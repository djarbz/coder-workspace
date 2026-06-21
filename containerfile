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
# 1. Install Standalone Binaries via COPY
# ==========================================
COPY --chown=coder:coder --from=ghcr.io/hadolint/hadolint:latest /bin/hadolint /usr/local/bin/hadolint
COPY --chown=coder:coder --from=docker.io/mvdan/shfmt:latest /bin/shfmt /usr/local/bin/shfmt
COPY --chown=coder:coder --from=docker.io/koalaman/shellcheck:stable /bin/shellcheck /usr/local/bin/shellcheck
COPY --chown=coder:coder --from=docker.io/hashicorp/terraform:latest /bin/terraform /usr/local/bin/terraform
COPY --chown=coder:coder --from=docker.io/oven/bun:latest /usr/local/bin/bun /usr/local/bin/bun

# ==========================================
# 2. Install Baseline System Packages
# ==========================================
# warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>`
# hadolint ignore=DL3008
RUN <<EORUN
apt-get update
apt-get install -yqq --no-install-recommends --no-install-suggests -o=Dpkg::Use-Pty=0 \
tzdata \
xz-utils \
bash-completion \
gnupg \
software-properties-common \
ripgrep
apt-get clean
rm -rf /var/lib/apt/lists/*
EORUN

# ==========================================
# 3. Install Python from Deadsnakes PPA
# ==========================================
RUN <<EORUN
add-apt-repository ppa:deadsnakes/ppa
apt-get update
apt-get install -yqq --no-install-recommends --no-install-suggests -o=Dpkg::Use-Pty=0 \
python3.15 \
python3.15-venv \
python3.15-dev
apt-get clean
rm -rf /var/lib/apt/lists/*
EORUN

# ==========================================
# Install PowerShell & Modules
# ==========================================

# 1. Install PowerShell Core via apt
RUN <<EORUN
# Get the version of Ubuntu (provides VERSION_ID)
source /etc/os-release

# Download the Microsoft repository config using curl
curl -sL -o packages-microsoft-prod.deb "https://packages.microsoft.com/config/ubuntu/\${VERSION_ID}/packages-microsoft-prod.deb"

# Register the Microsoft repository keys
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

# Update the list of packages and install PowerShell
apt-get update
apt-get install -yqq --no-install-recommends --no-install-suggests -o=Dpkg::Use-Pty=0 powershell
apt-get clean
rm -rf /var/lib/apt/lists/*
EORUN

# 2. Configure PowerShell and Install Modules
# We use -Scope AllUsers so the 'coder' user can access them later.
RUN pwsh -NoProfile -NonInteractive -Command - <<EOF
\$ErrorActionPreference = 'Stop'
\$ConfirmPreference = 'None'

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
# Install PowerShell Modules
# ==========================================
# We pipe a heredoc directly into pwsh.
# We use -Scope AllUsers so the 'coder' user can access them later.
RUN pwsh -NoProfile -NonInteractive -Command - <<EOF
\$ErrorActionPreference = 'Stop'
\$ConfirmPreference = 'None'

Write-Host "Trusting PSGallery..."
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

Write-Host "Installing Modules..."
# You can pass multiple modules to Install-Module in an array to speed up installation
Install-Module -Name PSScriptAnalyzer, MilestonePSTools, powershell-yaml, PSFramework -Scope AllUsers -Force
EOF

# ==========================================
# 4. Install NVM, Node, and Tooling
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
# 5. Final Setup
# ==========================================
USER coder
ENV BIN_DIR=/home/coder/.local/bin
RUN mkdir -p ${BIN_DIR}
