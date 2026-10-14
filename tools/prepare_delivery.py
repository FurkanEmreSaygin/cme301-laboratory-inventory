from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output' / 'CME301-PostgreSQL'
OUT.mkdir(parents=True, exist_ok=True)
downloads = ROOT / 'sql' / 'source'
source = (downloads/'schema.sql').read_text(encoding='utf-8-sig')
tables = source[source.index('CREATE TABLE role'):source.index('-- 5. FEFO issue procedure')]
tables = tables[:tables.rfind('---------------------------------------------------------------------------')]
tables = tables.replace('failed_logins  smallint', 'db_login       name         UNIQUE, -- optional individual PostgreSQL login mapping\n    failed_logins  smallint')
tables = tables.replace('parent_id      integer     REFERENCES location(location_id),', 'parent_id      integer     REFERENCES location(location_id),\n    CONSTRAINT ck_location_self CHECK (parent_id IS NULL OR parent_id <> location_id),')
tables = tables.replace("CONSTRAINT ck_transfer_target CHECK ((txn_type = 'TRANSFER') = (to_location_id IS NOT NULL))", "CONSTRAINT ck_transfer_target CHECK ((txn_type = 'TRANSFER') = (to_location_id IS NOT NULL)),\n    CONSTRAINT ck_transfer_different CHECK (to_location_id IS NULL OR to_location_id <> location_id)")
tables = tables.replace("(alert_type = 'LOW_STOCK' AND item_id IS NOT NULL) OR\n        (alert_type <> 'LOW_STOCK' AND lot_id IS NOT NULL)", "(alert_type = 'LOW_STOCK' AND item_id IS NOT NULL AND lot_id IS NULL) OR\n        (alert_type <> 'LOW_STOCK' AND lot_id IS NOT NULL AND item_id IS NULL)")
tables = tables.replace('line_no     smallint      NOT NULL,', 'line_no     smallint      NOT NULL CHECK (line_no > 0),')
tables = tables.replace('WHERE l.expiry_date <= current_date + 30 AND s.quantity > 0', 'WHERE l.expiry_date BETWEEN current_date AND current_date + 30 AND s.quantity > 0')
tables += '''
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
'''
header = '''-- CME301 Laboratory Inventory System / PostgreSQL 15+
-- Run once in an EMPTY lab schema; no existing objects are dropped.
-- DBeaver: open this file and Execute SQL Script (Alt+X).
-- 16 tables / 25 foreign keys. Expiry dates remain required per the agreed design.
BEGIN;
CREATE SCHEMA lab;
SET LOCAL search_path = lab, pg_catalog;
'''
(OUT/'01_schema.sql').write_text(header+tables+'\nCOMMIT;\n',encoding='utf-8')
routines = (ROOT/'tools/delivery_routines.sql').read_text(encoding='utf-8')
(OUT/'02_routines.sql').write_text(routines,encoding='utf-8')

# Preserve known identities for the supplied tests; fix the deliberately missing receipt.
sample=(downloads/'sample.sql').read_text(encoding='utf-8-sig')
sample=sample.replace("(8,6,'RECEIPT',12,3,now()-interval '15 days','initial'),", "(8,6,'RECEIPT',12,3,now()-interval '15 days','initial'),\n  (9,6,'RECEIPT',5,3,now()-interval '10 days','initial'),")
sample=sample.replace('-- receipts for lots 1-8 (lot 9 has no movement on purpose) and some issues in the last 30 days', '-- Complete opening receipts and subsequent issues: all current stock reconciles.')
sample += "\nINSERT INTO item_supplier(item_id,supplier_id,unit_price) VALUES (4,1,250),(7,3,45),(8,3,30),(9,2,950);\n"
sample += "INSERT INTO purchase_order(supplier_id,created_by) VALUES(1,3);\nINSERT INTO po_line(po_id,line_no,item_id,quantity,unit_price) SELECT max(po_id),1,1,10,120 FROM purchase_order;\nCALL lab.sp_refresh_alerts();\n"
(OUT/'03_sample.sql').write_text('-- Synthetic demonstration data. Run only once after 01 and 02.\nBEGIN;\nSET LOCAL search_path=lab,pg_catalog;\n'+sample+'\nCOMMIT;\n',encoding='utf-8')

