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
