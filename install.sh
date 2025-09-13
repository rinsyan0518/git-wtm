#!/bin/bash

# Remote installer for git-wtm (Git Worktree Manager)
# Usage: curl -fsSL https://raw.githubusercontent.com/rinsyan0518/git-wtr/main/install.sh | bash

set -e

# Configuration
BASE="main"
REPO_URL="https://raw.githubusercontent.com/rinsyan0518/git-wtr/${BASE}"
SCRIPT_NAME="git-wtm"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

echo "Installing ${SCRIPT_NAME} ..."

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Download and install
echo "Downloading git-wtm..."
curl -fsSL "${REPO_URL}/${SCRIPT_NAME}.bash" -o "${INSTALL_DIR}/${SCRIPT_NAME}"
chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"

echo "Installation complete!"
