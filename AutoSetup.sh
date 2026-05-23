#!/bin/bash
# Description: Lightweight, robust bootstrap script for MosDNS installation
# Author: Antigravity
# Date: 2026-05-22

set -euo pipefail

echo "=========================================="
echo "Initializing MosDNS Pre-requisites..."
echo "=========================================="

# 1. Check Root Privilege
if [ "$EUID" -ne 0 ]; then
    echo "Fatal: Please run this script as root." >&2
    exit 1
fi

# 2. Install minimal required dependencies (No bloated python/pip/git if already present)
echo "Installing minimal system utilities (wget, unzip, git, golang, gcc)..."
apt-get update -y > /dev/null 2>&1 || true
apt-get install -y wget unzip git golang-go gcc > /dev/null 2>&1

MOSDNS_DIR="/opt/mosdns"

# 3. Handle Pre-existing repository safely (Idempotency)
if [ -d "${MOSDNS_DIR}" ]; then
    echo "Found existing directory at ${MOSDNS_DIR}."
    # If it is already a git repository, pull updates to save bandwidth
    if [ -d "${MOSDNS_DIR}/.git" ]; then
        echo "Updating local repository via git fetch..."
        cd "${MOSDNS_DIR}"
        git fetch --all > /dev/null 2>&1 || true
        git reset --hard origin/feat/control-panel > /dev/null 2>&1 || true
    else
        echo "Directory exists but is not a git repository. Backing up and re-cloning..."
        mv "${MOSDNS_DIR}" "${MOSDNS_DIR}_bak_$(date +%s)"
        git clone -b feat/control-panel https://github.com/allanchen2019/mosdns-debian-install.git "${MOSDNS_DIR}"
    fi
else
    echo "Cloning MosDNS deployment repository..."
    git clone -b feat/control-panel https://github.com/allanchen2019/mosdns-debian-install.git "${MOSDNS_DIR}"
fi

# 4. Set secure but executable permissions
chmod 755 -R "${MOSDNS_DIR}"

# 5. Delegate installation to main installer
echo "Launching master installer..."
if bash "${MOSDNS_DIR}/install-mosdns.sh"; then
    echo "=========================================="
    echo "MosDNS Bootstrap completed successfully!"
    echo "=========================================="
else
    echo "Fatal: Master installation script reported failure." >&2
    exit 1
fi
