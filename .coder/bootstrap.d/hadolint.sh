#!/usr/bin/env bash
BIN_DIR=${BIN_DIR:-"$HOME/.local/bin"}

## Install Hadolint
GH_ORG=hadolint
GH_PROJ=hadolint
GH_REPO=${GH_ORG}/${GH_PROJ}
GH_ASSET=hadolint-Linux-x86_64
GH_BIN=hadolint
echo "Installing ${GH_REPO}..."
GITHUB_RELEASE_VERSION=$(
    git -c 'versionsort.suffix=-' ls-remote --tags --sort='v:refname' https://github.com/${GH_REPO}.git \
    | grep -oP 'refs\/tags\/v?\d+(\.\d+)?(\.\d+)?$' \
    | tail --lines=1 | cut --delimiter='/' --fields=3
)
curl -fsSL "https://github.com/${GH_REPO}/releases/download/${GITHUB_RELEASE_VERSION}/${GH_ASSET}" -o "${BIN_DIR}/${GH_BIN}"
chmod +x "${BIN_DIR}/${GH_BIN}"
