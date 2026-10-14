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
