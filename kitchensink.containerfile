FROM codercom/enterprise-base:ubuntu

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Run everything as root
USER root

# Avoid prompts from apt during build
ENV DEBIAN_FRONTEND=noninteractive

# Set the Timezone
RUN ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime

# ==========================================
# Install Standalone Binaries via COPY
# ==========================================
COPY --chown=coder:coder --from=docker.io/hashicorp/terraform:latest /bin/terraform /usr/local/bin/terraform

################################################################################
# System packages                                                              #
################################################################################

# The base image already provides build-essential, curl, git, jq, sudo,
# wget, python3, pipx, and Docker.
RUN <<EORUN
# Remove the broken Yarn repo from the base image since we use NVM
rm -f /etc/apt/sources.list.d/yarn.list

apt-get update
apt-get install -yqq --no-install-recommends --no-install-suggests -o=Dpkg::Use-Pty=0 \
  autoconf \
  automake \
  bash-completion \
  ca-certificates \
  cmake \
  gnupg \
  less \
  software-properties-common \
  sqlite3 \
  tree \
  tzdata \
  xz-utils \
  zsh
rm -rf /var/lib/apt/lists/*

EORUN

# Everything below installs into user-owned prefixes as the coder user.
USER coder
ENV HOME=/home/coder
ENV PATH=$HOME/.local/bin:$PATH

################################################################################
# Homebrew                                                                     #
################################################################################

# Homebrew 5.0 supports Linux ARM64/AArch64 as Tier 1, so bottles exist
# for both platforms this image builds for.
ENV PATH=/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

RUN brew install \
    bun \
    cargo-binstall \
    clang-format \
    fish \
    fnm \
    go \
    gofumpt \
    golangci-lint \
    gradle \
    hadolint \
    just \
    kotlin \
    maven \
    mise \
    ninja \
    node \
    opentofu \
    pkgconf \
    pnpm \
    powershell \
    rebar3 \
    ripgrep-all \
    ruby \
    shellcheck \
    shfmt \
    staticcheck \
    typos-cli \
    uv \
    yarn \
    && brew cleanup --prune=all && \
    rm -rf "$(brew --cache)"

# openjdk is keg-only in Homebrew, so expose it explicitly for tools
# that expect java on PATH.
ENV JAVA_HOME=/home/linuxbrew/.linuxbrew/opt/openjdk
ENV PATH=$PATH:$JAVA_HOME/bin

################################################################################
# Powershell
#
################################################################################

RUN pwsh -NoProfile -NonInteractive -Command - <<"EOF"
$ErrorActionPreference = 'Stop'
$ConfirmPreference = 'None'
Write-Host "Installing NuGet package provider..."
Install-PackageProvider -Name NuGet -Force
Write-Host "Registering and Trusting PSGallery..."
if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
    Register-PSRepository -Default -InstallationPolicy Trusted
} else {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
}
Write-Host "Installing Modules..."
Install-Module -Name PSScriptAnalyzer, MilestonePSTools, powershell-yaml, PSFramework -Force
EOF

################################################################################
# uv                                                                           #
################################################################################

RUN uv python install --default 3.14

################################################################################
# rustup                                                                       #
################################################################################

ENV PATH=$HOME/.cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y \
    --no-modify-path

RUN cargo binstall cargo-nextest --secure

################################################################################
# go                                                                           #
################################################################################

ENV GOPATH=$HOME/go
ENV GOBIN=$GOPATH/bin
ENV PATH=$PATH:$GOBIN

# Install Node Tooling
# warning: Pin versions in npm. Instead of `npm install <package>` use `npm install <package>@<version>`
# hadolint ignore=DL3016
RUN npm install -g prettier

# ==========================================
# Bake Pre-commit Template into Image
# ==========================================
RUN mkdir -p /opt/coder/templates
COPY --chmod=644 .pre-commit-config.yaml /opt/coder/templates/.pre-commit-config.yaml
COPY --chmod=644 .gitignore_system /opt/coder/templates/.gitignore_system
RUN git config --system core.excludesfile /opt/coder/templates/.gitignore_system

################################################################################
# Sanity checks                                                                #
################################################################################

RUN brew --version && \
    mise --version && \
    go version && \
    node -v && npm -v && yarn -v && pnpm -v && fnm --version && \
    uv --version && python3 --version && \
    cargo -V && cargo nextest --version && \
    ruby --version && \
    java -version && gradle --version && mvn --version && \
    just --version && tofu version