roles=source[source.index('CREATE ROLE lab_admin'):]
roles=re.sub(r'CREATE ROLE (lab_\w+)\s+NOLOGIN;',r"DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='\1') THEN CREATE ROLE \1 NOLOGIN; END IF; END $$;",roles)
roles=roles.replace('public, pg_temp','lab, pg_catalog, pg_temp')
roles += '''
GRANT USAGE ON SCHEMA lab TO lab_admin, lab_manager, lab_technician, lab_viewer;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA lab TO lab_admin, lab_manager, lab_technician;
GRANT EXECUTE ON PROCEDURE sp_transfer_stock(integer,integer,integer,numeric,integer,text),
 sp_dispose_stock(integer,integer,numeric,integer,text) TO lab_admin,lab_manager,lab_technician;
GRANT EXECUTE ON PROCEDURE sp_refresh_alerts() TO lab_admin,lab_manager;
GRANT SELECT ON v_expired_lots TO lab_admin,lab_manager,lab_technician,lab_viewer;
GRANT SELECT ON v_stock_reconciliation TO lab_admin,lab_manager;
'''
(OUT/'04_roles.sql').write_text('-- Run as database owner with CREATEROLE (or postgres).\nBEGIN;\nSET LOCAL search_path=lab,pg_catalog;\n'+roles+'\nCOMMIT;\n',encoding='utf-8')

tests=(downloads/'tests.sql').read_text(encoding='utf-8-sig')
tests='\n'.join(s for s in tests.splitlines() if not s.startswith('\\'))
tests=tests.replace('CREATE TEMP TABLE res(id text, ok boolean, info text);','CREATE TEMP TABLE res(id text, ok boolean NOT NULL, info text);')
tests=tests.replace('expect_err(id text, stmt text)', 'expect_err(id text, stmt text, expected_state text)')
tests=tests.replace("INSERT INTO res VALUES (id,true,left(SQLERRM,70))", "INSERT INTO res VALUES (id,SQLSTATE = expected_state, SQLSTATE||': '||left(SQLERRM,70))")
states={'F01':'23505','F02':'23502','F03':'23503','F04':'23514','F05':'23514','F06':'23514','F07':'23514','F08':'23514','F09':'23514','F10':'23505','F11':'23514','F12':'23514','F13':'23514','F14':'23514','F15':'23503','F16':'23505','F17':'23514','F18':'23505','P02':'P0001','P03':'P0001','P04':'22023','P05':'22023','P06':'23503','P07':'23503','P09':'22023'}
tests=re.sub(r"(SELECT pg_temp.expect_err\('([FP]\d+) [^\n]*?\$\$)\);",lambda m:m[1]+",'"+states[m[2]]+"');",tests)
tests=tests.replace('CREATE ROLE public_nobody NOLOGIN;',"DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='public_nobody') THEN CREATE ROLE public_nobody NOLOGIN; END IF; END $$;\nGRANT USAGE ON SCHEMA lab TO public_nobody;")
tests=tests.replace("WHEN OTHERS THEN ok := true; msg := 'allowed (other error: '||left(SQLERRM,40)||')';", "WHEN OTHERS THEN RESET ROLE; INSERT INTO res VALUES(id,false,'unexpected '||SQLSTATE||': '||left(SQLERRM,70)); RETURN;")
tests=tests.replace("DELETE FROM purchase_order WHERE po_id=(SELECT max(po_id) FROM purchase_order);\nINSERT INTO res SELECT 'F19 PO line deleted with its PO (cascade)', (SELECT count(*)=0 FROM po_line), 'lines left: '||(SELECT count(*) FROM po_line);", "CREATE TEMP TABLE cascade_target AS SELECT max(po_id) AS po_id FROM purchase_order;\nDELETE FROM purchase_order WHERE po_id=(SELECT po_id FROM cascade_target);\nINSERT INTO res SELECT 'F19 PO line deleted with its PO (cascade)', NOT EXISTS(SELECT 1 FROM po_line WHERE po_id=(SELECT po_id FROM cascade_target)), 'target order removed';")
tests += '''
SELECT pg_temp.expect_err('E01 same-location transfer', $$CALL lab.sp_transfer_stock(2,2,2,1,3,'bad')$$, '22023');
SELECT pg_temp.expect_err('E02 mismatched receipt metadata', $$CALL lab.sp_receive_stock(1,'T-A1',NULL,current_date+99,1,2,3)$$, '22023');
SELECT pg_temp.expect_err('E03 self-parent location', $$UPDATE lab.location SET parent_id=location_id WHERE location_id=1$$, '23514');
SELECT pg_temp.expect_err('E04 multi-node location cycle', $$UPDATE lab.location SET parent_id=5 WHERE location_id=1$$, '23514');
SELECT pg_temp.expect_ok('E05 transfer', $$CALL lab.sp_transfer_stock(2,2,5,2,3,'transfer-test')$$);
INSERT INTO res SELECT 'E05b transfer updates both locations', (SELECT quantity=10 FROM stock WHERE lot_id=2 AND location_id=2) AND (SELECT quantity=2 FROM stock WHERE lot_id=2 AND location_id=5), '10 source / 2 target';
SELECT pg_temp.expect_ok('E06 disposal', $$CALL lab.sp_dispose_stock(2,5,1,3,'damaged')$$);
SELECT pg_temp.expect_err('E07 excessive disposal', $$CALL lab.sp_dispose_stock(2,5,99,3,'bad')$$,'P0001');
SELECT pg_temp.expect_err('E08 fractional precision', $$CALL lab.sp_issue_stock(1,0.001,3,'bad')$$,'22023');
UPDATE app_user SET is_active=false WHERE user_id=3;
SELECT pg_temp.expect_err('E09 inactive actor', $$CALL lab.sp_issue_stock(1,1,3,'bad')$$,'42501');
UPDATE app_user SET is_active=true WHERE user_id=3;
INSERT INTO res SELECT 'E10 stock matches complete ledger', NOT EXISTS(SELECT 1 FROM v_stock_reconciliation WHERE difference<>0), 'all lot / location balances';
CREATE TEMP TABLE alert_count AS SELECT count(*) AS n FROM alert WHERE status IN ('OPEN','ACKNOWLEDGED');
CALL lab.sp_refresh_alerts(); CALL lab.sp_refresh_alerts();
INSERT INTO res SELECT 'E11 alert refresh is idempotent', (SELECT count(*) FROM alert WHERE status IN ('OPEN','ACKNOWLEDGED'))=(SELECT n FROM alert_count), 'no duplicate active alerts';
INSERT INTO res SELECT 'E12 audit trigger writes records', EXISTS(SELECT 1 FROM audit_log WHERE table_name='stock'), 'stock audit present';
SELECT id, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, info FROM res ORDER BY id;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed, count(*) AS total FROM res;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM res WHERE NOT ok) THEN RAISE EXCEPTION 'Test suite failed'; END IF; END $$;
ROLLBACK;
'''
(OUT/'05_tests.sql').write_text('-- Run after 01-04 as postgres. All test mutations are rolled back. DBeaver compatible.\nBEGIN;\nSET LOCAL search_path=lab,pg_catalog;\n'+tests,encoding='utf-8')

