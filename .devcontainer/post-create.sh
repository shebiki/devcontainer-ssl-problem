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

echo "=== [postCreateCommand] httpx install (non-root) ==="
HTTPX_VENV_DIR="/tmp/postcreate-httpx-venv"
rm -rf "${HTTPX_VENV_DIR}"
python3 -m venv "${HTTPX_VENV_DIR}"
"${HTTPX_VENV_DIR}/bin/pip" install --no-input --disable-pip-version-check httpx
"${HTTPX_VENV_DIR}/bin/python" -c "import httpx; r = httpx.get('https://github.com', timeout=10); print('httpx', httpx.__version__, '->', r.status_code)"

echo "=== [postCreateCommand] playwright install (non-root) ==="
# Install playwright and its chromium browser inside the devcontainer.
# SSL_CERT_FILE is already set in the Dockerfile ENV so pip and the playwright
# browser-download step trust the padawan-fw MITM CA automatically.
PLAYWRIGHT_VENV_DIR="/tmp/postcreate-playwright-venv"
rm -rf "${PLAYWRIGHT_VENV_DIR}"
python3 -m venv "${PLAYWRIGHT_VENV_DIR}"
"${PLAYWRIGHT_VENV_DIR}/bin/pip" install --no-input --disable-pip-version-check playwright
"${PLAYWRIGHT_VENV_DIR}/bin/python" -m playwright install chromium
# Install OS-level shared libraries that Chromium requires (libatk, libglib, etc.)
sudo "${PLAYWRIGHT_VENV_DIR}/bin/python" -m playwright install-deps chromium

echo "=== [postCreateCommand] playwright NSS CA setup ==="
# Playwright's Chromium on Linux uses the NSS certificate database (not SSL_CERT_FILE)
# to verify TLS connections.  We need to register the padawan-fw MITM CA there so
# that Chromium trusts it — this is the direct equivalent of setting SSL_CERT_FILE
# for Python tools.
#
# Extract the padawan-fw MITM CA (identified by its mkcert issuer) from the system
# bundle, then add it to the user NSS database that Chromium reads.
sudo apt-get install -y --no-install-recommends libnss3-tools >/dev/null 2>&1
mkdir -p "${HOME}/.pki/nssdb"
certutil -d "sql:${HOME}/.pki/nssdb" -N --empty-password 2>/dev/null || true

# Extract the mkcert MITM CA cert from the system bundle into a temp PEM file.
python3 - << 'PYEOF'
import re, subprocess, sys

bundle = open("/etc/ssl/certs/ca-certificates.crt").read()
certs = re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", bundle, re.DOTALL)
for pem in certs:
    result = subprocess.run(
        ["openssl", "x509", "-noout", "-issuer", "-subject"],
        input=pem, capture_output=True, text=True,
    )
    if "mkcert" in result.stdout.lower():
        with open("/tmp/mitm-ca.pem", "w") as f:
            f.write(pem)
        print("MITM CA extracted:", result.stdout.strip().split("\n")[0])
        sys.exit(0)
print("WARNING: mkcert CA not found in system bundle", file=sys.stderr)
sys.exit(1)
PYEOF

certutil -d "sql:${HOME}/.pki/nssdb" -A -n "padawan-fw-mitm" -t "CT,," -i /tmp/mitm-ca.pem
echo "MITM CA added to NSS database"
certutil -d "sql:${HOME}/.pki/nssdb" -L

echo "=== [postCreateCommand] playwright screenshot test (non-root) ==="
# Take screenshots of the local server, www.python.org, and github.com using
# Playwright's Chromium — with no ignore_https_errors, proving SSL is fully solved.
SCREENSHOT_DIR="/workspaces/repro/screenshots"
mkdir -p "${SCREENSHOT_DIR}"

"${PLAYWRIGHT_VENV_DIR}/bin/python" - << 'PYEOF'
import os, sys
from playwright.sync_api import sync_playwright

SCREENSHOT_DIR = "/workspaces/repro/screenshots"

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    results = []
    for name, url in [
        ("01-devcontainer-local-server", "http://localhost:8765/"),
        ("02-python-org",                "https://www.python.org/"),
        ("03-github-com",                "https://github.com/"),
    ]:
        page = browser.new_page(viewport={"width": 1280, "height": 800})
        try:
            page.goto(url, wait_until="domcontentloaded", timeout=20000)
            page.wait_for_timeout(2000)
            path = os.path.join(SCREENSHOT_DIR, f"{name}.png")
            page.screenshot(path=path)
            results.append(f"OK  {name}  ({page.title()})")
        except Exception as e:
            results.append(f"ERR {name}: {e}")
        page.close()
    browser.close()

for r in results:
    print(r)
    if r.startswith("ERR"):
        sys.exit(1)
PYEOF
