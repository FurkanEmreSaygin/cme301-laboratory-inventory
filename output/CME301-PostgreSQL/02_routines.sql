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
