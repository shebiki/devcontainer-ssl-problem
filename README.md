# Copilot cloud agent devcontainer non-root SSL repro

Minimal reproduction for the padawan-fw runc shim SSL bug in the GitHub Copilot cloud
agent, and an active workbench for testing the devcontainer setup.

---

## Root cause

The Copilot cloud agent environment runs **`padawan-fw`**, a network firewall that
performs TLS interception (MITM) on all outbound HTTPS. It installs a Bash shim at
`/usr/bin/runc` that intercepts every `runc create` call and injects bind-mounts into
the container's OCI `config.json` before the real `runc` runs.

The relevant part of the shim:

```bash
CERT_TMP_DIR=$(mktemp -d)                           # drwx------ (mode 0700)
cp "$CERT_PATH" "$CERT_TMP_DIR/ca-certificates.crt"
chmod 644 "$CERT_TMP_DIR/ca-certificates.crt"       # fixes the FILE, not the DIR
# missing: chmod 755 "$CERT_TMP_DIR"
```

Inside every container the result is:

```
drwx------ 2 root root  /etc/ssl/certs          ← 0700
-rw-r--r-- 1 root root  /etc/ssl/certs/ca-certificates.crt  ← 0644
```

`root` can traverse the 0700 dir (via `CAP_DAC_OVERRIDE`). Non-root users cannot, so
`curl` as `vscode` fails immediately with exit 77 (`CURLE_SSL_CACERT_BADFILE`).

The shim runs at the OCI layer and affects every container regardless of the base image.

**Real fix:** add `chmod 755 "$CERT_TMP_DIR"` to the padawan-fw shim right after
`mktemp -d`.

---

## Current devcontainer approach

### Base image

`mcr.microsoft.com/devcontainers/base:trixie` (Debian 13 / Trixie).

Chosen because:
- Debian is the standard base for devcontainers
- Trixie ships Python 3.13 in its default repos (convenient for the test, though we
  install via pyenv anyway for version-pinning reasons — see below)

### Python and Node: version-pinnable, not system-level

Devcontainer `features` were dropped in favour of tools installed directly in the
Dockerfile, giving full control over TLS calls during the build:

| Tool | Installed via | Location | Version pin |
|------|--------------|----------|-------------|
| Python | **pyenv** (compiled from source) | `/usr/local/pyenv` | `ARG PYTHON_VERSION=3.13` |
| Node | **nvm** | `/usr/local/nvm` | `ARG NODE_VERSION=lts` |

Both are installed as root to world-readable system-wide paths. Symlinks in
`/usr/local/bin/` make `python3`, `pip`, `pip3`, `node`, `npm`, `npx` available to
all users and `sudo`.

To pin a different version, rebuild with a build-arg:

```bash
docker build --build-arg PYTHON_VERSION=3.12 --build-arg NODE_VERSION=20 \
  -f .devcontainer/Dockerfile .
```

### SSL workaround: `chmod 755 /etc/ssl/certs`

Moving to a local Dockerfile means all Dockerfile `RUN` steps execute as root and can
traverse the 0700-mounted `/etc/ssl/certs` without any cert redirection. So the
previous workaround machinery was dropped entirely:

- ❌ removed: CA bundle copy to `/usr/local/share/ca-certificates.crt`
- ❌ removed: `~/.curlrc` cacert overrides
- ❌ removed: `git config --system http.sslCAInfo`
- ❌ removed: `/etc/environment` and `/etc/profile.d/ca-bundle-workaround.sh`
- ❌ removed: `ENV CURL_CA_BUNDLE / GIT_SSL_CAINFO / SSL_CERT_FILE / …` block
- ❌ removed: `features` block in `devcontainer.json`

Each Dockerfile `RUN` step that makes network calls opens with
`chmod 755 /etc/ssl/certs` — harmless when the dir is already 755, essential when the
shim has mounted a 0700 dir.

Each lifecycle hook script opens with `sudo chmod 755 /etc/ssl/certs` for the same
reason: the shim applies a fresh bind-mount every time a container starts, so
`postStartCommand` in particular must re-apply the fix on every boot.

