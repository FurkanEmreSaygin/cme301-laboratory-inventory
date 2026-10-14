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
