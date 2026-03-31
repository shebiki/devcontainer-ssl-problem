#!/usr/bin/env bash
set -euxo pipefail

# The padawan-fw runc shim bind-mounts a mode-0700 tmpdir over /etc/ssl/certs when this
# container was started. Repair the permissions so non-root users can traverse the
# directory and use TLS normally for the lifetime of this container.
sudo chmod 755 /etc/ssl/certs

echo "=== [updateContentCommand] user ==="
whoami
id

echo "=== [updateContentCommand] python version (root) ==="
sudo python3 --version

echo "=== [updateContentCommand] python version (vscode) ==="
python3 --version

echo "=== [updateContentCommand] node version (root) ==="
sudo "$(which node)" --version

echo "=== [updateContentCommand] node version (vscode) ==="
node --version

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
