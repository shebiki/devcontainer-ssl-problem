#!/usr/bin/env bash
set -euxo pipefail

echo "=== [onCreateCommand] user ==="
whoami
id

echo "=== [onCreateCommand] python version (root) ==="
sudo python3 --version

echo "=== [onCreateCommand] python version (vscode) ==="
python3 --version

echo "=== [onCreateCommand] node version (root) ==="
sudo bash -lc 'node --version'

echo "=== [onCreateCommand] node version (vscode) ==="
node --version

echo "=== [onCreateCommand] ssl bundle ==="
ls -l /etc/ssl/certs/ca-certificates.crt || true

echo "=== [onCreateCommand] root curl ==="
sudo bash -lc '
  set -euxo pipefail
  echo "root curl user: $(whoami)"
  curl -Ivs https://github.com >/tmp/oncreate-root-curl.txt 2>&1 || {
    cat /tmp/oncreate-root-curl.txt
    exit 1
  }
  cat /tmp/oncreate-root-curl.txt
'

echo "=== [onCreateCommand] user curl ==="
curl -Ivs https://github.com >/tmp/oncreate-user-curl.txt 2>&1 || {
  cat /tmp/oncreate-user-curl.txt
  exit 1
}
cat /tmp/oncreate-user-curl.txt
