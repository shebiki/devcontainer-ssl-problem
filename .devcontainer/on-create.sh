#!/usr/bin/env bash
set -euxo pipefail

# The padawan-fw runc shim bind-mounts a mode-0700 tmpdir over /etc/ssl/certs when this
# container was started. Repair the permissions so non-root users can traverse the
# directory and use TLS normally for the lifetime of this container.
sudo chmod 755 /etc/ssl/certs

echo "=== [onCreateCommand] user ==="
whoami
id

echo "=== [onCreateCommand] python version (root) ==="
sudo python3 --version

echo "=== [onCreateCommand] python version (vscode) ==="
python3 --version

echo "=== [onCreateCommand] node version (root) ==="
sudo "$(which node)" --version

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

echo "=== [onCreateCommand] pip install (non-root) ==="
PIP_VENV_DIR="/tmp/oncreate-pip-venv"
rm -rf "${PIP_VENV_DIR}"
python3 -m venv "${PIP_VENV_DIR}"
"${PIP_VENV_DIR}/bin/pip" install --no-input --disable-pip-version-check colorama
"${PIP_VENV_DIR}/bin/python" -c "import colorama; print(colorama.__version__)"

echo "=== [onCreateCommand] uv install (non-root) ==="
UV_PROJECT_DIR="/tmp/oncreate-uv-project"
rm -rf "${UV_PROJECT_DIR}"
uv init --bare --no-readme --vcs none --no-workspace "${UV_PROJECT_DIR}"
uv add --project "${UV_PROJECT_DIR}" requests
uv run --project "${UV_PROJECT_DIR}" python -c "import requests; print(requests.__version__)"
