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

Beyond the `/etc/ssl/certs` directory permission bug, two common developer tools ship with
their **own** TLS stacks that do not automatically trust the padawan-fw MITM CA:

| Tool | TLS stack | Symptom | Fix |
|------|-----------|---------|-----|
| **uv** | rustls (default) | `invalid peer certificate: UnknownIssuer` | `ENV UV_NATIVE_TLS=1` — switches uv to OpenSSL, which reads `/etc/ssl/certs` |
| **npm / Node.js** | Node's own CA store | `SELF_SIGNED_CERT_IN_CHAIN` | `ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt` — appends the MITM CA to Node's built-in store |

Both env vars are now set in the Dockerfile.

## Test results (Copilot cloud agent, with all workarounds)

### Lifecycle hook results

| Hook | User | curl | pip install | uv add | npm install |
|------|------|------|-------------|--------|-------------|
| `onCreateCommand` | vscode | ✅ HTTP 200 | ✅ colorama 0.4.6 | ✅ requests 2.33.1 | — |
| `updateContentCommand` | vscode | ✅ HTTP 200 | ✅ colorama 0.4.6 | ✅ requests 2.33.1 | — |
| `postCreateCommand` | vscode | ✅ HTTP 200 | ✅ colorama 0.4.6 | ✅ requests 2.33.1 | ✅ cowsay |
| `postStartCommand` | vscode | ✅ HTTP 200 | ✅ colorama 0.4.6 | ✅ requests 2.33.1 | — |

### Manual tool versions

| Tool | Version | Path |
|------|---------|------|
| Node.js | v24.14.1 | `/usr/local/bin/node` |
| npm | 11.11.0 | `/usr/local/bin/npm` |
| Python | 3.13.5 | `/usr/local/bin/python3` |
| uv | 0.6.6 | `/usr/local/bin/uv` |
| nvm | — | not installed (Node is pinned directly in the Dockerfile) |

### Manual install tests

| Test | Command | Result |
|------|---------|--------|
| `npm install` | `npm install cowsay` | ✅ 41 packages installed |
| `uv add` | `uv add httpx` | ✅ httpx 0.28.1 installed |

## Test results (without workaround)

| Test | Result |
|------|--------|
| root `curl https://github.com` | ✅ HTTP 200 |
| `vscode` user `curl https://github.com` | ❌ exit 77 (`CURLE_SSL_CACERT_BADFILE`) |
| `uv add` (default rustls) | ❌ `invalid peer certificate: UnknownIssuer` |
| `npm install` (without `NODE_EXTRA_CA_CERTS`) | ❌ `SELF_SIGNED_CERT_IN_CHAIN` |

This reproduces identically on both `debian-13` and `ubuntu-24.04` base images.
