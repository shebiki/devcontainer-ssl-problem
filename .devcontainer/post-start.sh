#!/usr/bin/env bash
set -euxo pipefail

echo "=== [postStartCommand] user ==="
whoami
id

echo "=== [postStartCommand] ssl bundle ==="
ls -l /etc/ssl/certs/ca-certificates.crt || true

echo "=== [postStartCommand] root curl ==="
sudo bash -lc '
  set -euxo pipefail
  echo "root curl user: $(whoami)"
  curl -Ivs https://github.com >/tmp/poststart-root-curl.txt 2>&1 || {
    cat /tmp/poststart-root-curl.txt
    exit 1
  }
  cat /tmp/poststart-root-curl.txt
'

echo "=== [postStartCommand] user curl ==="
curl -Ivs https://github.com >/tmp/poststart-user-curl.txt 2>&1 || {
  cat /tmp/poststart-user-curl.txt
  exit 1
}
cat /tmp/poststart-user-curl.txt
