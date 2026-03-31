#!/usr/bin/env bash
set -euxo pipefail

echo "=== [updateContentCommand] user ==="
whoami
id

echo "=== [updateContentCommand] ssl bundle ==="
ls -l /etc/ssl/certs/ca-certificates.crt || true

echo "=== [updateContentCommand] root curl ==="
sudo bash -lc '
  set -euxo pipefail
  echo "root curl user: $(whoami)"
  curl -Ivs https://github.com >/tmp/updatecontent-root-curl.txt 2>&1 || {
    cat /tmp/updatecontent-root-curl.txt
    exit 1
  }
  cat /tmp/updatecontent-root-curl.txt
'

echo "=== [updateContentCommand] user curl ==="
curl -Ivs https://github.com >/tmp/updatecontent-user-curl.txt 2>&1 || {
  cat /tmp/updatecontent-user-curl.txt
  exit 1
}
cat /tmp/updatecontent-user-curl.txt
