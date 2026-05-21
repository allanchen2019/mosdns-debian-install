#!/bin/bash
# Description: Fully atomic, verified, self-healing update script for MosDNS binary
# Author: Antigravity
# Date: 2026-05-22

set -euo pipefail

echo "=========================================="
echo "Starting MosDNS binary update..."
echo "=========================================="

MOSDNS_BIN_DIR="/opt/mosdns/bin"
BACKUP_DIR="${MOSDNS_BIN_DIR}/backup"
TEMP_DIR=$(mktemp -d)

# Cleanup on exit
cleanup() {
    rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

# 1. Detect architecture
architecture=$(dpkg --print-architecture)
case "${architecture}" in
    amd64)  arch_suffix="amd64" ;;
    arm64)  arch_suffix="arm64" ;;
    *)
        echo "Fatal: Unsupported architecture ${architecture}" >&2
        exit 1
        ;;
esac

# 2. Download latest release via wget with timeout & retries
DOWNLOAD_URL="https://github.com/IrineSistiana/mosdns/releases/latest/download/mosdns-linux-${arch_suffix}.zip"
echo "Downloading binary from ${DOWNLOAD_URL}..."

if ! wget --timeout=20 --tries=3 --show-progress -qO "${TEMP_DIR}/mosdns.zip" "${DOWNLOAD_URL}"; then
    echo "Fatal: Failed to download MosDNS binary package from GitHub." >&2
    exit 1
fi

# 3. Unzip and verify contents
echo "Extracting binary..."
if ! unzip -qo "${TEMP_DIR}/mosdns.zip" -d "${TEMP_DIR}"; then
    echo "Fatal: Failed to unzip MosDNS binary package." >&2
    exit 1
fi

NEW_BIN="${TEMP_DIR}/mosdns"
if [ ! -f "${NEW_BIN}" ]; then
    echo "Fatal: Binary file 'mosdns' not found in extracted package." >&2
    exit 1
fi

chmod +x "${NEW_BIN}"

# 4. Perform sanity check (test execution of the new binary)
echo "Performing sanity check on the new binary..."
if ! "${NEW_BIN}" version > /dev/null 2>&1; then
    echo "Fatal: New binary failed sanity execution check." >&2
    exit 1
fi
NEW_VER=$("${NEW_BIN}" version || echo "unknown")
echo "Sanity check passed. New version detected: ${NEW_VER}"

# 5. Prepare backup of current binary
mkdir -p "${BACKUP_DIR}"
ACTIVE_BIN="${MOSDNS_BIN_DIR}/mosdns"
HAS_BACKUP=false

if [ -f "${ACTIVE_BIN}" ]; then
    cp "${ACTIVE_BIN}" "${BACKUP_DIR}/mosdns"
    HAS_BACKUP=true
fi

# 6. Atomic replacement (using mv to prevent 'Text file busy' error)
echo "Deploying new binary..."
mv "${NEW_BIN}" "${ACTIVE_BIN}"
chmod 755 "${ACTIVE_BIN}"

# 7. Restart service and monitor status
echo "Restarting mosdns service..."
if systemctl restart mosdns.service; then
    sleep 2
    if systemctl is-active --quiet mosdns.service; then
        echo "=========================================="
        echo "MosDNS binary updated successfully to version: ${NEW_VER}!"
        echo "=========================================="
        rm -rf "${BACKUP_DIR}"
        exit 0
    fi
fi

# 8. Rollback in case of failure
echo "==========================================" >&2
echo "WARNING: MosDNS service failed to start with new binary! Rolling back..." >&2
echo "==========================================" >&2

if [ "${HAS_BACKUP}" = true ]; then
    # In case of mv, we restore from BACKUP_DIR
    cp "${BACKUP_DIR}/mosdns" "${ACTIVE_BIN}"
    chmod 755 "${ACTIVE_BIN}"
    systemctl restart mosdns.service
    echo "Rollback completed. MosDNS restored to previous version." >&2
else
    echo "Fatal: Rollback failed. No previous binary backup found!" >&2
fi

exit 1
