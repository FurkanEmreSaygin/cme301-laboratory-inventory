from pathlib import Path
import subprocess, json
from local_config import connection_settings
ROOT=Path(__file__).resolve().parents[1]
settings=connection_settings(); pw=settings['PGPASSWORD']
config={'connections':{'cme301-postgresql':{'provider':'postgresql','driver':'postgres-jdbc','name':'CME301 Laboratory','save-password':False,'configuration':{'host':settings['PGHOST'],'port':settings['PGPORT'],'database':settings['PGDATABASE'],'url':f"jdbc:postgresql://{settings['PGHOST']}:{settings['PGPORT']}/{settings['PGDATABASE']}",'type':'dev','auth-model':'native','auth-properties':{'userName':settings['PGUSER']}}}}}
p=ROOT/'.local/dbeaver-workspace/General/.dbeaver/data-sources.json'
p.parent.mkdir(parents=True,exist_ok=True)
p.write_text(json.dumps(config,indent=2),encoding='utf-8')
con='id=cme301-postgresql|name=CME301 Laboratory|create=false|user='+settings['PGUSER']+'|password='+pw+'|save=false|savePassword=false|connect=true'
subprocess.Popen(['C:/Program Files/DBeaver/dbeaver.exe','-data',str(ROOT/'.local/dbeaver-workspace'),'-connect',con,'-vmargs','-Djava.nio.channels.spi.SelectorProvider=sun.nio.ch.WindowsSelectorProvider'],cwd='C:/Program Files/DBeaver',creationflags=subprocess.CREATE_NO_WINDOW)
print('DBeaver connection dispatched; credentials were not printed.')
