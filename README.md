# Copilot cloud agent devcontainer non-root SSL repro

This repository is a minimal reproduction for a suspected issue in the GitHub Copilot cloud agent when using a devcontainer.

## Summary

The goal is to test whether HTTPS/network operations behave differently for:

- root/setup-time commands, versus
- the non-root devcontainer user (`vscode`)

inside the Copilot cloud agent environment.

This repo intentionally avoids:

- application code
- private registries
- custom CA certificates
- custom SSL configuration
- database setup

## What this repo does

The devcontainer runs `curl https://github.com` as both `root` and the non-root `vscode` user in every devcontainer lifecycle hook:

| Hook | Script |
|------|--------|
| `onCreateCommand` | `on-create.sh` |
| `updateContentCommand` | `update-content.sh` |
| `postCreateCommand` | `post-create.sh` |
| `postStartCommand` | `post-start.sh` |

Each script:
1. Prints the current user and `id`
2. Shows `/etc/ssl/certs/ca-certificates.crt` permissions
3. Runs `curl -Ivs https://github.com` as **root** (via `sudo bash -lc`)
4. Runs `curl -Ivs https://github.com` as the **current (non-root) user**

## Expected result

All `curl` calls — root and non-root — succeed across all lifecycle hooks.

## Files

- `.devcontainer/devcontainer.json`
- `.devcontainer/docker-compose.yml`
- `.devcontainer/on-create.sh`
- `.devcontainer/update-content.sh`
- `.devcontainer/post-create.sh`
- `.devcontainer/post-start.sh`

---

## Root cause analysis

### What is actually happening

The Copilot cloud agent environment runs a **`padawan-fw`** network firewall that
performs TLS interception (MITM) on all outbound HTTPS connections from containers.
To achieve this, it installs a shim at `/usr/bin/runc` — a Bash script that intercepts
every `runc create` call made by `containerd` when a Docker container starts.

The shim (readable at `/usr/bin/runc` in the runner environment) does the following:

```bash
CERT_TMP_DIR=$(mktemp -d)                          # creates drwx------ (mode 0700)
cp "$CERT_PATH" "$CERT_TMP_DIR/ca-certificates.crt"
chmod 644 "$CERT_TMP_DIR/ca-certificates.crt"      # fixes the FILE — but NOT the DIR
# ← missing: chmod 755 "$CERT_TMP_DIR"
```

It then injects bind mounts into the container's OCI `config.json` to overlay
`$CERT_TMP_DIR` over `/etc/ssl/certs`.

### The bug

`mktemp -d` creates directories with mode `0700` (root-only) by default. The shim
`chmod 644`s the **cert file** inside the directory, but never makes the **directory
itself** world-traversable. Result inside every container:

```
drwx------ 2 root root 4096  /etc/ssl/certs        ← mode 0700
-rw-r--r-- 1 root root 1655  /etc/ssl/certs/ca-certificates.crt  ← mode 0644
```

`root` can traverse `0700` directories it owns (via `CAP_DAC_OVERRIDE`/`CAP_DAC_READ_SEARCH`).
Non-root users cannot. So `curl` as the `vscode` user immediately fails with
`exit 77` (`CURLE_SSL_CACERT_BADFILE`) when it tries to open the CA bundle path.

### Does this affect the Docker container image?

**No.** The shim operates at the OCI/`runc` layer and injects the bind mount
unconditionally regardless of what image is used. Testing confirmed **identical
behaviour** on:

- `mcr.microsoft.com/devcontainers/base:debian-13`
- `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`

A different base image **would not help**.

### Workaround

Add `sudo chmod 755 /etc/ssl/certs` to the first lifecycle hook (`onCreateCommand`)
before any non-root network calls. This is already applied in `on-create.sh`.

### Real fix

Change `/usr/bin/runc` (the padawan-fw shim) to add `chmod 755 "$CERT_TMP_DIR"`
immediately after `mktemp -d`.

---

## Additional SSL quirk: tools with their own TLS stacks

Beyond the `/etc/ssl/certs` directory permission bug, several common developer tools ship
with their **own** TLS stacks or certificate stores that do **not** automatically trust the
padawan-fw MITM CA certificate. The fixes are environment variables set in the Dockerfile.

### Why each tool category behaves differently

