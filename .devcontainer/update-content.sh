#!/usr/bin/env bash
set -euxo pipefail

echo "=== updateContent user ==="
whoami
id

echo "=== filtered env ==="
env | grep -E 'SSL|REQUESTS|CURL|PIP|PYTHON' || true

echo "=== tool versions ==="
python3 --version
python3 -m pip --version

echo "=== pip https test ==="
python3 -m pip install --user requests

echo "=== python ssl defaults ==="
python3 - <<'PY'
import ssl
print(ssl.get_default_verify_paths())
PY
