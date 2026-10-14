-- Run in the cme301_lab database as postgres. Executes 01-04.

-- CME301 Laboratory Inventory System / PostgreSQL 15+
-- Run once in an EMPTY lab schema; no existing objects are dropped.
-- DBeaver: open this file and Execute SQL Script (Alt+X).
-- 16 tables / 25 foreign keys. Expiry dates remain required per the agreed design.
BEGIN;
CREATE SCHEMA lab;
SET LOCAL search_path = lab, pg_catalog;
CREATE TABLE role (
    role_id      smallint     PRIMARY KEY,
    role_name    varchar(30)  NOT NULL UNIQUE,
    description  varchar(200)
);

CREATE TABLE app_user (
    user_id        integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username       varchar(50)  NOT NULL UNIQUE,
    password_hash  text         NOT NULL,
    full_name      varchar(100) NOT NULL,
    email          varchar(120) UNIQUE,
    role_id        smallint     NOT NULL REFERENCES role(role_id),
    is_active      boolean      NOT NULL DEFAULT true,
    db_login       name         UNIQUE, -- optional individual PostgreSQL login mapping
    failed_logins  smallint     NOT NULL DEFAULT 0 CHECK (failed_logins >= 0),
    created_at     timestamptz  NOT NULL DEFAULT now()
);

CREATE TABLE category (
    category_id  smallint    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         varchar(60) NOT NULL UNIQUE,
    description  varchar(200)
);

-- ITEM is the supertype of REAGENT, CONSUMABLE and CHEMICAL (ISA in the ER model).
-- The three subtypes are mapped to one table with a discriminator column (item_type).
CREATE TABLE item (
    item_id         integer       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    catalog_no      varchar(40)   NOT NULL UNIQUE,
    barcode         varchar(50)   UNIQUE,
    name            varchar(150)  NOT NULL,
    item_type       varchar(12)   NOT NULL CHECK (item_type IN ('REAGENT','CONSUMABLE','CHEMICAL')),
    category_id     smallint      NOT NULL REFERENCES category(category_id),
    unit            varchar(20)   NOT NULL,
    min_stock       numeric(12,2) NOT NULL DEFAULT 0 CHECK (min_stock >= 0),
    reorder_qty     numeric(12,2) CHECK (reorder_qty > 0),
    storage_temp_c  smallint,
    cas_number      varchar(20),
    hazard_class    varchar(30),
    pack_size       integer       CHECK (pack_size > 0),
    is_active       boolean       NOT NULL DEFAULT true,
    CONSTRAINT ck_reagent_temp    CHECK (item_type <> 'REAGENT'    OR storage_temp_c IS NOT NULL),
    CONSTRAINT ck_chemical_only   CHECK (item_type =  'CHEMICAL'   OR (cas_number IS NULL AND hazard_class IS NULL)),
    CONSTRAINT ck_consumable_only CHECK (item_type =  'CONSUMABLE' OR pack_size IS NULL)
);

CREATE TABLE supplier (
    supplier_id     integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            varchar(120) NOT NULL UNIQUE,
    contact_person  varchar(100),
    email           varchar(120),
    phone           varchar(30),
    lead_time_days  smallint     NOT NULL DEFAULT 7 CHECK (lead_time_days >= 0)
);

CREATE TABLE item_supplier (
    item_id             integer       NOT NULL REFERENCES item(item_id),
    supplier_id         integer       NOT NULL REFERENCES supplier(supplier_id),
    supplier_item_code  varchar(40),
    unit_price          numeric(12,2) NOT NULL CHECK (unit_price >= 0),
    currency            char(3)       NOT NULL DEFAULT 'TRY',
    PRIMARY KEY (item_id, supplier_id)
);

CREATE TABLE location (
    location_id    integer     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name           varchar(80) NOT NULL,
    location_type  varchar(10) NOT NULL CHECK (location_type IN ('ROOM','CABINET','FRIDGE','FREEZER','SHELF')),
    temp_celsius   smallint,
    parent_id      integer     REFERENCES location(location_id),
    CONSTRAINT ck_location_self CHECK (parent_id IS NULL OR parent_id <> location_id),
    UNIQUE NULLS NOT DISTINCT (parent_id, name)
);

CREATE TABLE lot (
    lot_id         integer       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id        integer       NOT NULL REFERENCES item(item_id),
    supplier_id    integer       REFERENCES supplier(supplier_id),
    lot_no         varchar(40)   NOT NULL,
    received_date  date          NOT NULL DEFAULT current_date,
    expiry_date    date          NOT NULL,
    initial_qty    numeric(12,2) NOT NULL CHECK (initial_qty > 0),
    CONSTRAINT uq_lot       UNIQUE (item_id, lot_no),
    CONSTRAINT ck_lot_dates CHECK (expiry_date > received_date)
);

