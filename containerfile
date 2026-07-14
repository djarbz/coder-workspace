# Choose from: base, desktop, node, golang
# See https://hub.docker.com/u/codercom for options
ARG ENV_FLAVOR=base

# This is a development container, so we often prefer latest versions of the packages.
FROM docker.io/codercom/enterprise-${ENV_FLAVOR}:ubuntu
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

USER root

# Avoid prompts from apt during build
ENV DEBIAN_FRONTEND=noninteractive

# Set the Timezone
RUN ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime

# ==========================================
# Install Standalone Binaries via COPY
# ==========================================
COPY --chown=coder:coder --from=ghcr.io/hadolint/hadolint:latest /bin/hadolint /usr/local/bin/hadolint
COPY --chown=coder:coder --from=docker.io/mvdan/shfmt:latest /bin/shfmt /usr/local/bin/shfmt
COPY --chown=coder:coder --from=docker.io/koalaman/shellcheck:stable /bin/shellcheck /usr/local/bin/shellcheck
COPY --chown=coder:coder --from=docker.io/hashicorp/terraform:latest /bin/terraform /usr/local/bin/terraform
COPY --chown=coder:coder --from=docker.io/oven/bun:latest /usr/local/bin/bun /usr/local/bin/bun
COPY --chown=coder:coder --from=docker.io/golangci/golangci-lint:latest /usr/bin/golangci-lint /usr/local/bin/golangci-lint
COPY --chown=coder:coder --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# ==========================================
# Install Baseline System Packages
# ==========================================
# warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>`
# hadolint ignore=DL3008
RUN <<EORUN
# Remove the broken Yarn repo from the base image since we use NVM
rm -f /etc/apt/sources.list.d/yarn.list

apt-get update
apt-get install -yqq --no-install-recommends --no-install-suggests -o=Dpkg::Use-Pty=0 \
  tzdata \
  xz-utils \
  bash-completion \
  curl \
  gnupg \
  software-properties-common \
  ripgrep \
  tree \
  git
apt-get clean
rm -rf /var/lib/apt/lists/*

EORUN

# ==========================================
# Bake Pre-commit Template into Image
# ==========================================
RUN mkdir -p /opt/coder/templates
COPY --chown=coder:coder .pre-commit-config.yaml /opt/coder/templates/.pre-commit-config.yaml

# ==========================================
# Install Python & Tools using uv
# ==========================================
# Install Python to a global directory
ARG UV_PYTHON_VERSION=3.14
ENV UV_PYTHON_VERSION=${UV_PYTHON_VERSION}
ENV UV_PYTHON_INSTALL_DIR=/opt/python
RUN uv python install ${UV_PYTHON_VERSION}

# Install pre-commit globally using uv tool
ENV UV_TOOL_DIR=/opt/uv-tools
ENV UV_TOOL_BIN_DIR=/usr/local/bin
RUN uv tool install pre-commit

# ==========================================
# Install PowerShell & Modules
# ==========================================
RUN <<"EORUN"
source /etc/os-release
CLEAN_VERSION_ID="${VERSION_ID//"/}"
curl -sSfL -o packages-microsoft-prod.deb "https://packages.microsoft.com/config/ubuntu/${CLEAN_VERSION_ID}/packages-microsoft-prod.deb"
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb
apt-get update
apt-get install -yqq --no-install-recommends --no-install-suggests -o=Dpkg::Use-Pty=0 powershell
apt-get clean
rm -rf /var/lib/apt/lists/*
EORUN

RUN pwsh -NoProfile -NonInteractive -Command - <<"EOF"
$ErrorActionPreference = 'Stop'
$ConfirmPreference = 'None'
Write-Host "Installing NuGet package provider..."
Install-PackageProvider -Name NuGet -Force -Scope AllUsers
Write-Host "Registering and Trusting PSGallery..."
if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
    Register-PSRepository -Default -InstallationPolicy Trusted
} else {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
}
Write-Host "Installing Modules..."
Install-Module -Name PSScriptAnalyzer, MilestonePSTools, powershell-yaml, PSFramework -Scope AllUsers -Force
EOF

# ==========================================
# Install NVM, Node, and Tooling
# ==========================================
ARG NVM_VERSION=v0.40.4
ENV NVM_VERSION=${NVM_VERSION}
ENV NVM_DIR=/usr/local/nvm
RUN mkdir -p "${NVM_DIR}"
RUN curl -fsSL -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash

# info: Not following: File not included in mock.
# hadolint ignore=SC1091
RUN <<EORUN
. ${NVM_DIR}/nvm.sh
nvm install --lts --latest-npm
ln -s "$(nvm which current)" /usr/local/bin/node
ln -s "$(which npm)" /usr/local/bin/npm
EORUN

# Install Node Tooling
# warning: Pin versions in npm. Instead of `npm install <package>` use `npm install <package>@<version>`
# hadolint ignore=DL3016
RUN npm install -g prettier

# ==========================================
# Final Setup
# ==========================================
USER coder
ENV BIN_DIR=/home/coder/.local/bin
RUN mkdir -p ${BIN_DIR}
