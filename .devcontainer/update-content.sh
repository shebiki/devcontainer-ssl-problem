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

echo "=== [updateContentCommand] pip install (non-root) ==="
PIP_VENV_DIR="/tmp/updatecontent-pip-venv"
rm -rf "${PIP_VENV_DIR}"
python3 -m venv "${PIP_VENV_DIR}"
"${PIP_VENV_DIR}/bin/pip" install --no-input --disable-pip-version-check colorama
"${PIP_VENV_DIR}/bin/python" -c "import colorama; print(colorama.__version__)"

echo "=== [updateContentCommand] uv install (non-root) ==="
UV_PROJECT_DIR="/tmp/updatecontent-uv-project"
rm -rf "${UV_PROJECT_DIR}"
uv init --bare --no-readme --vcs none --no-workspace "${UV_PROJECT_DIR}"
uv add --project "${UV_PROJECT_DIR}" requests
uv run --project "${UV_PROJECT_DIR}" python -c "import requests; print(requests.__version__)"

echo "=== [updateContentCommand] httpx install (non-root) ==="
HTTPX_VENV_DIR="/tmp/updatecontent-httpx-venv"
rm -rf "${HTTPX_VENV_DIR}"
python3 -m venv "${HTTPX_VENV_DIR}"
"${HTTPX_VENV_DIR}/bin/pip" install --no-input --disable-pip-version-check httpx
"${HTTPX_VENV_DIR}/bin/python" -c "import httpx; r = httpx.get('https://github.com', timeout=10); print('httpx', httpx.__version__, '->', r.status_code)"
