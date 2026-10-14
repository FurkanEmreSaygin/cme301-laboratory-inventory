from pathlib import Path
import os,subprocess,json,xml.etree.ElementTree as E,shutil
from local_config import connection_settings, connection_environment
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/CME301-PostgreSQL/diagrams'
settings=connection_settings();env=connection_environment()
sql="""SELECT json_build_object(
 'tables',(SELECT json_agg(table_name ORDER BY table_name) FROM information_schema.tables WHERE table_schema='lab' AND table_type='BASE TABLE'),
 'foreign_keys',(SELECT json_agg(json_build_object('name',conname,'table',cl.relname,'reference',ref.relname))
 FROM pg_constraint co JOIN pg_class cl ON cl.oid=co.conrelid JOIN pg_class ref ON ref.oid=co.confrelid
 WHERE co.contype='f' AND co.connamespace='lab'::regnamespace));"""
r=subprocess.run([str(ROOT/'.local/postgres-runtime/pgsql/bin/psql.exe'),'-h',settings['PGHOST'],'-p',settings['PGPORT'],'-U',settings['PGUSER'],'-d',settings['PGDATABASE'],'-Atc',sql],capture_output=True,text=True,env=env,check=True,creationflags=subprocess.CREATE_NO_WINDOW)
meta=json.loads(r.stdout); (OUT/'schema-metadata.json').write_text(json.dumps(meta,indent=2),encoding='utf-8')
full={t:(50+(i%4)*380,80+(i//4)*420) for i,t in enumerate([
 'role','app_user','supplier','item_supplier','category','item','lot','location',
 'alert','audit_log','stock_transaction','stock','maintenance','equipment','po_line','purchase_order'])}
core={'supplier':(60,100),'item_supplier':(430,100),'item':(800,100),'category':(1170,100),
      'app_user':(60,580),'stock_transaction':(430,580),'lot':(800,580),'stock':(1170,580),'location':(1170,1060)}
for filename,title,positions in [('CME301-Tam.erd','CME301 - 16 Tables',full),('CME301-Stok.erd','CME301 - Stock and FEFO',core)]:
 diagram=E.Element('diagram',version='1',name=title)
 ds=E.SubElement(E.SubElement(diagram,'entities'),'data-source',id='cme301-postgresql')
 ids={t:str(i+1) for i,t in enumerate(positions)}
 for t,(x,y) in positions.items():
  color='232,225,243' if t in ('role','app_user','audit_log','alert') else '222,240,236' if t in ('stock','item_supplier') else '233,240,250'
  e=E.SubElement(ds,'entity',id=ids[t],name=t,**{'fq-name':'lab.'+t,'x':str(x),'y':str(y),'color-bg':color,'color-fg':'23,38,60'})
  E.SubElement(e,'path',name='lab');E.SubElement(e,'path',name=settings['PGDATABASE'])
 rel=E.SubElement(diagram,'relations')
 for fk in meta['foreign_keys']:
  if fk['table'] in ids and fk['reference'] in ids:
   E.SubElement(rel,'relation',name=fk['name'],type='fk',**{'pk-ref':ids[fk['reference']],'fk-ref':ids[fk['table']]})
 E.indent(diagram)
 E.ElementTree(diagram).write(OUT/filename,encoding='utf-8',xml_declaration=True)
 project=ROOT/'.local/dbeaver-workspace/General/Diagrams'
 project.mkdir(parents=True,exist_ok=True)
 shutil.copyfile(OUT/filename,project/filename)
 print(filename,len(positions),'tables')
