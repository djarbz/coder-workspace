# Choose from: base, desktop, node, golang
# See https://hub.docker.com/u/codercom for options
ARG ENV_FLAVOR=base
FROM docker.io/codercom/enterprise-${ENV_FLAVOR}:ubuntu
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

USER root

# Install baseline packages
# warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>`
# hadolint ignore=DL3008
RUN <<EORUN
apt-get update
apt-get install -yqq --no-install-recommends --no-install-suggests -o=Dpkg::Use-Pty=0 \
tzdata \
xz-utils \
bash-completion
rm -rf /var/lib/apt/lists/*
EORUN

# Set the Timezone
RUN ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime

USER coder
ENV BIN_DIR=/home/coder/.local/bin

RUN <<EORUN
mkdir -p ${BIN_DIR}
curl -SsL "https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.x86_64.tar.xz" | tar -xJvf - -C "${BIN_DIR}/" --strip-components=1 --wildcards '*/shellcheck'
EORUN
