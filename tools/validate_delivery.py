from pathlib import Path
import subprocess, os, secrets, sys
from local_config import connection_settings, connection_environment

ROOT=Path(__file__).resolve().parents[1]
LOCAL=ROOT/'.local'
BIN=LOCAL/'postgres-runtime/pgsql/bin'
DATA=LOCAL/'postgres-data'
OUT=ROOT/'output/CME301-PostgreSQL'
PW=LOCAL/'postgres-password.txt'
LOCAL.mkdir(exist_ok=True)
settings=connection_settings()
if not PW.exists(): PW.write_text((settings['PGPASSWORD'] or secrets.token_urlsafe(24))+'\n',encoding='ascii')
env=connection_environment(); env['PGPASSWORD']=settings['PGPASSWORD'] or PW.read_text().strip()
flags=subprocess.CREATE_NO_WINDOW

def run(exe,args,check=True):
    r=subprocess.run([str(BIN/exe),*map(str,args)],capture_output=True,text=True,encoding='utf-8',errors='replace',env=env,creationflags=flags)
    if check and r.returncode:
        print(r.stdout); print(r.stderr); raise SystemExit(r.returncode)
    return r

if not (DATA/'PG_VERSION').exists():
    r=run('initdb.exe',['-D',DATA,'-U','postgres','--pwfile',PW,'--auth=scram-sha-256','--locale=C','-E','UTF8'])
    print('PostgreSQL initialized',flush=True)
status=run('pg_ctl.exe',['-D',DATA,'status'],False)
if status.returncode:
    with (LOCAL/'pg-start.log').open('w',encoding='utf-8') as start_log:
        subprocess.run([str(BIN/'pg_ctl.exe'),'-D',str(DATA),'-l',str(LOCAL/'postgres.log'),'-o',f"-h 127.0.0.1 -p {settings['PGPORT']}",'-w','start'],stdout=start_log,stderr=start_log,env=env,creationflags=flags,check=True)
    print(f"PostgreSQL running at 127.0.0.1:{settings['PGPORT']}",flush=True)
base=['-h',settings['PGHOST'],'-p',settings['PGPORT'],'-U',settings['PGUSER'],'-v','ON_ERROR_STOP=1']
dbname=sys.argv[1] if len(sys.argv)>1 else settings['PGDATABASE']
if not dbname.replace('_','').isalnum(): raise ValueError('Unsafe database name')
existing=run('psql.exe',base+['-d','postgres','-Atc',f"SELECT 1 FROM pg_database WHERE datname='{dbname}'"]).stdout.strip()
if not existing: run('psql.exe',base+['-d','postgres','-c',f'CREATE DATABASE {dbname}'])
start_file=sys.argv[2] if len(sys.argv)>2 else '01_schema.sql'
files=['01_schema.sql','02_routines.sql','03_sample.sql','04_roles.sql','05_tests.sql','06_queries.sql','07_demo.sql']
for file in files[files.index(start_file):]:
    r=run('psql.exe',base+['-d',dbname,'-f',OUT/file],False)
    (OUT/(file.replace('.sql','.log'))).write_text(r.stdout+'\n'+r.stderr,encoding='utf-8')
    print(file, 'OK' if r.returncode==0 else 'FAILED',flush=True)
    if r.returncode:
        print(r.stdout[-8000:]); print(r.stderr[-4000:]); raise SystemExit(r.returncode)
check=run('psql.exe',base+['-d',dbname,'-c',"SELECT version(); SELECT count(*) AS tables FROM information_schema.tables WHERE table_schema='lab' AND table_type='BASE TABLE'; SELECT count(*) AS foreign_keys FROM information_schema.table_constraints WHERE constraint_schema='lab' AND constraint_type='FOREIGN KEY'; SELECT * FROM lab.v_stock_reconciliation WHERE difference<>0;"])
(OUT/'validation.log').write_text(check.stdout,encoding='utf-8')
print(check.stdout,flush=True)
(LOCAL/'connection.txt').write_text(f"Host: {settings['PGHOST']}\nPort: {settings['PGPORT']}\nDatabase: {dbname}\nUser: {settings['PGUSER']}\nPassword: project .env PGPASSWORD (not printed)\n",encoding='utf-8')
