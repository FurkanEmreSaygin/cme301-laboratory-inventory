"""Read the project .env without printing or persisting connection secrets."""
from pathlib import Path
import os

ROOT = Path(__file__).resolve().parents[1]


def connection_settings():
    values = {}
    path = ROOT / '.env'
    if path.exists():
        for line in path.read_text(encoding='utf-8-sig').splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            key, separator, value = line.partition('=')
            if separator:
                values[key.strip()] = value.strip().strip('"').strip("'")
    defaults = {'PGHOST': '127.0.0.1', 'PGPORT': '54329', 'PGDATABASE': 'cme301_lab', 'PGUSER': 'postgres', 'PGSCHEMA': 'lab'}
    settings = {key: os.environ.get(key, values.get(key, default)) for key, default in defaults.items()}
    settings['PGPASSWORD'] = os.environ.get('PGPASSWORD', values.get('PGPASSWORD', ''))
    if not settings['PGPASSWORD']:
        legacy_path = ROOT / '.local' / 'postgres-password.txt'
        if legacy_path.exists():
            settings['PGPASSWORD'] = legacy_path.read_text().strip()
    return settings


def connection_environment():
    env = os.environ.copy()
    env.update(connection_settings())
    env['PGCLIENTENCODING'] = 'UTF8'
    return env
