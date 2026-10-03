"""Generate secrets locally, once. Never prints secret values."""
import base64, os, secrets
from pathlib import Path
path = Path(__file__).resolve().parents[1] / '.env'
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as f:
    f.write('DB_PASSWORD=' + secrets.token_urlsafe(32) + '\n')
    f.write('JWT_SECRET=' + secrets.token_urlsafe(64) + '\n')
    f.write('ENCRYPTION_KEY=' + base64.urlsafe_b64encode(secrets.token_bytes(32)).decode() + '\n')
print('Created .env with restrictive permissions. Keep it out of Git.')
