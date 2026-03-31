#!/usr/bin/env bash
set -euxo pipefail

# The padawan-fw runc shim bind-mounts a mode-0700 tmpdir over /etc/ssl/certs when this
# container was started. Repair the permissions so non-root users can traverse the
# directory and use TLS normally for the lifetime of this container.
sudo chmod 755 /etc/ssl/certs

echo "=== [postCreateCommand] user ==="
whoami
id

echo "=== [postCreateCommand] python version (root) ==="
sudo python3 --version

echo "=== [postCreateCommand] python version (vscode) ==="
python3 --version

echo "=== [postCreateCommand] node version (root) ==="
sudo "$(which node)" --version

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
PIP_VENV_DIR="/tmp/postcreate-pip-venv"
rm -rf "${PIP_VENV_DIR}"
python3 -m venv "${PIP_VENV_DIR}"
"${PIP_VENV_DIR}/bin/pip" install --no-input --disable-pip-version-check colorama
"${PIP_VENV_DIR}/bin/python" -c "import colorama; print(colorama.__version__)"

echo "=== [postCreateCommand] uv install (non-root) ==="
UV_PROJECT_DIR="/tmp/postcreate-uv-project"
rm -rf "${UV_PROJECT_DIR}"
uv init --bare --no-readme --vcs none --no-workspace "${UV_PROJECT_DIR}"
uv add --project "${UV_PROJECT_DIR}" requests
uv run --project "${UV_PROJECT_DIR}" python -c "import requests; print(requests.__version__)"

echo "=== [postCreateCommand] npm install (non-root) ==="
mkdir -p /tmp/npm-test
cd /tmp/npm-test
npm install cowsay