ra=(downloads/'ra.sql').read_text(encoding='utf-8-sig')
ra=re.sub(r'^\\echo (.*)$',r'-- \1',ra,flags=re.M)
ra=ra.replace('SELECT DISTINCT catalog_no, name FROM item WHERE storage_temp_c = -80;', 'SELECT DISTINCT i.catalog_no, i.name FROM item i JOIN lot l USING(item_id) JOIN stock s USING(lot_id) JOIN location loc USING(location_id) WHERE loc.temp_celsius=-80 AND s.quantity>0;')
ra=ra.replace('SELECT c.name, COUNT(DISTINCT i.item_id) AS items, COALESCE(SUM(s.quantity),0) AS qty FROM category c LEFT JOIN item i USING(category_id) LEFT JOIN lot l USING(item_id) LEFT JOIN stock s USING(lot_id) GROUP BY c.name ORDER BY 1;', 'SELECT c.name, i.unit, COUNT(DISTINCT i.item_id) AS items, COALESCE(SUM(s.quantity),0) AS qty FROM category c LEFT JOIN item i USING(category_id) LEFT JOIN lot l USING(item_id) LEFT JOIN stock s USING(lot_id) GROUP BY c.name,i.unit ORDER BY 1,2;')
(OUT/'06_queries.sql').write_text('SET search_path=lab,pg_catalog;\n'+ra+'\n-- Expected result: zero discrepancies.\nSELECT * FROM v_stock_reconciliation WHERE difference<>0;\n',encoding='utf-8')
(OUT/'07_demo.sql').write_text('''-- FEFO demonstration: run in DBeaver; rolls back all changes.
BEGIN;
SET LOCAL search_path=lab,pg_catalog;
SELECT l.lot_no,l.expiry_date,s.quantity FROM lot l JOIN stock s USING(lot_id) WHERE l.item_id=1 ORDER BY l.expiry_date;
CALL lab.sp_issue_stock(1,8,3,'presentation-demo');
SELECT l.lot_no,l.expiry_date,s.quantity FROM lot l JOIN stock s USING(lot_id) WHERE l.item_id=1 ORDER BY l.expiry_date;
SELECT * FROM stock_transaction WHERE reason='presentation-demo';
SELECT * FROM v_low_stock;
SELECT * FROM v_expiring_lots;
SELECT * FROM v_expired_lots;
ROLLBACK;
''',encoding='utf-8')
(OUT/'00_install_all.sql').write_text('-- Run in the cme301_lab database as postgres. Executes 01-04.\n\n'+'\n\n'.join((OUT/f).read_text(encoding='utf-8') for f in ['01_schema.sql','02_routines.sql','03_sample.sql','04_roles.sql']),encoding='utf-8')
print('Created delivery SQL in',OUT)
