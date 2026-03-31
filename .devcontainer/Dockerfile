FROM mcr.microsoft.com/devcontainers/python:1-3.13-bookworm

# The padawan-fw runc shim bind-mounts a mode-0700 tmpdir over /etc/ssl/certs in every
# container it starts (including each Docker build container). Root can already traverse
# 0700 directories, so all apt/curl calls below work without any cert redirection.
# Opening each network-touching RUN step with chmod 755 /etc/ssl/certs additionally
# makes the directory traversable by non-root users within the same RUN step.

ARG UV_VERSION=0.6.6
ARG NODE_VERSION=24.14.1
ARG NODE_SHA256_X64=84d38715d449447117d05c3e71acd78daa49d5b1bfa8aacf610303920c3322be
ARG NODE_SHA256_ARM64=71e427e28b78846f201d4d5ecc30cb13d1508ca099ef3871889a1256c7d6f67e
ENV UV_PYTHON_PREFERENCE=only-system
ENV UV_PYTHON_DOWNLOADS=never
# Use native TLS (OpenSSL) so uv trusts the padawan-fw MITM CA from /etc/ssl/certs.
ENV UV_NATIVE_TLS=1
# Append the runtime MITM CA bundle to Node's built-in CA store so npm/yarn/pnpm trust it.
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
# The Python `requests` library uses its bundled certifi CA store by default (not system
# OpenSSL). Point it to the system bundle so it trusts the padawan-fw MITM CA at runtime.
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
# The Python `httpx` library also defaults to certifi, but respects SSL_CERT_FILE.
# This also benefits any other tool that honours the standard OpenSSL env var.
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Install uv system-wide.
RUN <<EOF
set -e
chmod 755 /etc/ssl/certs

ARCH=$(uname -m)
case "${ARCH}" in
    x86_64)
        UV_ARCH="x86_64-unknown-linux-gnu"
        UV_SHA256="4c3426c4919d9f44633ab9884827fa1ad64ad8d993516d636eb955a3835c4a8c"
        ;;
    aarch64)
        UV_ARCH="aarch64-unknown-linux-gnu"
        UV_SHA256="37a543598cdb7d8fc9b74e6b1fe1fdf8b9a279c6137c7ff8396a88f69ec7a43c"
        ;;
    *)
        echo "Unsupported architecture: ${ARCH}" >&2
        exit 1
        ;;
esac

curl -LsSf "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_ARCH}.tar.gz" \
    -o /tmp/uv.tar.gz
echo "${UV_SHA256}  /tmp/uv.tar.gz" | sha256sum --check --strict
tar -xz --strip-components=1 -C /usr/local/bin -f /tmp/uv.tar.gz
rm /tmp/uv.tar.gz
EOF

# Install the pinned Node binary directly from upstream.
RUN <<EOF
set -e
chmod 755 /etc/ssl/certs

ARCH=$(uname -m)
case "${ARCH}" in
    x86_64)
        NODE_ARCH="x64"
        NODE_SHA256="${NODE_SHA256_X64}"
        ;;
    aarch64)
        NODE_ARCH="arm64"
        NODE_SHA256="${NODE_SHA256_ARM64}"
        ;;
    *)
        echo "Unsupported architecture: ${ARCH}" >&2
        exit 1
        ;;
esac

NODE_TARBALL="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TARBALL}" -o /tmp/${NODE_TARBALL}
echo "${NODE_SHA256}  /tmp/${NODE_TARBALL}" | sha256sum --check --strict
mkdir -p /usr/local/lib/nodejs
tar -xJf /tmp/${NODE_TARBALL} -C /usr/local/lib/nodejs
ln -sf /usr/local/lib/nodejs/node-v${NODE_VERSION}-linux-${NODE_ARCH}/bin/node /usr/local/bin/node
ln -sf /usr/local/lib/nodejs/node-v${NODE_VERSION}-linux-${NODE_ARCH}/bin/npm /usr/local/bin/npm
ln -sf /usr/local/lib/nodejs/node-v${NODE_VERSION}-linux-${NODE_ARCH}/bin/npx /usr/local/bin/npx
ln -sf /usr/local/lib/nodejs/node-v${NODE_VERSION}-linux-${NODE_ARCH}/bin/corepack /usr/local/bin/corepack
rm -f /tmp/${NODE_TARBALL}
EOF
