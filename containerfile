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
RUN mkdir -p /opt/coder/templates && cat <<'EOF' > /opt/coder/templates/.pre-commit-config.yaml
repos:
  # General/File System
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files

  # Python: Ruff (Formatting & Linting)
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.4.8
    hooks:
      - id: ruff
        args: [ --fix ]
      - id: ruff-format

  # Golang: golangci-lint
  - repo: https://github.com/golangci/golangci-lint
    rev: v1.59.0
    hooks:
      - id: golangci-lint

  # Web/JSON/Markdown/YAML: Prettier
  - repo: https://github.com/pre-commit/mirrors-prettier
    rev: v3.1.0
    hooks:
      - id: prettier
        types_or: [javascript, typescript, css, html, json, markdown]

  # Bash/Shell: shfmt & shellcheck
  - repo: https://github.com/scop/pre-commit-shfmt
    rev: v3.8.0-1
    hooks:
      - id: shfmt
        args: ["-w", "-s", "-i", "2"] # Write, simplify, indent 2 spaces
  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.10.0
    hooks:
      - id: shellcheck

  # Docker: Hadolint
  - repo: https://github.com/hadolint/hadolint
    rev: v2.12.0
    hooks:
      - id: hadolint
EOF
RUN chown -R coder:coder /opt/coder/templates

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
RUN uv tool install pre-commit --install-dir /usr/local/bin

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