| Category | How it resolves CAs | Affected? |
|---|---|---|
| **curl, git, wget** | libcurl → OpenSSL → reads `/etc/ssl/certs` | ✅ Works (after `chmod 755`) |
| **Python `ssl` / `urllib`** | CPython SSL → OpenSSL → reads `/usr/lib/ssl/cert.pem` (symlink to `/etc/ssl/certs/ca-certificates.crt`) | ✅ Works |
| **pip** (the tool) | Uses `ssl.create_default_context()` — same OpenSSL path | ✅ Works |
| **httpie** | Uses `ssl.create_default_context()` — same OpenSSL path | ✅ Works |
| **Python `requests` library** | Uses **`certifi`** bundled Mozilla CA store (272 KB), ignores system OpenSSL paths | ❌ Fails |
| **npm / Node.js** | Node.js ships its own embedded CA store (Mozilla-derived) | ❌ Fails |
| **yarn v1** (uses Node.js) | Same embedded Node.js CA store | ❌ Fails |
| **uv** (default) | Ships with **rustls** + bundled WebPKI roots | ❌ Fails |
| **pnpm** (uses Node.js) | Same embedded Node.js CA store | ❌ Fails (not tested here) |
| **Deno** (default) | Ships with **rustls** + bundled WebPKI roots | ❌ Fails (not tested here) |
| **poetry** (uses requests) | Inherits `requests`/certifi behavior | ❌ Fails (not tested here) |
| **Cargo / Rust** | Depends on compile-time feature (`rustls` or `native-tls`) | ❌ Likely fails with rustls builds (not tested here) |

### Verified failures and fixes

| Tool | TLS stack | Error | Dockerfile fix |
|------|-----------|-------|----------------|
| **Python `requests`** | certifi bundle | `CERTIFICATE_VERIFY_FAILED: self-signed certificate in certificate chain` | `ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt` |
| **Python `httpx`** | certifi bundle | `CERTIFICATE_VERIFY_FAILED: self-signed certificate in certificate chain` | `ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt` |
| **uv** | rustls (default) | `invalid peer certificate: UnknownIssuer` | `ENV UV_NATIVE_TLS=1` |
| **npm / yarn / Node.js** | Node.js CA store | `SELF_SIGNED_CERT_IN_CHAIN` | `ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt` |

All four env vars are now set in the Dockerfile.

#### `requests` vs `httpx` — same root cause, different env var

Both `requests` and `httpx` default to `certifi.where()` instead of the system OpenSSL paths,
so they each fail with the same `CERTIFICATE_VERIFY_FAILED` error without an override.
But they check **different** env vars:

```python
# requests/_internal/utils.py
DEFAULT_CA_BUNDLE_PATH = os.environ.get("REQUESTS_CA_BUNDLE") or certifi.where()

# httpx/_config.py
if trust_env and os.environ.get("SSL_CERT_FILE"):
    ctx = ssl.create_default_context(cafile=os.environ["SSL_CERT_FILE"])
else:
    ctx = ssl.create_default_context(cafile=certifi.where())  # ← MITM cert not in certifi
```

Verified: `REQUESTS_CA_BUNDLE` does **not** fix `httpx`; `SSL_CERT_FILE` does **not** fix
`requests`. Both env vars must be set. As a bonus `SSL_CERT_FILE` is also honoured by OpenSSL
itself, so it helps any other tool that respects the standard OpenSSL env vars.

#### Playwright / Chromium — NSS certificate database

Playwright's Chromium is a **separate subprocess** with its own certificate verification stack.
It does **not** read `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, or any of the Python/Node env vars.
On Linux, Chromium uses the **NSS certificate database** (`~/.pki/nssdb`).

The fix — equivalent to setting an env var for the other tools — is to register the MITM CA
there once via `certutil`. This is automated in `post-create.sh`:

```bash
# 1. Install NSS tools
sudo apt-get install -y libnss3-tools

# 2. Create (or reuse) the user NSS database
mkdir -p "${HOME}/.pki/nssdb"
certutil -d "sql:${HOME}/.pki/nssdb" -N --empty-password

