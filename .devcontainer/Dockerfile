FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# The padawan-fw runc shim bind-mounts a mode-0700 tmpdir over /etc/ssl/certs in every
# container it starts (including each Docker build container). Root can already traverse
# 0700 directories, so all apt/curl calls below work without any cert redirection.
# Opening each network-touching RUN step with chmod 755 /etc/ssl/certs additionally
# makes the directory traversable by non-root users within the same RUN step.

ARG UV_VERSION=0.6.6
ARG PYTHON_VERSION=3.13.2
ARG NODE_VERSION=24.14.1
ARG NVM_VERSION=0.40.4
ENV PYENV_ROOT=/opt/pyenv
ENV PATH=${PYENV_ROOT}/shims:${PYENV_ROOT}/bin:${PATH}
ENV NVM_DIR=/opt/nvm

# Install uv system-wide (arch-aware direct download).
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

# Install build dependencies required by pyenv and CPython compilation.
RUN <<EOF
set -e
chmod 755 /etc/ssl/certs
apt-get update
apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    libbz2-dev \
    libffi-dev \
    liblzma-dev \
    libncursesw5-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    llvm \
    make \
    tk-dev \
    wget \
    xz-utils \
    zlib1g-dev
rm -rf /var/lib/apt/lists/*
mkdir -p "${PYENV_ROOT}"
git clone --depth=1 https://github.com/pyenv/pyenv.git "${PYENV_ROOT}"
chown -R vscode:vscode "${PYENV_ROOT}"
EOF

# Install the pinned Python version with pyenv and set it as the global default.
USER vscode
RUN <<EOF
set -e
sudo chmod 755 /etc/ssl/certs
export PYENV_ROOT="${PYENV_ROOT}"
export PATH="${PYENV_ROOT}/bin:${PATH}"
eval "$(pyenv init -)"
pyenv install -s "${PYTHON_VERSION}"
pyenv global "${PYTHON_VERSION}"
EOF

# Install nvm and the pinned Node version in a system location.
USER root
RUN <<EOF
set -e
chmod 755 /etc/ssl/certs
mkdir -p "${NVM_DIR}"
chown -R vscode:vscode "${NVM_DIR}"
EOF

USER vscode
RUN <<EOF
set -e
sudo chmod 755 /etc/ssl/certs
curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | PROFILE=/dev/null bash
set +e
. "${NVM_DIR}/nvm.sh"
set -e
nvm install "${NODE_VERSION}"
nvm alias default "${NODE_VERSION}"
nvm cache clear
EOF

# Make nvm and the default Node version available from the system shell init
# path rather than user dotfiles.
USER root
RUN <<EOF
set -e
cat >/etc/profile.d/pyenv.sh <<'EOPYENV'
export PYENV_ROOT="/opt/pyenv"
export PATH="${PYENV_ROOT}/bin:${PYENV_ROOT}/shims:${PATH}"

if command -v pyenv >/dev/null 2>&1; then
    eval "$(pyenv init -)"
fi
EOPYENV
chmod 0644 /etc/profile.d/pyenv.sh
grep -qxF '. /etc/profile.d/pyenv.sh' /etc/bash.bashrc || echo '. /etc/profile.d/pyenv.sh' >> /etc/bash.bashrc
if [ -f /etc/zsh/zshrc ]; then
    grep -qxF '. /etc/profile.d/pyenv.sh' /etc/zsh/zshrc || echo '. /etc/profile.d/pyenv.sh' >> /etc/zsh/zshrc
fi
if [ -f /etc/zshrc ]; then
    grep -qxF '. /etc/profile.d/pyenv.sh' /etc/zshrc || echo '. /etc/profile.d/pyenv.sh' >> /etc/zshrc
fi

cat >/etc/profile.d/nvm.sh <<'EONVM'
export NVM_DIR="/opt/nvm"

if [ -s "${NVM_DIR}/nvm.sh" ]; then
    . "${NVM_DIR}/nvm.sh"
    nvm use --silent default >/dev/null 2>&1 || true
fi
EONVM
chmod 0644 /etc/profile.d/nvm.sh
grep -qxF '. /etc/profile.d/nvm.sh' /etc/bash.bashrc || echo '. /etc/profile.d/nvm.sh' >> /etc/bash.bashrc
if [ -f /etc/zsh/zshrc ]; then
    grep -qxF '. /etc/profile.d/nvm.sh' /etc/zsh/zshrc || echo '. /etc/profile.d/nvm.sh' >> /etc/zsh/zshrc
fi
if [ -f /etc/zshrc ]; then
    grep -qxF '. /etc/profile.d/nvm.sh' /etc/zshrc || echo '. /etc/profile.d/nvm.sh' >> /etc/zshrc
fi
EOF

USER vscode
