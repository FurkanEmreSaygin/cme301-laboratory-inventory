-- CME301 Laboratory Inventory System: schema draft for PostgreSQL 15 or newer
-- 16 tables (12 core + 4 optional), indexes, views, FEFO procedure, roles and privileges.
-- Phase 1 design draft: validated on PostgreSQL 18 with sample data; not yet reviewed by the team.

---------------------------------------------------------------------------
-- 1. Core tables
---------------------------------------------------------------------------
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
    CONSTRAINT ck_transfer_target CHECK ((txn_type = 'TRANSFER') = (to_location_id IS NOT NULL))
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
        (alert_type = 'LOW_STOCK' AND item_id IS NOT NULL) OR
        (alert_type <> 'LOW_STOCK' AND lot_id IS NOT NULL))
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
    line_no     smallint      NOT NULL,
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
WHERE l.expiry_date <= current_date + 30 AND s.quantity > 0
GROUP BY i.catalog_no, i.name, l.lot_no, l.expiry_date;

CREATE VIEW v_low_stock AS
SELECT i.item_id, i.catalog_no, i.name, COALESCE(t.total, 0) AS on_hand, i.min_stock
FROM item i
LEFT JOIN (SELECT l.item_id, SUM(s.quantity) AS total
           FROM lot l JOIN stock s ON s.lot_id = l.lot_id
           WHERE l.expiry_date >= current_date
           GROUP BY l.item_id) t ON t.item_id = i.item_id
WHERE i.is_active AND COALESCE(t.total, 0) < i.min_stock;

---------------------------------------------------------------------------
-- 5. FEFO issue procedure (all or nothing)
---------------------------------------------------------------------------
CREATE PROCEDURE sp_issue_stock(p_item_id integer, p_qty numeric, p_user_id integer, p_reason text DEFAULT NULL)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    r           record;
    v_remaining numeric := p_qty;
    v_take      numeric;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Quantity must be positive (got %)', p_qty;
    END IF;

    FOR r IN
        SELECT s.lot_id, s.location_id, s.quantity
        FROM stock s
        JOIN lot l ON l.lot_id = s.lot_id
        WHERE l.item_id = p_item_id
          AND s.quantity > 0
          AND l.expiry_date >= current_date
        ORDER BY l.expiry_date, l.lot_id, s.location_id
        FOR UPDATE OF s
    LOOP
        v_take := LEAST(v_remaining, r.quantity);
        UPDATE stock SET quantity = quantity - v_take
        WHERE lot_id = r.lot_id AND location_id = r.location_id;
        INSERT INTO stock_transaction (lot_id, location_id, txn_type, quantity, user_id, reason)
        VALUES (r.lot_id, r.location_id, 'ISSUE', v_take, p_user_id, p_reason);
        v_remaining := v_remaining - v_take;
        EXIT WHEN v_remaining = 0;
    END LOOP;

    IF v_remaining > 0 THEN
        RAISE EXCEPTION 'Insufficient unexpired stock for item %: short by %', p_item_id, v_remaining;
    END IF;
END;
$$;


-- Goods receipt: creates the lot (or adds to an existing one) and writes the RECEIPT transaction.
CREATE PROCEDURE sp_receive_stock(p_item_id integer, p_lot_no varchar, p_supplier_id integer, p_expiry date,
                                  p_qty numeric, p_location_id integer, p_user_id integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_lot integer;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Quantity must be positive (got %)', p_qty;
    END IF;
    SELECT lot_id INTO v_lot FROM lot WHERE item_id = p_item_id AND lot_no = p_lot_no;
    IF v_lot IS NULL THEN
        INSERT INTO lot (item_id, supplier_id, lot_no, expiry_date, initial_qty)
        VALUES (p_item_id, p_supplier_id, p_lot_no, p_expiry, p_qty) RETURNING lot_id INTO v_lot;
    END IF;
    INSERT INTO stock (lot_id, location_id, quantity) VALUES (v_lot, p_location_id, p_qty)
    ON CONFLICT (lot_id, location_id) DO UPDATE SET quantity = stock.quantity + EXCLUDED.quantity;
    INSERT INTO stock_transaction (lot_id, location_id, txn_type, quantity, user_id, reason)
    VALUES (v_lot, p_location_id, 'RECEIPT', p_qty, p_user_id, 'goods receipt');
END;
$$;

---------------------------------------------------------------------------
-- 6. Roles and privileges
---------------------------------------------------------------------------
CREATE ROLE lab_admin      NOLOGIN;
CREATE ROLE lab_manager    NOLOGIN;
CREATE ROLE lab_technician NOLOGIN;
CREATE ROLE lab_viewer     NOLOGIN;

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