-- Current quantity per lot and location. Changed only by the stored procedures.
CREATE TABLE stock (
    lot_id       integer       NOT NULL REFERENCES lot(lot_id),
    location_id  integer       NOT NULL REFERENCES location(location_id),
    quantity     numeric(12,2) NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    PRIMARY KEY (lot_id, location_id)
);

-- History of every movement. For a TRANSFER, location_id is the source and to_location_id the target.
CREATE TABLE stock_transaction (
    txn_id          bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lot_id          integer       NOT NULL REFERENCES lot(lot_id) ON DELETE RESTRICT,
    location_id     integer       NOT NULL REFERENCES location(location_id),
    to_location_id  integer       REFERENCES location(location_id),
    txn_type        varchar(10)   NOT NULL CHECK (txn_type IN ('RECEIPT','ISSUE','TRANSFER','DISPOSAL')),
    quantity        numeric(12,2) NOT NULL CHECK (quantity > 0),
    user_id         integer       NOT NULL REFERENCES app_user(user_id),
    txn_time        timestamptz   NOT NULL DEFAULT now(),
    reason          varchar(200),
    CONSTRAINT ck_transfer_target CHECK ((txn_type = 'TRANSFER') = (to_location_id IS NOT NULL)),
    CONSTRAINT ck_transfer_different CHECK (to_location_id IS NULL OR to_location_id <> location_id)
);

CREATE TABLE alert (
    alert_id     bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    alert_type   varchar(12)  NOT NULL CHECK (alert_type IN ('LOW_STOCK','EXPIRY_SOON','EXPIRED')),
    item_id      integer      REFERENCES item(item_id),
    lot_id       integer      REFERENCES lot(lot_id),
    message      varchar(200) NOT NULL,
    status       varchar(12)  NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','ACKNOWLEDGED','RESOLVED')),
    created_at   timestamptz  NOT NULL DEFAULT now(),
    resolved_by  integer      REFERENCES app_user(user_id),
    resolved_at  timestamptz,
    CONSTRAINT ck_alert_target CHECK (
        (alert_type = 'LOW_STOCK' AND item_id IS NOT NULL AND lot_id IS NULL) OR
        (alert_type <> 'LOW_STOCK' AND lot_id IS NOT NULL AND item_id IS NULL))
);

CREATE TABLE audit_log (
    log_id      bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     integer     REFERENCES app_user(user_id),
    table_name  varchar(40) NOT NULL,
    record_id   varchar(60) NOT NULL,
    action      varchar(6)  NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    old_value   jsonb,
    new_value   jsonb,
    log_time    timestamptz NOT NULL DEFAULT now()
);

---------------------------------------------------------------------------
-- 2. Optional tables (purchase orders, equipment, maintenance)
---------------------------------------------------------------------------
CREATE TABLE purchase_order (
    po_id          integer     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_id    integer     NOT NULL REFERENCES supplier(supplier_id),
    created_by     integer     NOT NULL REFERENCES app_user(user_id),
    approved_by    integer     REFERENCES app_user(user_id),
    status         varchar(10) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','SUBMITTED','APPROVED','RECEIVED','CANCELLED')),
    order_date     date        NOT NULL DEFAULT current_date,
    expected_date  date,
    CONSTRAINT ck_po_approver CHECK (approved_by IS NULL OR approved_by <> created_by),
    CONSTRAINT ck_po_dates    CHECK (expected_date IS NULL OR expected_date >= order_date)
);

-- Weak entity: a line exists only with its purchase order.
CREATE TABLE po_line (
    po_id       integer       NOT NULL REFERENCES purchase_order(po_id) ON DELETE CASCADE,
    line_no     smallint      NOT NULL CHECK (line_no > 0),
    item_id     integer       NOT NULL REFERENCES item(item_id),
    quantity    numeric(12,2) NOT NULL CHECK (quantity > 0),
    unit_price  numeric(12,2) NOT NULL CHECK (unit_price >= 0),
    PRIMARY KEY (po_id, line_no)
);

CREATE TABLE equipment (
    equipment_id   integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name           varchar(120) NOT NULL,
    serial_no      varchar(60)  NOT NULL UNIQUE,
    location_id    integer      REFERENCES location(location_id),
    status         varchar(12)  NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','MAINTENANCE','RETIRED')),
    purchase_date  date
);

CREATE TABLE maintenance (
    maint_id      integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    equipment_id  integer      NOT NULL REFERENCES equipment(equipment_id),
    maint_type    varchar(12)  NOT NULL CHECK (maint_type IN ('MAINTENANCE','CALIBRATION','REPAIR')),
    due_date      date         NOT NULL,
    done_date     date,
    performed_by  integer      REFERENCES app_user(user_id),
    notes         varchar(200),
    CONSTRAINT ck_maint_done CHECK (done_date IS NULL OR performed_by IS NOT NULL)
);

