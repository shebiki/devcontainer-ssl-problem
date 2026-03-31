FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# The padawan-fw runc shim bind-mounts a mode-0700 tmpdir over /etc/ssl/certs in every
# container it starts (including Docker build containers), which blocks non-root TLS.
# This RUN step executes as root (which can traverse 0700) and copies the CA bundle to
# a world-readable path at image-build time.  The ENV vars below point curl, pip, nvm,
# and Node.js at that copy so non-root SSL works in all subsequent build layers (feature
# installation) and at container runtime, with no chmod needed at startup.
RUN cp /etc/ssl/certs/ca-certificates.crt /usr/local/share/ca-certificates.crt \
    && chmod 644 /usr/local/share/ca-certificates.crt

ENV CURL_CA_BUNDLE=/usr/local/share/ca-certificates.crt \
    SSL_CERT_FILE=/usr/local/share/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates.crt \
    PIP_CERT=/usr/local/share/ca-certificates.crt
