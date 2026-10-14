from pathlib import Path
import os,subprocess,time
from local_config import connection_settings, connection_environment
ROOT=Path(__file__).resolve().parents[1]; OUT=ROOT/'output/CME301-PostgreSQL'
settings=connection_settings();env=connection_environment()
base=[str(ROOT/'.local/postgres-runtime/pgsql/bin/psql.exe'),'-h',settings['PGHOST'],'-p',settings['PGPORT'],'-U',settings['PGUSER'],'-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose']
flags=subprocess.CREATE_NO_WINDOW
def sql(db,s):return subprocess.run(base+['-d',db,'-Atc',s],env=env,capture_output=True,text=True,creationflags=flags)
db='cme301_concurrency'
r=sql('postgres','CREATE DATABASE '+db)
if r.returncode: print(r.stderr);raise SystemExit(1)
for name in ['01_schema.sql','02_routines.sql','03_sample.sql','04_roles.sql']:
 r=subprocess.run(base+['-d',db,'-f',str(OUT/name)],env=env,capture_output=True,text=True,creationflags=flags)
 if r.returncode:print(r.stderr);raise SystemExit(1)
def overlap(first,second):
 a=subprocess.Popen(base+['-d',db,'-c',first],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,creationflags=flags)
 time.sleep(0.4)
 b=subprocess.Popen(base+['-d',db,'-c',second],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,creationflags=flags)
 ao,ae=a.communicate(timeout=20);bo,be=b.communicate(timeout=20)
 return a.returncode,b.returncode,ao+ae+bo+be
ac,bc,details=overlap("BEGIN; CALL lab.sp_issue_stock(3,6,3,'concurrent-issue'); SELECT pg_sleep(2); COMMIT;", "BEGIN; CALL lab.sp_issue_stock(3,6,3,'concurrent-issue'); COMMIT;")
balance=sql(db,'SELECT quantity FROM lab.stock WHERE lot_id=4 AND location_id=2').stdout.strip()
assert ac==0 and bc!=0 and 'P0001' in details and balance=='2.00', (ac,bc,balance,details)
report='Concurrent issue: PASS (8 available; two requests of 6; one succeeds; final quantity 2.00)\n'+details
ac,bc,details=overlap("BEGIN; CALL lab.sp_receive_stock(1,'CONCURRENT-LOT',1,current_date+500,2,2,3); SELECT pg_sleep(2); COMMIT;", "BEGIN; CALL lab.sp_receive_stock(1,'CONCURRENT-LOT',1,current_date+500,2,2,3); COMMIT;")
result=sql(db,"SELECT count(*),SUM(s.quantity) FROM lab.lot l JOIN lab.stock s USING(lot_id) WHERE l.lot_no='CONCURRENT-LOT'").stdout.strip()
assert ac==0 and bc==0 and result=='1|4.00',(ac,bc,result,details)
report+='\nConcurrent receipt: PASS (one lot, total quantity 4.00)\n'+details
assert sql(db,'SELECT count(*) FROM lab.v_stock_reconciliation WHERE difference<>0').stdout.strip()=='0'
report+='\nFinal ledger reconciliation: PASS (zero discrepancies)\n'
(OUT/'concurrency.log').write_text(report,encoding='utf-8')
print(report.splitlines()[0]); print('Concurrent receipt: PASS'); print('Ledger reconciliation: PASS')