---------------------------------------------------------------------------
-- 3. Indexes (primary key and UNIQUE constraints already create B+-tree indexes)
---------------------------------------------------------------------------
CREATE INDEX idx_item_category      ON item (category_id);
CREATE INDEX idx_lot_item_expiry    ON lot (item_id, expiry_date);                  -- FEFO and expiry scan (composite)
CREATE INDEX idx_stock_location     ON stock (location_id);
CREATE INDEX idx_txn_lot_time       ON stock_transaction (lot_id, txn_time);        -- history of a lot (composite)
CREATE INDEX idx_txn_user           ON stock_transaction (user_id);
CREATE INDEX idx_alert_open         ON alert (created_at) WHERE status = 'OPEN';    -- partial index
CREATE INDEX idx_audit_table_time   ON audit_log (table_name, log_time);
-- Hash index: kept for the index experiment only; production lookups use the UNIQUE B+-tree on barcode.
CREATE INDEX idx_item_barcode_hash  ON item USING hash (barcode);

---------------------------------------------------------------------------
-- 4. Views
---------------------------------------------------------------------------
CREATE VIEW v_stock_by_location AS
SELECT i.catalog_no, i.name AS item_name, l.lot_no, l.expiry_date,
       loc.name AS location, s.quantity, i.unit
FROM stock s
JOIN lot l       ON l.lot_id = s.lot_id
JOIN item i      ON i.item_id = l.item_id
JOIN location loc ON loc.location_id = s.location_id
WHERE s.quantity > 0;

CREATE VIEW v_expiring_lots AS
SELECT i.catalog_no, i.name AS item_name, l.lot_no, l.expiry_date,
       (l.expiry_date - current_date) AS days_left,
       SUM(s.quantity) AS quantity
FROM lot l
JOIN item i ON i.item_id = l.item_id
JOIN stock s ON s.lot_id = l.lot_id
WHERE l.expiry_date BETWEEN current_date AND current_date + 30 AND s.quantity > 0
GROUP BY i.catalog_no, i.name, l.lot_no, l.expiry_date;

CREATE VIEW v_low_stock AS
SELECT i.item_id, i.catalog_no, i.name, COALESCE(t.total, 0) AS on_hand, i.min_stock
FROM item i
LEFT JOIN (SELECT l.item_id, SUM(s.quantity) AS total
           FROM lot l JOIN stock s ON s.lot_id = l.lot_id
           WHERE l.expiry_date >= current_date
           GROUP BY l.item_id) t ON t.item_id = i.item_id
WHERE i.is_active AND COALESCE(t.total, 0) < i.min_stock;


-- Additional integrity and reporting objects.
CREATE UNIQUE INDEX uq_alert_open_item ON alert (alert_type, item_id)
 WHERE status IN ('OPEN','ACKNOWLEDGED') AND item_id IS NOT NULL;
CREATE UNIQUE INDEX uq_alert_open_lot ON alert (alert_type, lot_id)
 WHERE status IN ('OPEN','ACKNOWLEDGED') AND lot_id IS NOT NULL;
CREATE INDEX idx_lot_expiry ON lot (expiry_date);
CREATE INDEX idx_location_parent ON location (parent_id);
CREATE VIEW v_expired_lots AS
 SELECT i.catalog_no, i.name AS item_name, l.lot_no, l.expiry_date, SUM(s.quantity) AS quantity
 FROM lot l JOIN item i USING (item_id) JOIN stock s USING (lot_id)
 WHERE l.expiry_date < current_date AND s.quantity > 0
 GROUP BY i.catalog_no, i.name, l.lot_no, l.expiry_date;
CREATE VIEW v_stock_reconciliation AS
 WITH movements AS (
   SELECT lot_id, location_id,
          CASE WHEN txn_type='RECEIPT' THEN quantity ELSE -quantity END AS delta
   FROM stock_transaction
   UNION ALL
   SELECT lot_id, to_location_id, quantity FROM stock_transaction WHERE txn_type='TRANSFER'
 ), ledger AS (
   SELECT lot_id, location_id, SUM(delta) AS ledger_qty FROM movements GROUP BY lot_id, location_id
 )
 SELECT COALESCE(s.lot_id,l.lot_id) AS lot_id, COALESCE(s.location_id,l.location_id) AS location_id,
        COALESCE(s.quantity,0) AS stock_qty, COALESCE(l.ledger_qty,0) AS ledger_qty,
        COALESCE(s.quantity,0)-COALESCE(l.ledger_qty,0) AS difference
 FROM stock s FULL JOIN ledger l USING (lot_id,location_id);

COMMIT;


-- CME301 business rules, atomic stock operations, alerts and audit.
BEGIN;
SET LOCAL search_path=lab,pg_catalog;

