#!/usr/bin/env bash
set -euxo pipefail

echo "=== [postCreateCommand] user ==="
whoami
id

echo "=== [postCreateCommand] python version (root) ==="
sudo python3 --version

echo "=== [postCreateCommand] python version (vscode) ==="
python3 --version

echo "=== [postCreateCommand] node version (root) ==="
sudo bash -lc 'node --version'

echo "=== [postCreateCommand] node version (vscode) ==="
node --version

echo "=== [postCreateCommand] ssl bundle ==="
ls -l /etc/ssl/certs/ca-certificates.crt || true

echo "=== [postCreateCommand] root curl ==="
sudo bash -lc '
  set -euxo pipefail
  echo "root curl user: $(whoami)"
  curl -Ivs https://github.com >/tmp/postcreate-root-curl.txt 2>&1 || {
    cat /tmp/postcreate-root-curl.txt
    exit 1
  }
  cat /tmp/postcreate-root-curl.txt
'

echo "=== [postCreateCommand] user curl ==="
curl -Ivs https://github.com >/tmp/postcreate-user-curl.txt 2>&1 || {
  cat /tmp/postcreate-user-curl.txt
  exit 1
}
cat /tmp/postcreate-user-curl.txt

echo "=== [postCreateCommand] pip install (non-root) ==="
pip install cowsay --user

echo "=== [postCreateCommand] npm install (non-root) ==="
mkdir -p /tmp/npm-test
cd /tmp/npm-test
npm install cowsay
