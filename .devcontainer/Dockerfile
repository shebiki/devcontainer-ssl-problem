FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# The padawan-fw runc shim bind-mounts a mode-0700 tmpdir over /etc/ssl/certs in every
# container it starts (including each Docker build container). Root can already traverse
# 0700 directories, so all apt/curl calls below work without any cert redirection.
# Opening each network-touching RUN step with chmod 755 /etc/ssl/certs additionally
# makes the directory traversable by non-root users within the same RUN step.

# Install Python 3.13 via deadsnakes PPA
RUN chmod 755 /etc/ssl/certs \
    && apt-get update \
    && apt-get install -y --no-install-recommends software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends python3.13 python3.13-venv \
    && curl -sSL https://bootstrap.pypa.io/get-pip.py | python3.13 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 100 \
    && rm -rf /var/lib/apt/lists/*

# Install Node LTS via NodeSource
RUN chmod 755 /etc/ssl/certs \
    && curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