CREATE FUNCTION fn_validate_qty(p_qty numeric) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
 IF p_qty IS NULL OR p_qty::text IN ('NaN','Infinity','-Infinity') OR p_qty<=0 OR round(p_qty,2)<>p_qty THEN
   RAISE EXCEPTION 'Quantity must be positive with at most two decimal places' USING ERRCODE='22023';
 END IF;
END $$;

CREATE FUNCTION fn_actor(p_user_id integer) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=lab,pg_catalog,pg_temp AS $$
DECLARE u app_user%ROWTYPE; v_owner name; v_role text;
BEGIN
 SELECT * INTO u FROM app_user WHERE user_id=p_user_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown user %',p_user_id USING ERRCODE='23503'; END IF;
 IF NOT u.is_active THEN RAISE EXCEPTION 'Inactive user' USING ERRCODE='42501'; END IF;
 SELECT pg_get_userbyid(datdba) INTO v_owner FROM pg_database WHERE datname=current_database();
 IF session_user<>v_owner AND u.db_login IS DISTINCT FROM session_user THEN
   RAISE EXCEPTION 'Actor does not match database login' USING ERRCODE='42501';
 END IF;
 v_role:=current_setting('role',true);
 IF v_role IN ('lab_admin','lab_manager','lab_technician','lab_viewer') AND
    u.role_id<>(CASE v_role WHEN 'lab_admin' THEN 1 WHEN 'lab_manager' THEN 2 WHEN 'lab_technician' THEN 3 ELSE 4 END) THEN
   RAISE EXCEPTION 'Actor role mismatch' USING ERRCODE='42501';
 END IF;
 PERFORM set_config('lab.actor_id',p_user_id::text,true);
END $$;

CREATE FUNCTION fn_location_cycle() RETURNS trigger
LANGUAGE plpgsql SET search_path=lab,pg_catalog,pg_temp AS $$ BEGIN
 PERFORM pg_advisory_xact_lock(301,1);
 IF NEW.parent_id IS NOT NULL AND EXISTS(
   WITH RECURSIVE ancestors AS (
     SELECT location_id,parent_id FROM location WHERE location_id=NEW.parent_id
     UNION SELECT l.location_id,l.parent_id FROM location l JOIN ancestors a ON l.location_id=a.parent_id
   ) SELECT 1 FROM ancestors WHERE location_id=NEW.location_id
 ) THEN RAISE EXCEPTION 'Location hierarchy cannot contain a cycle' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER tr_location_cycle BEFORE INSERT OR UPDATE OF parent_id ON location
 FOR EACH ROW EXECUTE FUNCTION fn_location_cycle();

CREATE FUNCTION fn_audit() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=lab,pg_catalog,pg_temp AS $$
DECLARE before_data jsonb; after_data jsonb; actor integer; rid text;
BEGIN
 IF TG_OP<>'INSERT' THEN before_data:=to_jsonb(OLD); END IF;
 IF TG_OP<>'DELETE' THEN after_data:=to_jsonb(NEW); END IF;
 -- Password hashes are deliberately excluded from audit payloads.
 before_data:=before_data-'password_hash'; after_data:=after_data-'password_hash';
 actor:=NULLIF(current_setting('lab.actor_id',true),'')::integer;
 IF actor IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app_user WHERE user_id=actor) THEN actor:=NULL; END IF;
 SELECT string_agg(COALESCE(after_data,before_data)->>k,':') INTO rid FROM unnest(TG_ARGV) k;
 INSERT INTO audit_log(user_id,table_name,record_id,action,old_value,new_value)
 VALUES(actor,TG_TABLE_NAME,COALESCE(rid,'?'),TG_OP,before_data,after_data);
 RETURN NULL;
END $$;
DO $$
DECLARE r record;
BEGIN
 FOR r IN SELECT * FROM (VALUES
 ('role','role_id',NULL),('app_user','user_id',NULL),('category','category_id',NULL),
 ('item','item_id',NULL),('supplier','supplier_id',NULL),('item_supplier','item_id','supplier_id'),
 ('location','location_id',NULL),('lot','lot_id',NULL),('stock','lot_id','location_id'),
 ('stock_transaction','txn_id',NULL),('alert','alert_id',NULL),('purchase_order','po_id',NULL),
 ('po_line','po_id','line_no'),('equipment','equipment_id',NULL),('maintenance','maint_id',NULL)
 ) x(t,k1,k2) LOOP
 EXECUTE format('CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON lab.%I FOR EACH ROW EXECUTE FUNCTION lab.fn_audit(%L%s)',
 'tr_audit_'||r.t,r.t,r.k1,CASE WHEN r.k2 IS NULL THEN '' ELSE ','||quote_literal(r.k2) END);
 END LOOP;
END $$;

