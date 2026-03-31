#!/usr/bin/env bash
set -euxo pipefail

# The padawan-fw runc shim bind-mounts a mode-0700 tmpdir over /etc/ssl/certs each time
# this container starts. Repair the permissions so non-root users can traverse the
# directory and use TLS normally for the lifetime of this container session.
sudo chmod 755 /etc/ssl/certs

echo "=== [postStartCommand] user ==="
whoami
id

echo "=== [postStartCommand] python version (root) ==="
sudo python3 --version

echo "=== [postStartCommand] python version (vscode) ==="
python3 --version

echo "=== [postStartCommand] node version (root) ==="
sudo "$(which node)" --version

echo "=== [postStartCommand] node version (vscode) ==="
node --version

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

echo "=== [postStartCommand] pip install (non-root) ==="
PIP_VENV_DIR="/tmp/poststart-pip-venv"
rm -rf "${PIP_VENV_DIR}"
python3 -m venv "${PIP_VENV_DIR}"
"${PIP_VENV_DIR}/bin/pip" install --no-input --disable-pip-version-check colorama
"${PIP_VENV_DIR}/bin/python" -c "import colorama; print(colorama.__version__)"

echo "=== [postStartCommand] uv install (non-root) ==="
UV_PROJECT_DIR="/tmp/poststart-uv-project"
rm -rf "${UV_PROJECT_DIR}"
uv init --bare --no-readme --vcs none --no-workspace "${UV_PROJECT_DIR}"
uv add --project "${UV_PROJECT_DIR}" requests
uv run --project "${UV_PROJECT_DIR}" python -c "import requests; print(requests.__version__)"
