"""Save a server-only key interactively without echoing it or placing it in argv."""
import getpass
import os
from pathlib import Path

root = Path(__file__).resolve().parents[1]
key = getpass.getpass('DeepSeek API key (hidden): ').strip()
if not key or '\n' in key or '\r' in key:
    raise SystemExit('Invalid key')
path = root / '.env'
lines = path.read_text().splitlines() if path.exists() else []
lines = [line for line in lines if not line.startswith('COOK_DEEPSEEK_API_KEY=')]
lines.append('COOK_DEEPSEEK_API_KEY=' + key)
path.write_text('\n'.join(lines) + '\n')
os.chmod(path, 0o600)
print('Server key saved in ignored .env (mode 0600).')
