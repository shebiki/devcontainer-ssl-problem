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

## Test results (Copilot cloud agent, after workaround)

| Hook | User | curl result |
|------|------|-------------|
| `onCreateCommand` | root | ✅ HTTP 200 |
| `onCreateCommand` | vscode | ✅ HTTP 200 (after `chmod 755 /etc/ssl/certs`) |
| `updateContentCommand` | vscode | ✅ HTTP 200 |
| `postCreateCommand` | vscode | ✅ HTTP 200 |
| `postStartCommand` | vscode | ✅ HTTP 200 |

## Test results (without workaround)

| Test | Result |
|------|--------|
| root `curl https://github.com` | ✅ HTTP 200 |
| `vscode` user `curl https://github.com` | ❌ exit 77 (`CURLE_SSL_CACERT_BADFILE`) |

This reproduces identically on both `debian-13` and `ubuntu-24.04` base images.