CREATE PROCEDURE sp_refresh_alerts()
LANGUAGE plpgsql SECURITY DEFINER SET search_path=lab,pg_catalog,pg_temp AS $$ BEGIN
 INSERT INTO alert(alert_type,item_id,message)
 SELECT 'LOW_STOCK',item_id,'Available stock below minimum: '||catalog_no FROM v_low_stock
 ON CONFLICT DO NOTHING;
 INSERT INTO alert(alert_type,lot_id,message)
 SELECT CASE WHEN l.expiry_date<current_date THEN 'EXPIRED' ELSE 'EXPIRY_SOON' END,l.lot_id,
        'Expiry check: lot '||l.lot_no||' / '||l.expiry_date
 FROM lot l WHERE l.expiry_date<=current_date+30 AND EXISTS(SELECT 1 FROM stock s WHERE s.lot_id=l.lot_id AND s.quantity>0)
 ON CONFLICT DO NOTHING;
 UPDATE alert a SET status='RESOLVED',resolved_at=now()
 WHERE a.status IN ('OPEN','ACKNOWLEDGED') AND (
  (a.alert_type='LOW_STOCK' AND NOT EXISTS(SELECT 1 FROM v_low_stock v WHERE v.item_id=a.item_id)) OR
  (a.alert_type='EXPIRY_SOON' AND NOT EXISTS(SELECT 1 FROM lot l JOIN stock s USING(lot_id) WHERE l.lot_id=a.lot_id AND l.expiry_date BETWEEN current_date AND current_date+30 AND s.quantity>0)) OR
  (a.alert_type='EXPIRED' AND NOT EXISTS(SELECT 1 FROM lot l JOIN stock s USING(lot_id) WHERE l.lot_id=a.lot_id AND l.expiry_date<current_date AND s.quantity>0))
 );
END $$;

