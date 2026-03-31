#!/usr/bin/env bash
set -euxo pipefail

mkdir -p "$HOME/.cache/pip"
sudo chown "$(id -u):$(id -g)" "$HOME/.cache" "$HOME/.cache/pip" || true

echo "=== user ==="
whoami
id

echo "=== env ==="
env | sort
echo "=== filtered env ==="
env | grep -E 'SSL|REQUESTS|CURL|PIP|PYTHON' || true

echo "=== ssl bundle ==="
ls -l /etc/ssl/certs || true
ls -l /etc/ssl/certs/ca-certificates.crt || true

echo "=== python ssl defaults ==="
python3 - <<'PY'
import ssl
print(ssl.get_default_verify_paths())
PY

echo "=== root curl ==="
sudo bash -lc '
  set -euxo pipefail
  whoami
  id
  env | grep -E "SSL|REQUESTS|CURL|PIP|PYTHON" || true
  curl -Ivs https://github.com >/tmp/root-curl.txt 2>&1 || {
    cat /tmp/root-curl.txt
    exit 1
  }
  cat /tmp/root-curl.txt
'

echo "=== user curl ==="
curl -Ivs https://github.com >/tmp/user-curl.txt 2>&1 || {
  cat /tmp/user-curl.txt
  exit 1
}
cat /tmp/user-curl.txt
