FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# The padawan-fw runc shim bind-mounts a mode-0700 tmpdir over /etc/ssl/certs in every
# container it starts (including Docker build containers), which blocks non-root TLS.
# Root can still traverse 0700, so this RUN step (which runs as root) copies the CA
# bundle to a world-readable path at image-build time.
#
# We then advertise the copy through every mechanism that curl, git, pip, nvm, and
# Node.js honour, covering all the contexts used by devcontainer feature installers:
#   - ~/.curlrc             → read by curl for every user, regardless of env vars or
#                             login context; fixes the `su vscode -c "curl | bash"`
#                             NVM installer download
#   - git config --system   → fixes git's hardcoded /etc/ssl/certs path; used by the
#                             NVM installer when it falls back to `git clone`
#   - /etc/environment      → read by PAM (pam_env) for su and other managed sessions
#   - /etc/profile.d        → sourced by bash login shells (belt-and-suspenders)
#   - Docker ENV            → inherited by downstream Dockerfile/feature-build RUN steps
RUN cp /etc/ssl/certs/ca-certificates.crt /usr/local/share/ca-certificates.crt \
    && chmod 644 /usr/local/share/ca-certificates.crt \
    && echo "cacert=/usr/local/share/ca-certificates.crt" > /home/vscode/.curlrc \
    && echo "cacert=/usr/local/share/ca-certificates.crt" > /root/.curlrc \
    && git config --system http.sslCAInfo /usr/local/share/ca-certificates.crt \
    && { \
         echo 'CURL_CA_BUNDLE=/usr/local/share/ca-certificates.crt'; \
         echo 'GIT_SSL_CAINFO=/usr/local/share/ca-certificates.crt'; \
         echo 'SSL_CERT_FILE=/usr/local/share/ca-certificates.crt'; \
         echo 'NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates.crt'; \
         echo 'PIP_CERT=/usr/local/share/ca-certificates.crt'; \
       } >> /etc/environment \
    && { \
         echo 'export CURL_CA_BUNDLE=/usr/local/share/ca-certificates.crt'; \
         echo 'export GIT_SSL_CAINFO=/usr/local/share/ca-certificates.crt'; \
         echo 'export SSL_CERT_FILE=/usr/local/share/ca-certificates.crt'; \
         echo 'export NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates.crt'; \
         echo 'export PIP_CERT=/usr/local/share/ca-certificates.crt'; \
       } > /etc/profile.d/ca-bundle-workaround.sh \
    && chmod 644 /etc/profile.d/ca-bundle-workaround.sh

ENV CURL_CA_BUNDLE=/usr/local/share/ca-certificates.crt \
    GIT_SSL_CAINFO=/usr/local/share/ca-certificates.crt \
    SSL_CERT_FILE=/usr/local/share/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates.crt \
    PIP_CERT=/usr/local/share/ca-certificates.crt
