\set QUIET on
\o /dev/null
CREATE TEMP TABLE res(id text, ok boolean, info text);
CREATE FUNCTION pg_temp.expect_err(id text, stmt text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE stmt; INSERT INTO res VALUES (id,false,'no error raised');
  EXCEPTION WHEN OTHERS THEN INSERT INTO res VALUES (id,true,left(SQLERRM,70)); END;
END $$;
CREATE FUNCTION pg_temp.expect_ok(id text, stmt text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE stmt; INSERT INTO res VALUES (id,true,'ok');
  EXCEPTION WHEN OTHERS THEN INSERT INTO res VALUES (id,false,left(SQLERRM,70)); END;
END $$;

-- ---- single-fault constraint tests (run as superuser: only the constraints are exercised)
SELECT pg_temp.expect_err('F01 duplicate catalog_no',$$INSERT INTO item(catalog_no,name,item_type,category_id,unit,storage_temp_c) VALUES ('TAQ-001','x','REAGENT',1,'mL',-20)$$);
SELECT pg_temp.expect_err('F02 NULL name',$$INSERT INTO item(catalog_no,name,item_type,category_id,unit,storage_temp_c) VALUES ('X1',NULL,'REAGENT',1,'mL',-20)$$);
SELECT pg_temp.expect_err('F03 unknown category (FK)',$$INSERT INTO item(catalog_no,name,item_type,category_id,unit,storage_temp_c) VALUES ('X2','x','REAGENT',99,'mL',-20)$$);
SELECT pg_temp.expect_err('F04 invalid item_type',$$INSERT INTO item(catalog_no,name,item_type,category_id,unit) VALUES ('X3','x','TOY',1,'mL')$$);
SELECT pg_temp.expect_err('F05 reagent without temperature',$$INSERT INTO item(catalog_no,name,item_type,category_id,unit) VALUES ('X4','x','REAGENT',1,'mL')$$);
SELECT pg_temp.expect_err('F06 CAS number on a reagent',$$INSERT INTO item(catalog_no,name,item_type,category_id,unit,storage_temp_c,cas_number) VALUES ('X5','x','REAGENT',1,'mL',4,'1-1-1')$$);
SELECT pg_temp.expect_err('F07 pack_size on a chemical',$$INSERT INTO item(catalog_no,name,item_type,category_id,unit,pack_size) VALUES ('X6','x','CHEMICAL',4,'L',10)$$);
SELECT pg_temp.expect_err('F08 negative min_stock',$$INSERT INTO item(catalog_no,name,item_type,category_id,unit,min_stock,storage_temp_c) VALUES ('X7','x','REAGENT',1,'mL',-1,4)$$);
SELECT pg_temp.expect_err('F09 expiry before receipt',$$INSERT INTO lot(item_id,lot_no,received_date,expiry_date,initial_qty) VALUES (1,'BAD',current_date,current_date-1,5)$$);
SELECT pg_temp.expect_err('F10 duplicate lot number for item',$$INSERT INTO lot(item_id,lot_no,expiry_date,initial_qty) VALUES (1,'T-A1',current_date+100,5)$$);
SELECT pg_temp.expect_err('F11 zero initial quantity',$$INSERT INTO lot(item_id,lot_no,expiry_date,initial_qty) VALUES (1,'ZERO',current_date+100,0)$$);
SELECT pg_temp.expect_err('F12 negative stock',$$UPDATE stock SET quantity=-1 WHERE lot_id=1$$);
SELECT pg_temp.expect_err('F13 transfer without target',$$INSERT INTO stock_transaction(lot_id,location_id,txn_type,quantity,user_id) VALUES (1,2,'TRANSFER',1,3)$$);
SELECT pg_temp.expect_err('F14 PO approved by its creator',$$INSERT INTO purchase_order(supplier_id,created_by,approved_by) VALUES (1,2,2)$$);
SELECT pg_temp.expect_err('F15 delete item that has lots (FK)',$$DELETE FROM item WHERE item_id=1$$);
SELECT pg_temp.expect_err('F16 duplicate sibling location',$$INSERT INTO location(name,location_type,parent_id) VALUES ('Shelf 1','SHELF',2)$$);
SELECT pg_temp.expect_err('F17 alert without target',$$INSERT INTO alert(alert_type,message) VALUES ('EXPIRED','x')$$);
SELECT pg_temp.expect_err('F18 duplicate username',$$INSERT INTO app_user(username,password_hash,full_name,role_id) VALUES ('admin','h','x',1)$$);

-- weak entity cascade
INSERT INTO purchase_order(supplier_id,created_by) VALUES (1,3);
INSERT INTO po_line VALUES (currval(pg_get_serial_sequence('purchase_order','po_id')),1,1,5,10);
DELETE FROM purchase_order WHERE po_id=(SELECT max(po_id) FROM purchase_order);
INSERT INTO res SELECT 'F19 PO line deleted with its PO (cascade)', (SELECT count(*)=0 FROM po_line), 'lines left: '||(SELECT count(*) FROM po_line);

-- ---- FEFO
SELECT pg_temp.expect_ok('P01 FEFO issue 8 of item 1',$$CALL sp_issue_stock(1,8,3,'test')$$);
INSERT INTO res SELECT 'P01b takes 5 from T-A1 first, then 3 from T-A2',
  (SELECT quantity FROM stock WHERE lot_id=1)=0 AND (SELECT quantity FROM stock WHERE lot_id=2)=12,
  'T-A1='||(SELECT quantity FROM stock WHERE lot_id=1)||' T-A2='||(SELECT quantity FROM stock WHERE lot_id=2);
INSERT INTO res SELECT 'P01c two ISSUE rows written', (SELECT count(*)=2 FROM stock_transaction WHERE reason='test'), '';
SELECT pg_temp.expect_err('P02 over-issue is refused',$$CALL sp_issue_stock(1,1000,3,'x')$$);
INSERT INTO res SELECT 'P02b over-issue leaves stock unchanged (rollback)', (SELECT sum(quantity) FROM stock WHERE lot_id IN (1,2))=12, '';
SELECT pg_temp.expect_err('P03 expired lot is never issued',$$CALL sp_issue_stock(6,1,3,'x')$$);
SELECT pg_temp.expect_err('P04 negative quantity',$$CALL sp_issue_stock(1,-5,3,'x')$$);
SELECT pg_temp.expect_err('P05 zero quantity',$$CALL sp_issue_stock(1,0,3,'x')$$);
SELECT pg_temp.expect_err('P06 unknown user',$$CALL sp_issue_stock(2,0.5,999,'x')$$);
SELECT pg_temp.expect_err('P07 unknown item (nothing to issue)',$$CALL sp_issue_stock(999,1,3,'x')$$);
SELECT pg_temp.expect_ok('P08 goods receipt',$$CALL sp_receive_stock(1,'T-A3',1,current_date+300,10,2,3)$$);
SELECT pg_temp.expect_err('P09 receipt with expired date',$$CALL sp_receive_stock(1,'T-OLD',1,current_date-1,10,2,3)$$);
-- compound fault: batch of three issues, third fails, all rolled back
DO $$ BEGIN
  BEGIN
    CALL sp_issue_stock(2,1,3,'batch'); CALL sp_issue_stock(3,1,3,'batch'); CALL sp_issue_stock(3,9999,3,'batch');
    INSERT INTO res VALUES ('C01 batch of 3, third fails',false,'no error');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO res VALUES ('C01 batch of 3, third fails: whole batch rolled back',
      (SELECT count(*)=0 FROM stock_transaction WHERE reason='batch'), 'batch rows left: '||(SELECT count(*) FROM stock_transaction WHERE reason='batch'));
  END; END $$;

CREATE ROLE public_nobody NOLOGIN;
CREATE FUNCTION pg_temp.as_role(id text, r text, stmt text, expect_ok boolean) RETURNS void LANGUAGE plpgsql AS $$
DECLARE ok boolean; msg text;
BEGIN
  BEGIN
    EXECUTE format('SET LOCAL ROLE %I', r); EXECUTE stmt; ok := true; msg := 'allowed';
  EXCEPTION WHEN insufficient_privilege THEN ok := false; msg := 'denied';
            WHEN OTHERS THEN ok := true; msg := 'allowed (other error: '||left(SQLERRM,40)||')';
  END;
  RESET ROLE;
  INSERT INTO res VALUES (id, ok = expect_ok, r||': '||msg);
END $$;
SELECT pg_temp.as_role('R01 viewer reads item','lab_viewer','SELECT * FROM item',true);
SELECT pg_temp.as_role('R02 viewer reads stock table','lab_viewer','SELECT * FROM stock',false);
SELECT pg_temp.as_role('R03 viewer reads view','lab_viewer','SELECT * FROM v_stock_by_location',true);
SELECT pg_temp.as_role('R04 viewer cannot see suppliers','lab_viewer','SELECT * FROM supplier',false);
SELECT pg_temp.as_role('R05 viewer cannot insert item','lab_viewer',$$INSERT INTO item(catalog_no,name,item_type,category_id,unit) VALUES ('V1','x','CONSUMABLE',3,'box')$$,false);
SELECT pg_temp.as_role('R06 viewer cannot issue','lab_viewer','CALL sp_issue_stock(2,1,3)',false);
SELECT pg_temp.as_role('R07 technician issues stock','lab_technician','CALL sp_issue_stock(2,1,3,''tech'')',true);
SELECT pg_temp.as_role('R08 technician cannot UPDATE stock directly','lab_technician','UPDATE stock SET quantity=999',false);
SELECT pg_temp.as_role('R09 technician cannot DELETE history','lab_technician','DELETE FROM stock_transaction',false);
SELECT pg_temp.as_role('R10 technician cannot read audit_log','lab_technician','SELECT * FROM audit_log',false);
SELECT pg_temp.as_role('R11 technician cannot read password hashes','lab_technician','SELECT password_hash FROM app_user',false);
SELECT pg_temp.as_role('R12 technician cannot create item','lab_technician',$$INSERT INTO item(catalog_no,name,item_type,category_id,unit) VALUES ('V2','x','CONSUMABLE',3,'box')$$,false);
SELECT pg_temp.as_role('R13 technician creates DRAFT PO','lab_technician','INSERT INTO purchase_order(supplier_id,created_by) VALUES (1,3)',true);
SELECT pg_temp.as_role('R14 technician cannot set PO status','lab_technician',$$INSERT INTO purchase_order(supplier_id,created_by,status) VALUES (1,3,'APPROVED')$$,false);
SELECT pg_temp.as_role('R15 manager cannot read password hashes','lab_manager','SELECT password_hash FROM app_user',false);
SELECT pg_temp.as_role('R16 manager reads usernames','lab_manager','SELECT username FROM app_user',true);
SELECT pg_temp.as_role('R17 manager approves PO','lab_manager','UPDATE purchase_order SET status=''APPROVED'', approved_by=2',true);
SELECT pg_temp.as_role('R18 manager adds an item','lab_manager',$$INSERT INTO item(catalog_no,name,item_type,category_id,unit) VALUES ('V3','x','CONSUMABLE',3,'box')$$,true);
SELECT pg_temp.as_role('R19 manager cannot UPDATE stock directly','lab_manager','UPDATE stock SET quantity=999',false);
SELECT pg_temp.as_role('R20 manager cannot UPDATE audit_log','lab_manager','UPDATE audit_log SET action=''X''',false);
SELECT pg_temp.as_role('R21 admin cannot DELETE audit_log','lab_admin','DELETE FROM audit_log',false);
SELECT pg_temp.as_role('R22 admin manages users','lab_admin',$$INSERT INTO app_user(username,password_hash,full_name,role_id) VALUES ('u9','h','n',3)$$,true);
SELECT pg_temp.as_role('R23 admin cannot UPDATE stock directly','lab_admin','UPDATE stock SET quantity=999',false);
SELECT pg_temp.as_role('R24 admin issues stock','lab_admin','CALL sp_issue_stock(2,0.5,1,''adm'')',true);
SELECT pg_temp.as_role('R25 PUBLIC cannot execute procedure','public_nobody','CALL sp_issue_stock(2,1,3)',false);

\o
\set QUIET off
SELECT id, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, info FROM res ORDER BY id;
SELECT count(*) FILTER (WHERE ok) AS passed, count(*) FILTER (WHERE NOT ok) AS failed, count(*) AS total FROM res;
