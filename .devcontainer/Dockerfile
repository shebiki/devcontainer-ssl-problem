FROM mcr.microsoft.com/devcontainers/base:trixie

# Version pins — change these ARGs and rebuild to switch versions.
ARG PYTHON_VERSION=3.13
ARG NODE_VERSION=lts

ENV PYENV_ROOT=/usr/local/pyenv \
    NVM_DIR=/usr/local/nvm

# The padawan-fw runc shim bind-mounts a mode-0700 tmpdir over /etc/ssl/certs in every
# container it starts. Each RUN step opens with chmod 755 /etc/ssl/certs so that both
# root and the non-root vscode user can reach the cert bundle for TLS.

# Build dependencies needed by pyenv to compile Python from source.
RUN chmod 755 /etc/ssl/certs \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
         build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
         libsqlite3-dev libncursesw5-dev xz-utils tk-dev libxml2-dev \
         libxmlsec1-dev libffi-dev liblzma-dev \
    && rm -rf /var/lib/apt/lists/*

# Install pyenv to /usr/local/pyenv and compile the pinned Python version.
# Direct git clone avoids the pyenv-installer script's Launchpad/GitHub API calls
# and makes the install reproducible.
RUN chmod 755 /etc/ssl/certs \
    && git clone https://github.com/pyenv/pyenv.git ${PYENV_ROOT} \
    && ${PYENV_ROOT}/bin/pyenv install ${PYTHON_VERSION} \
    && ${PYENV_ROOT}/bin/pyenv global ${PYTHON_VERSION} \
    && chown -R root:root ${PYENV_ROOT} \
    && chmod -R a+rX ${PYENV_ROOT} \
    && ln -sf "$(${PYENV_ROOT}/bin/pyenv which python3)" /usr/local/bin/python3 \
    && ln -sf "$(${PYENV_ROOT}/bin/pyenv which pip3)"    /usr/local/bin/pip3 \
    && ln -sf "$(${PYENV_ROOT}/bin/pyenv which pip3)"    /usr/local/bin/pip

# Install nvm to /usr/local/nvm and install the pinned Node version.
RUN chmod 755 /etc/ssl/certs \
    && mkdir -p "${NVM_DIR}" \
    && curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh \
         | NVM_DIR="${NVM_DIR}" bash \
    && . "${NVM_DIR}/nvm.sh" \
    && nvm install "${NODE_VERSION}" \
    && nvm alias default "${NODE_VERSION}" \
    && NODE_BIN="$(nvm which default)" \
    && chown -R root:root "${NVM_DIR}" \
    && chmod -R a+rX "${NVM_DIR}" \
    && ln -sf "${NODE_BIN}"                      /usr/local/bin/node \
    && ln -sf "$(dirname "${NODE_BIN}")/npm"     /usr/local/bin/npm \
    && ln -sf "$(dirname "${NODE_BIN}")/npx"     /usr/local/bin/npx
