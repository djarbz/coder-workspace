# Choose from: base, desktop, node, golang
# See https://hub.docker.com/u/codercom for options
ARG ENV_FLAVOR=base

# STAGE 1: Builder
# This stage discovers the latest shfmt version, downloads it, and makes it executable.
FROM alpine:3.20 AS builder
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# Install curl for downloading and jq for parsing JSON from the GitHub API
# warning: Pin versions in apk add. Instead of `apk add <package>` use `apk add <package>=<version>`
# hadolint ignore=DL3018
RUN apk add --no-cache curl jq

# Set target OS and architecture as build arguments for flexibility
ARG TARGETOS=linux
ARG TARGETARCH=amd64

# This RUN command is a multi-line script to perform all the necessary steps
RUN <<EORUN
# Exit immediately if a command exits with a non-zero status.
set -e

# Discover the latest release tag from the mvdan/sh GitHub repository
# The tag will be in a format like "v3.8.0"
LATEST_TAG=$(curl -sL "https://api.github.com/repos/mvdan/sh/releases/latest" | jq -r ".tag_name")

# Check if the tag was successfully fetched
if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" = "null" ]; then
  echo "Error: Could not fetch the latest release tag from GitHub."
  exit 1
fi

echo "Discovered latest shfmt version: ${LATEST_TAG}"

# Construct the binary name and the full download URL
BINARY_NAME="shfmt_${LATEST_TAG}_${TARGETOS}_${TARGETARCH}"
DOWNLOAD_URL="https://github.com/mvdan/sh/releases/download/${LATEST_TAG}/${BINARY_NAME}"

echo "Downloading from ${DOWNLOAD_URL}"

# Download the binary using curl, placing it directly in /usr/local/bin/
# The -L flag follows redirects
curl -sLo /usr/local/bin/shfmt "${DOWNLOAD_URL}"

# Make the downloaded binary executable
chmod +x /usr/local/bin/shfmt


# (Optional) Verify the installation by printing the version
echo "shfmt installation complete:"
shfmt --version
EORUN


# STAGE 2: Final Image
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
bash-completion \
gnupg \
software-properties-common
rm -rf /var/lib/apt/lists/*
EORUN

# Set the Timezone
RUN ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime

COPY --chown=coder:coder --from=builder /usr/local/bin/shfmt /usr/local/bin/shfmt

# Install NVM and Node
ENV NVM_VERSION=v0.40.3
ENV NVM_DIR=/usr/local/nvm
RUN mkdir -p "${NVM_DIR}"
RUN curl -fsSL -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash
# install node and npm
RUN source ${NVM_DIR}/nvm.sh \
    && nvm install --lts --latest-npm

# Install Node Tooling
RUN npm install -g bun prettier

# Install Terraform
RUN <<EORUN
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | gpg --dearmor \
  | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
gpg --no-default-keyring \
  --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
  --fingerprint
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
EORUN
# warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>`
# hadolint ignore=DL3008
RUN <<EORUN
apt-get update
apt-get install -yqq --no-install-recommends --no-install-suggests -o=Dpkg::Use-Pty=0 \
terraform
rm -rf /var/lib/apt/lists/*
EORUN

USER coder
ENV BIN_DIR=/home/coder/.local/bin

# Install Shellcheck
RUN <<EORUN
mkdir -p ${BIN_DIR}
curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.x86_64.tar.xz" | tar -xJvf - -C "${BIN_DIR}/" --strip-components=1 --wildcards '*/shellcheck'
EORUN