CREATE PROCEDURE sp_issue_stock(p_item_id integer,p_qty numeric,p_user_id integer,p_reason text DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=lab,pg_catalog,pg_temp AS $$
DECLARE r record; remaining numeric:=p_qty; take_qty numeric;
BEGIN
 PERFORM fn_validate_qty(p_qty); PERFORM fn_actor(p_user_id);
 PERFORM 1 FROM item WHERE item_id=p_item_id AND is_active FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown or inactive item %',p_item_id USING ERRCODE='23503'; END IF;
 FOR r IN SELECT s.lot_id,s.location_id,s.quantity FROM stock s JOIN lot l USING(lot_id)
   WHERE l.item_id=p_item_id AND s.quantity>0 AND l.expiry_date>=current_date
   ORDER BY l.expiry_date,l.lot_id,s.location_id FOR UPDATE OF s LOOP
   take_qty:=LEAST(remaining,r.quantity);
   UPDATE stock SET quantity=quantity-take_qty WHERE lot_id=r.lot_id AND location_id=r.location_id;
   INSERT INTO stock_transaction(lot_id,location_id,txn_type,quantity,user_id,reason)
     VALUES(r.lot_id,r.location_id,'ISSUE',take_qty,p_user_id,p_reason);
   remaining:=remaining-take_qty; EXIT WHEN remaining=0;
 END LOOP;
 IF remaining>0 THEN RAISE EXCEPTION 'Insufficient unexpired stock: short by %',remaining; END IF;
 CALL sp_refresh_alerts();
END $$;

CREATE PROCEDURE sp_receive_stock(p_item_id integer,p_lot_no varchar,p_supplier_id integer,p_expiry date,
 p_qty numeric,p_location_id integer,p_user_id integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=lab,pg_catalog,pg_temp AS $$
DECLARE r lot%ROWTYPE; v_lot integer;
BEGIN
 PERFORM fn_validate_qty(p_qty); PERFORM fn_actor(p_user_id);
 IF p_expiry IS NULL OR p_expiry<=current_date OR p_lot_no IS NULL OR btrim(p_lot_no)='' THEN
   RAISE EXCEPTION 'Receipt requires a nonempty lot number and future expiry date' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM item WHERE item_id=p_item_id AND is_active FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown or inactive item' USING ERRCODE='23503'; END IF;
 SELECT * INTO r FROM lot WHERE item_id=p_item_id AND lot_no=p_lot_no FOR UPDATE;
 IF FOUND THEN
   IF r.expiry_date IS DISTINCT FROM p_expiry OR r.supplier_id IS DISTINCT FROM p_supplier_id THEN
     RAISE EXCEPTION 'Existing lot expiry or supplier differs' USING ERRCODE='22023'; END IF;
   v_lot:=r.lot_id;
 ELSE
   INSERT INTO lot(item_id,supplier_id,lot_no,expiry_date,initial_qty)
     VALUES(p_item_id,p_supplier_id,p_lot_no,p_expiry,p_qty) RETURNING lot_id INTO v_lot;
 END IF;
 INSERT INTO stock(lot_id,location_id,quantity) VALUES(v_lot,p_location_id,p_qty)
 ON CONFLICT(lot_id,location_id) DO UPDATE SET quantity=stock.quantity+EXCLUDED.quantity;
 INSERT INTO stock_transaction(lot_id,location_id,txn_type,quantity,user_id,reason)
 VALUES(v_lot,p_location_id,'RECEIPT',p_qty,p_user_id,'goods receipt');
 CALL sp_refresh_alerts();
END $$;

CREATE PROCEDURE sp_transfer_stock(p_lot_id integer,p_from integer,p_to integer,p_qty numeric,p_user_id integer,p_reason text DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=lab,pg_catalog,pg_temp AS $$
DECLARE v_item integer; v_qty numeric;
BEGIN
 PERFORM fn_validate_qty(p_qty); PERFORM fn_actor(p_user_id);
 IF p_from IS NULL OR p_to IS NULL OR p_from=p_to THEN RAISE EXCEPTION 'Transfer locations must differ' USING ERRCODE='22023'; END IF;
 SELECT item_id INTO v_item FROM lot WHERE lot_id=p_lot_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown lot' USING ERRCODE='23503'; END IF;
 PERFORM 1 FROM item WHERE item_id=v_item FOR UPDATE;
 SELECT quantity INTO v_qty FROM stock WHERE lot_id=p_lot_id AND location_id=p_from FOR UPDATE;
 IF v_qty IS NULL OR v_qty<p_qty THEN RAISE EXCEPTION 'Insufficient source stock'; END IF;
 UPDATE stock SET quantity=quantity-p_qty WHERE lot_id=p_lot_id AND location_id=p_from;
 INSERT INTO stock(lot_id,location_id,quantity) VALUES(p_lot_id,p_to,p_qty)
 ON CONFLICT(lot_id,location_id) DO UPDATE SET quantity=stock.quantity+EXCLUDED.quantity;
 INSERT INTO stock_transaction(lot_id,location_id,to_location_id,txn_type,quantity,user_id,reason)
 VALUES(p_lot_id,p_from,p_to,'TRANSFER',p_qty,p_user_id,p_reason);
 CALL sp_refresh_alerts();
END $$;

CREATE PROCEDURE sp_dispose_stock(p_lot_id integer,p_location integer,p_qty numeric,p_user_id integer,p_reason text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=lab,pg_catalog,pg_temp AS $$
DECLARE v_item integer; v_qty numeric;
BEGIN
 PERFORM fn_validate_qty(p_qty); PERFORM fn_actor(p_user_id);
 IF p_reason IS NULL OR btrim(p_reason)='' THEN RAISE EXCEPTION 'Disposal reason is required' USING ERRCODE='22023'; END IF;
 SELECT item_id INTO v_item FROM lot WHERE lot_id=p_lot_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown lot' USING ERRCODE='23503'; END IF;
 PERFORM 1 FROM item WHERE item_id=v_item FOR UPDATE;
 SELECT quantity INTO v_qty FROM stock WHERE lot_id=p_lot_id AND location_id=p_location FOR UPDATE;
 IF v_qty IS NULL OR v_qty<p_qty THEN RAISE EXCEPTION 'Insufficient stock for disposal'; END IF;
 UPDATE stock SET quantity=quantity-p_qty WHERE lot_id=p_lot_id AND location_id=p_location;
 INSERT INTO stock_transaction(lot_id,location_id,txn_type,quantity,user_id,reason)
 VALUES(p_lot_id,p_location,'DISPOSAL',p_qty,p_user_id,p_reason);
 CALL sp_refresh_alerts();
END $$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA lab FROM PUBLIC;
REVOKE EXECUTE ON ALL PROCEDURES IN SCHEMA lab FROM PUBLIC;
COMMIT;


-- Synthetic demonstration data. Run only once after 01 and 02.
BEGIN;
SET LOCAL search_path=lab,pg_catalog;
-- Small sample data set used only to validate the design (dates are relative to today).
INSERT INTO role VALUES (1,'Admin','Manages users and all data'),(2,'Lab Manager','Approves orders, manages catalogue'),
       (3,'Technician','Records stock movements'),(4,'Viewer','Read-only');
INSERT INTO app_user (username, password_hash, full_name, email, role_id) VALUES
  ('admin','sample-not-a-real-hash','Admin User','admin@example.org',1),
  ('manager','sample-not-a-real-hash','Manager User','manager@example.org',2),
  ('tech1','sample-not-a-real-hash','Technician One','tech1@example.org',3),
  ('viewer1','sample-not-a-real-hash','Viewer One','viewer1@example.org',4);
INSERT INTO category (name) VALUES ('PCR Reagents'),('Antibodies'),('Plastic Consumables'),('Chemicals');
INSERT INTO item (catalog_no, name, item_type, category_id, unit, min_stock, storage_temp_c, cas_number, hazard_class, pack_size) VALUES
  ('TAQ-001','Taq DNA Polymerase','REAGENT',1,'mL',5,-20,NULL,NULL,NULL),
  ('DNTP-010','dNTP Mix','REAGENT',1,'mL',2,-20,NULL,NULL,NULL),
  ('BUF-PCR','10x PCR Buffer','REAGENT',1,'mL',5,-20,NULL,NULL,NULL),
  ('ANT-007','Primary antibody anti-X','REAGENT',2,'vial',1,-80,NULL,NULL,NULL),
  ('TIP-200','Pipette tips 200 uL (box of 96)','CONSUMABLE',3,'box',20,NULL,NULL,NULL,96),
  ('TUBE-15','Microcentrifuge tubes 1.5 mL (bag)','CONSUMABLE',3,'bag',10,NULL,NULL,NULL,500),
  ('ETOH-96','Ethanol 96%','CHEMICAL',4,'L',4,NULL,'64-17-5','Flammable',NULL),
  ('NAOH-1M','Sodium hydroxide 1 M','CHEMICAL',4,'L',2,NULL,'1310-73-2','Corrosive',NULL),
  ('KIT-RNA','RNA extraction kit','REAGENT',1,'kit',1,4,NULL,NULL,NULL);
INSERT INTO supplier (name, lead_time_days) VALUES ('Alpha Biotech',7),('Beta Scientific',14),('Gamma Lab Supply',3);
INSERT INTO item_supplier (item_id, supplier_id, unit_price) VALUES
  (1,1,120),(2,1,80),(3,1,40),(1,2,115),(2,2,85),(5,3,30),(6,3,12);
INSERT INTO location (name, location_type, temp_celsius, parent_id) VALUES
  ('Lab Room A','ROOM',22,NULL),('Freezer -20 #1','FREEZER',-20,1),('Freezer -80 #1','FREEZER',-80,1),
  ('Fridge +4 #1','FRIDGE',4,1),('Shelf 1','SHELF',-20,2),('Cabinet C1','CABINET',22,1);
INSERT INTO lot (item_id, lot_no, received_date, expiry_date, initial_qty) VALUES
  (1,'T-A1', current_date-200, current_date+10, 20),
  (1,'T-A2', current_date-30,  current_date+120,20),
  (2,'D-1',  current_date-60,  current_date+200,10),
  (3,'B-1',  current_date-90,  current_date+20, 10),
  (4,'AB-1', current_date-20,  current_date+300,3),
  (5,'TP-1', current_date-40,  current_date+400,50),
  (6,'TU-1', current_date-400, current_date-5,  30),
  (7,'E-1',  current_date-15,  current_date+60, 12),
  (8,'N-1',  current_date-10,  current_date+90, 5);
INSERT INTO stock (lot_id, location_id, quantity) VALUES
  (1,2,5),(2,2,15),(3,2,1.5),(4,2,8),(5,3,3),(6,6,40),(7,6,30),(8,6,12),(9,6,5);
-- Complete opening receipts and subsequent issues: all current stock reconciles.
INSERT INTO stock_transaction (lot_id, location_id, txn_type, quantity, user_id, txn_time, reason) VALUES
  (1,2,'RECEIPT',20,3,now()-interval '200 days','initial'),(2,2,'RECEIPT',20,3,now()-interval '30 days','initial'),
  (3,2,'RECEIPT',10,3,now()-interval '60 days','initial'),(4,2,'RECEIPT',10,3,now()-interval '90 days','initial'),
  (5,3,'RECEIPT',3,3,now()-interval '20 days','initial'),(6,6,'RECEIPT',50,3,now()-interval '40 days','initial'),
  (7,6,'RECEIPT',30,3,now()-interval '400 days','initial'),(8,6,'RECEIPT',12,3,now()-interval '15 days','initial'),
  (9,6,'RECEIPT',5,3,now()-interval '10 days','initial'),
  (1,2,'ISSUE',15,3,now()-interval '5 days','run'),(2,2,'ISSUE',5,3,now()-interval '3 days','run'),
  (3,2,'ISSUE',8.5,3,now()-interval '10 days','run'),(4,2,'ISSUE',2,3,now()-interval '20 days','run'),
  (6,6,'ISSUE',10,3,now()-interval '12 days','run');
-- fix: stock of lot 2 was 15 after a 5-unit issue
-- (lot 2: 20 received, 5 issued = 15 on hand)
INSERT INTO equipment (name, serial_no, location_id) VALUES ('Real-time PCR cycler','RT-0001',1),('Centrifuge','CF-0002',1);
INSERT INTO maintenance (equipment_id, maint_type, due_date, done_date, performed_by) VALUES
  (1,'CALIBRATION',current_date-10,current_date-9,3),(1,'MAINTENANCE',current_date+20,NULL,NULL),(2,'MAINTENANCE',current_date-3,current_date-2,3);

INSERT INTO item_supplier(item_id,supplier_id,unit_price) VALUES (4,1,250),(7,3,45),(8,3,30),(9,2,950);
INSERT INTO purchase_order(supplier_id,created_by) VALUES(1,3);
INSERT INTO po_line(po_id,line_no,item_id,quantity,unit_price) SELECT max(po_id),1,1,10,120 FROM purchase_order;
CALL lab.sp_refresh_alerts();

COMMIT;


-- Run as database owner with CREATEROLE (or postgres).
BEGIN;
SET LOCAL search_path=lab,pg_catalog;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='lab_admin') THEN CREATE ROLE lab_admin NOLOGIN; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='lab_manager') THEN CREATE ROLE lab_manager NOLOGIN; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='lab_technician') THEN CREATE ROLE lab_technician NOLOGIN; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='lab_viewer') THEN CREATE ROLE lab_viewer NOLOGIN; END IF; END $$;

