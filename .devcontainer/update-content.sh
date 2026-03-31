#!/usr/bin/env bash
set -euxo pipefail

echo "=== updateContent user ==="
whoami
id

echo "=== filtered env ==="
env | grep -E 'SSL|REQUESTS|CURL|NODE|NPM|PIP|PYTHON' || true

echo "=== tool versions ==="
node --version
npm --version
python3 --version
python3 -m pip --version

echo "=== npm https test ==="
npm view lodash version

echo "=== pip https test ==="
python3 -m pip install --user requests

echo "=== python ssl defaults ==="
python3 - <<'PY'
import ssl
print(ssl.get_default_verify_paths())
PY
