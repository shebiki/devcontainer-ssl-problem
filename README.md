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

## Notes

This reproduction does not use any custom CA certificates or certificate overrides, and no devcontainer features are installed.

---

## Results

### Debian-13 (`mcr.microsoft.com/devcontainers/base:debian-13`)

#### `onCreateCommand` lifecycle hook

| Test | Result |
|------|--------|
| root `curl https://github.com` | ✅ HTTP 200 OK |
| `vscode` user `curl https://github.com` | ❌ exit 77 — `error setting certificate file` |

The `onCreateCommand` fails at the user curl step; subsequent hooks
(`updateContentCommand`, `postCreateCommand`, `postStartCommand`) are skipped.

#### Manual tests inside the running container

After `devcontainer up` (container stays up despite the hook failure):

```
# root
$ docker exec <container> bash -c 'curl -Ivs https://github.com 2>&1 | grep -E "HTTP|error"'
< HTTP/1.1 200 OK      ✅

# vscode user
$ docker exec --user vscode <container> curl -Ivs https://github.com
* error setting certificate file: /etc/ssl/certs/ca-certificates.crt
curl: (77) ...           ❌
```

#### Root cause

```
$ docker exec <container> ls -ld /etc/ssl/certs
drwx------ 2 root root 4096  /etc/ssl/certs   ← mode 700, root-only

$ docker exec <container> ls -l /etc/ssl/certs/ca-certificates.crt
-rw-r--r-- 1 root root 1655  /etc/ssl/certs/ca-certificates.crt  ← mode 644
```

The `/etc/ssl/certs` **directory** has mode `700`. The file itself is world-readable
(`644`), but the non-root `vscode` user cannot traverse the directory to reach it.
`curl` (exit 77 = `CURLE_SSL_CACERT_BADFILE`) and any other TLS-aware tool fail immediately.

---

### Ubuntu-24.04 (`mcr.microsoft.com/devcontainers/base:ubuntu-24.04`)

Identical result. The `/etc/ssl/certs` directory also has mode `700` in this image:

```
drwx------ 2 root root 4096  /etc/ssl/certs   ← same bug
```

| Test | Result |
|------|--------|
| root `curl https://github.com` | ✅ HTTP 200 OK |
| `vscode` user `curl https://github.com` | ❌ exit 77 |

---

### Conclusion

The `drwx------` permission on `/etc/ssl/certs` is a **bug in the
`mcr.microsoft.com/devcontainers/base` images** for both `debian-13` and `ubuntu-24.04`.
It is not expected behaviour — the Debian `ca-certificates` package guarantees this
directory should be world-executable (`755`) so non-root users can traverse it.

This is a container image issue, not a devcontainer feature issue, and not specific to the
Python feature. It reproduces on the plain base image with no features installed.

This was confirmed against `devcontainers/images` (no tracking issue found for this
specific `700` directory permission at the time of testing, 2026-03-31).