# 3. Extract the padawan-fw MITM CA from the system bundle and register it
#    (see post-create.sh for the Python snippet that identifies it by issuer)
certutil -d "sql:${HOME}/.pki/nssdb" -A -n "padawan-fw-mitm" -t "CT,," -i /tmp/mitm-ca.pem
```

After this, Playwright can navigate to HTTPS sites with **full certificate validation**
(`ignore_https_errors` is not needed or set).

Note: both `www.python.org` and `github.com` are intercepted by the MITM proxy
(`subject=O = GoProxy untrusted MITM proxy Inc`). The MITM CA being in the NSS database is
what makes Chromium trust those connections.

### Tools NOT yet covered by these env vars

For completeness, if these tools are added to the devcontainer image in the future:

| Tool | Fix |
|------|-----|
| **pnpm** | already covered by `NODE_EXTRA_CA_CERTS` |
| **yarn v2 / Berry** | `yarn config set httpsCaFilePath /etc/ssl/certs/ca-certificates.crt` |
| **Deno** | `ENV DENO_CERT=/etc/ssl/certs/ca-certificates.crt` |
| **Bun** | `ENV NODE_EXTRA_CA_CERTS=...` (Bun respects this) |
| **poetry** | already covered by `REQUESTS_CA_BUNDLE` |
| **Cargo** (rustls build) | `ENV CARGO_HTTP_CAINFO=/etc/ssl/certs/ca-certificates.crt` |
| **Go / `go get`** | Works automatically via system certs (uses `crypto/x509`) |
| **gh CLI** | Works automatically (Go-based) |
| **Java / Maven / Gradle** | `keytool -importcert` into the JVM keystore; or set `javax.net.ssl.trustStore` |
| **Ruby Gems** | `ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt` |

---

## Test results (Copilot cloud agent, clean-room run with all workarounds)

### Lifecycle hook results

| Hook | User | curl (root) | curl (vscode) | pip install | uv add | httpx get | npm install | playwright screenshots |
|------|------|-------------|---------------|-------------|--------|-----------|-------------|----------------------|
| `onCreateCommand` | vscode | ✅ HTTP 200 | ✅ HTTP 200 | ✅ colorama 0.4.6 | ✅ requests 2.33.1 | ✅ 200 | — | — |
| `updateContentCommand` | vscode | ✅ HTTP 200 | ✅ HTTP 200 | ✅ colorama 0.4.6 | ✅ requests 2.33.1 | ✅ 200 | — | — |
| `postCreateCommand` | vscode | ✅ HTTP 200 | ✅ HTTP 200 | ✅ colorama 0.4.6 | ✅ requests 2.33.1 | ✅ 200 | ✅ cowsay (41 pkgs) | ✅ 3 screenshots |
| `postStartCommand` | vscode | ✅ HTTP 200 | ✅ HTTP 200 | ✅ colorama 0.4.6 | ✅ requests 2.33.1 | ✅ 200 | — | — |

Outcome: `{"outcome":"success"}` — all hooks completed without error.

### Manual tool versions (verified inside running container)

| Tool | Version | Path |
|------|---------|------|
| Node.js | v24.14.1 | `/usr/local/bin/node` |
| npm | 11.11.0 | `/usr/local/bin/npm` |
| Python | 3.13.5 | `/usr/local/bin/python3` |
| uv | 0.6.6 | `/usr/local/bin/uv` |
| yarn | 1.22.22 | `/usr/bin/yarn` (pre-installed by base image) |
| git | 2.50.1 | `/usr/bin/git` |
| curl | 7.88.1 | `/usr/bin/curl` |
| nvm | — | not installed (Node is pinned directly in the Dockerfile) |

### Manual install tests (verified inside running container)

| Test | Command | Result |
|------|---------|--------|
| `npm install` | `npm install cowsay` | ✅ 41 packages |
| `yarn add` | `yarn add chalk` | ✅ chalk 5.6.2 |
| `uv add` | `uv add httpx` | ✅ httpx 0.28.1 |
| `pip install` | `pip3 install colorama` | ✅ colorama 0.4.6 |
| `git clone` | `git clone https://github.com/octocat/Hello-World.git` | ✅ cloned |

## Test results (without workarounds)

| Test | Result |
|------|--------|
| `curl https://github.com` (non-root, no `chmod 755`) | ❌ exit 77 (`CURLE_SSL_CACERT_BADFILE`) |
| `curl https://github.com` (root, any time) | ✅ HTTP 200 |
| `uv add` without `UV_NATIVE_TLS=1` | ❌ `invalid peer certificate: UnknownIssuer` |
| `npm install` without `NODE_EXTRA_CA_CERTS` | ❌ `SELF_SIGNED_CERT_IN_CHAIN` |
| `yarn add` without `NODE_EXTRA_CA_CERTS` | ❌ `Error: self-signed certificate in certificate chain` |
| `requests.get()` without `REQUESTS_CA_BUNDLE` | ❌ `CERTIFICATE_VERIFY_FAILED: self-signed certificate` |
| `httpx.get()` without `SSL_CERT_FILE` | ❌ `CERTIFICATE_VERIFY_FAILED: self-signed certificate` |
| `httpx.get()` with `REQUESTS_CA_BUNDLE` only | ❌ `CERTIFICATE_VERIFY_FAILED` (httpx does not read `REQUESTS_CA_BUNDLE`) |
| Playwright Chromium without NSS CA setup | ❌ `ERR_CERT_AUTHORITY_INVALID` |
| Playwright Chromium with NSS CA + no `ignore_https_errors` | ✅ pages load, screenshots saved |

This reproduces identically on both `debian-13` and `ubuntu-24.04` base images.