---

## Repository structure

```
.devcontainer/
  Dockerfile            # trixie base + pyenv Python + nvm Node
  devcontainer.json     # no features; references docker-compose.yml + hooks
  docker-compose.yml    # builds Dockerfile; mounts workspace
  on-create.sh          # onCreateCommand   — chmod fix + version/curl checks
  update-content.sh     # updateContentCommand — chmod fix + version/curl checks
  post-create.sh        # postCreateCommand — chmod fix + version/curl/pip/npm checks
  post-start.sh         # postStartCommand  — chmod fix + version/curl checks
```

### What each hook script does

1. `sudo chmod 755 /etc/ssl/certs` — shim workaround
2. `whoami` / `id`
3. Python and Node version checks (root and non-root)
4. `ls -l /etc/ssl/certs/ca-certificates.crt`
5. `curl -Ivs https://github.com` as root and as `vscode`
6. (`post-create.sh` only) `pip install --user cowsay` and `npm install cowsay`

---

## Current status / what the next agent needs to do

The Dockerfile was written but **the image build has not yet been completed or
verified**. The build was started and then stopped because it requires outbound access
to domains that may be firewall-blocked in the runner environment.

### Domains that must be reachable during `docker build`

| Step | Domain(s) needed |
|------|-----------------|
| `apt-get update` | `deb.debian.org`, `security.debian.org` |
| pyenv git clone | `github.com` |
| pyenv Python build | `www.python.org` (source tarball download) |
| nvm install script | `raw.githubusercontent.com` |
| nvm Node download | `nodejs.org` |

### Steps to complete

1. **Verify the domains above are reachable** from a `docker build` container. If any
   are blocked, ask the user to lift the firewall restriction before proceeding.

2. **Build the image:**
   ```bash
   cd /home/runner/work/devcontainer-ssl-problem/devcontainer-ssl-problem
   docker build --no-cache -t repro-test -f .devcontainer/Dockerfile .
   ```

3. **Start a container and run the hook scripts manually** (simulating what the
   devcontainer lifecycle would do):
   ```bash
   docker run -d --name repro-test-ctr repro-test sleep infinity
   docker exec -u vscode repro-test-ctr bash /workspaces/repro/.devcontainer/on-create.sh
   docker exec -u vscode repro-test-ctr bash /workspaces/repro/.devcontainer/update-content.sh
   docker exec -u vscode repro-test-ctr bash /workspaces/repro/.devcontainer/post-create.sh
   docker exec -u vscode repro-test-ctr bash /workspaces/repro/.devcontainer/post-start.sh
   ```

4. **Run manual version and install checks inside the running container:**
   ```bash
   docker exec repro-test-ctr python3 --version
   docker exec repro-test-ctr pip3 --version
   docker exec repro-test-ctr node --version
   docker exec repro-test-ctr npm --version
   docker exec -u vscode repro-test-ctr python3 --version
   docker exec -u vscode repro-test-ctr node --version
   docker exec -u vscode repro-test-ctr pip install --user cowsay
   docker exec -u vscode repro-test-ctr bash -c 'cd /tmp && npm install cowsay'
   ```

5. **Summarise hook output and manual check results** and update the
   [Test results](#test-results) section below.

6. **Commit and push.**

---

## Test results

> **Not yet recorded.** The image build has not been completed. See
> [Current status](#current-status--what-the-next-agent-needs-to-do) above.

### Expected results (after build succeeds)

| Hook | User | curl | python3 --version | node --version |
|------|------|------|-------------------|----------------|
| `onCreateCommand` | vscode | ✅ HTTP 200 | ✅ 3.13.x | ✅ LTS |
| `updateContentCommand` | vscode | ✅ HTTP 200 | ✅ 3.13.x | ✅ LTS |
| `postCreateCommand` | vscode | ✅ HTTP 200 | ✅ 3.13.x | ✅ LTS |
| `postStartCommand` | vscode | ✅ HTTP 200 | ✅ 3.13.x | ✅ LTS |
