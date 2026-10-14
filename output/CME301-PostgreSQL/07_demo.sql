-- FEFO demonstration: run in DBeaver; rolls back all changes.
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
