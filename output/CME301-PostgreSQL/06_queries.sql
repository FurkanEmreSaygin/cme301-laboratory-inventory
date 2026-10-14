SET search_path=lab,pg_catalog;
-- RA1 selection: lots expiring within 30 days
SELECT lot_no, expiry_date FROM lot WHERE expiry_date BETWEEN current_date AND current_date+30 ORDER BY 2;
-- RA2 projection: items stored at -80
SELECT DISTINCT i.catalog_no, i.name FROM item i JOIN lot l USING(item_id) JOIN stock s USING(lot_id) JOIN location loc USING(location_id) WHERE loc.temp_celsius=-80 AND s.quantity>0;
-- RA3 join: item-lot-stock-location
SELECT i.catalog_no, l.lot_no, loc.name, s.quantity FROM item i JOIN lot l USING(item_id) JOIN stock s USING(lot_id) JOIN location loc USING(location_id) WHERE s.quantity>0 ORDER BY 1,2;
-- RA4 grouping + outer join: items below minimum
SELECT i.catalog_no, COALESCE(SUM(s.quantity),0) AS on_hand, i.min_stock FROM item i LEFT JOIN lot l ON l.item_id=i.item_id AND l.expiry_date>=current_date LEFT JOIN stock s ON s.lot_id=l.lot_id GROUP BY i.item_id HAVING COALESCE(SUM(s.quantity),0) < i.min_stock ORDER BY 1;
-- RA5 difference: items with no movement in 30 days
SELECT catalog_no FROM item EXCEPT SELECT i.catalog_no FROM item i JOIN lot l USING(item_id) JOIN stock_transaction t USING(lot_id) WHERE t.txn_time >= now()-interval '30 days' ORDER BY 1;
-- RA6 union: low-stock or expiring items
SELECT catalog_no FROM v_low_stock UNION SELECT catalog_no FROM v_expiring_lots ORDER BY 1;
-- RA7 intersection: items offered by supplier 1 and 2
SELECT item_id FROM item_supplier WHERE supplier_id=1 INTERSECT SELECT item_id FROM item_supplier WHERE supplier_id=2;
-- RA8 grouping: stock per category
SELECT c.name, i.unit, COUNT(DISTINCT i.item_id) AS items, COALESCE(SUM(s.quantity),0) AS qty FROM category c LEFT JOIN item i USING(category_id) LEFT JOIN lot l USING(item_id) LEFT JOIN stock s USING(lot_id) GROUP BY c.name,i.unit ORDER BY 1,2;
-- RA9 division: suppliers that offer ALL items of a required set (TAQ-001, DNTP-010)
SELECT sp.name FROM supplier sp WHERE NOT EXISTS (SELECT 1 FROM item i WHERE i.catalog_no IN ('TAQ-001','DNTP-010') AND NOT EXISTS (SELECT 1 FROM item_supplier x WHERE x.item_id=i.item_id AND x.supplier_id=sp.supplier_id)) ORDER BY 1;
-- RA10 self-join: location and parent
SELECT c.name AS location, p.name AS parent FROM location c LEFT JOIN location p ON p.location_id=c.parent_id ORDER BY c.location_id;
-- ROP: reorder point = avg daily use(90d) * lead time + safety stock (safety = 1.65*sd*sqrt(L) here simplified to 20% of d*L)
WITH d AS (SELECT l.item_id, SUM(t.quantity)/90.0 AS dbar FROM stock_transaction t JOIN lot l USING(lot_id) WHERE t.txn_type='ISSUE' AND t.txn_time>=now()-interval '90 days' GROUP BY l.item_id)
SELECT i.catalog_no, ROUND(d.dbar,3) AS dbar, sp.lead_time_days, ROUND(d.dbar*sp.lead_time_days*1.2,2) AS rop FROM d JOIN item i USING(item_id) JOIN item_supplier isu USING(item_id) JOIN supplier sp USING(supplier_id) ORDER BY 1,3;

-- Expected result: zero discrepancies.
SELECT * FROM v_stock_reconciliation WHERE difference<>0;