-- Procedures are executable by PUBLIC by default: revoke, then grant per role.
REVOKE ALL ON PROCEDURE sp_receive_stock(integer, varchar, integer, date, numeric, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE sp_receive_stock(integer, varchar, integer, date, numeric, integer, integer)
      TO lab_admin, lab_manager, lab_technician;
REVOKE ALL ON PROCEDURE sp_issue_stock(integer, numeric, integer, text) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE sp_issue_stock(integer, numeric, integer, text)
      TO lab_admin, lab_manager, lab_technician;

-- Admin
GRANT SELECT, INSERT, UPDATE, DELETE ON role, app_user, category, item, supplier, item_supplier,
      location, lot, purchase_order, po_line, equipment, maintenance TO lab_admin;
GRANT SELECT, UPDATE ON alert TO lab_admin;
GRANT SELECT ON stock, stock_transaction, audit_log TO lab_admin;
GRANT SELECT ON v_stock_by_location, v_expiring_lots, v_low_stock TO lab_admin;

-- Lab manager (no access to password hashes; no direct writes to stock or history)
GRANT SELECT ON role, category, item, supplier, item_supplier, location, lot, stock, stock_transaction,
      alert, audit_log, purchase_order, po_line, equipment, maintenance TO lab_manager;
GRANT SELECT (user_id, username, full_name, email, role_id, is_active, created_at) ON app_user TO lab_manager;
GRANT INSERT, UPDATE ON category, item, supplier, location, equipment, maintenance, po_line TO lab_manager;
GRANT INSERT, UPDATE, DELETE ON item_supplier TO lab_manager;
GRANT INSERT ON purchase_order TO lab_manager;
GRANT UPDATE (status, approved_by, expected_date) ON purchase_order TO lab_manager;
GRANT UPDATE (supplier_id, expiry_date) ON lot TO lab_manager;
GRANT UPDATE (status, resolved_by, resolved_at) ON alert TO lab_manager;
GRANT SELECT ON v_stock_by_location, v_expiring_lots, v_low_stock TO lab_manager;

-- Technician (stock changes only through procedures; purchase orders only as DRAFT)
GRANT SELECT ON category, item, supplier, location, lot, stock, stock_transaction, alert,
      purchase_order, po_line, equipment, maintenance TO lab_technician;
GRANT INSERT (supplier_id, created_by, expected_date) ON purchase_order TO lab_technician;
GRANT INSERT (po_id, line_no, item_id, quantity, unit_price) ON po_line TO lab_technician;
GRANT INSERT ON maintenance TO lab_technician;
GRANT SELECT ON v_stock_by_location, v_expiring_lots, v_low_stock TO lab_technician;

-- Viewer (read-only; no suppliers, prices, users, history or audit log)
GRANT SELECT ON category, item, location, lot, alert, equipment, maintenance TO lab_viewer;
GRANT SELECT ON v_stock_by_location, v_expiring_lots, v_low_stock TO lab_viewer;

GRANT USAGE ON SCHEMA lab TO lab_admin, lab_manager, lab_technician, lab_viewer;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA lab TO lab_admin, lab_manager, lab_technician;
GRANT EXECUTE ON PROCEDURE sp_transfer_stock(integer,integer,integer,numeric,integer,text),
 sp_dispose_stock(integer,integer,numeric,integer,text) TO lab_admin,lab_manager,lab_technician;
GRANT EXECUTE ON PROCEDURE sp_refresh_alerts() TO lab_admin,lab_manager;
GRANT SELECT ON v_expired_lots TO lab_admin,lab_manager,lab_technician,lab_viewer;
GRANT SELECT ON v_stock_reconciliation TO lab_admin,lab_manager;

COMMIT;
