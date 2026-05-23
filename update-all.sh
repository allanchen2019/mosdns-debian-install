#!/bin/bash
# Description: Lossless update script for both MosDNS core binary and Web Control Panel
# Author: Antigravity
# Date: 2026-05-23

set -euo pipefail

cd "$(dirname "$0")"

echo "=========================================="
echo "Starting MosDNS & Control Panel Update..."
echo "=========================================="

MOSDNS_DIR="/opt/mosdns"
MOSDNS_BIN_DIR="${MOSDNS_DIR}/bin"
BACKUP_DIR="${MOSDNS_BIN_DIR}/backup-all"
TEMP_DIR=$(mktemp -d)

# Cleanup on exit
cleanup() {
    rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

# 1. Detect Architecture
if command -v dpkg >/dev/null 2>&1; then
    architecture=$(dpkg --print-architecture)
else
    architecture=$(uname -m)
fi

case "${architecture}" in
    amd64|x86_64)  arch_suffix="amd64" ;;
    arm64|aarch64) arch_suffix="arm64" ;;
    *)
        echo "Fatal: Unsupported architecture ${architecture}" >&2
        exit 1
        ;;
esac

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# 2. Update MosDNS Core Binary
DOWNLOAD_URL="https://github.com/IrineSistiana/mosdns/releases/latest/download/mosdns-linux-${arch_suffix}.zip"
echo "Downloading latest MosDNS core binary from ${DOWNLOAD_URL}..."

MOSDNS_UPDATED=false
if wget --timeout=20 --tries=3 --show-progress -qO "${TEMP_DIR}/mosdns.zip" "${DOWNLOAD_URL}"; then
    echo "Extracting core binary..."
    if unzip -qo "${TEMP_DIR}/mosdns.zip" -d "${TEMP_DIR}" && [ -f "${TEMP_DIR}/mosdns" ]; then
        NEW_BIN="${TEMP_DIR}/mosdns"
        chmod +x "${NEW_BIN}"
        
        # Sanity Check
        if "${NEW_BIN}" version > /dev/null 2>&1; then
            NEW_VER=$("${NEW_BIN}" version || echo "unknown")
            echo "MosDNS core binary sanity check passed. New version: ${NEW_VER}"
            
            # Backup active binary
            if [ -f "${MOSDNS_BIN_DIR}/mosdns" ]; then
                cp "${MOSDNS_BIN_DIR}/mosdns" "${BACKUP_DIR}/mosdns"
            fi
            
            # Deploy
            echo "Deploying new MosDNS core binary..."
            mv -f "${NEW_BIN}" "${MOSDNS_BIN_DIR}/mosdns"
            chmod 755 "${MOSDNS_BIN_DIR}/mosdns"
            MOSDNS_UPDATED=true
        else
            echo "Warning: Downloaded MosDNS core binary failed sanity check." >&2
        fi
    else
        echo "Warning: Failed to extract MosDNS core binary." >&2
    fi
else
    echo "Warning: Failed to download MosDNS core binary." >&2
fi

# 3. Update Web Control Panel Binary
PANEL_URL="https://github.com/allanchen2019/mosdns-debian-install/releases/download/latest/mosdns-panel-linux-${arch_suffix}"
echo "Downloading latest MosDNS Web Control Panel from ${PANEL_URL}..."

PANEL_UPDATED=false
DEPLOY_PANEL_SUCCESS=false

# Try downloading pre-compiled binary
if wget --timeout=15 --tries=2 -qO "${TEMP_DIR}/mosdns-panel" "${PANEL_URL}"; then
    chmod +x "${TEMP_DIR}/mosdns-panel"
    if "${TEMP_DIR}/mosdns-panel" -h 2>&1 | grep -q "port"; then
        echo "Pre-compiled control panel verified successfully."
        # Backup active panel
        if [ -f "${MOSDNS_BIN_DIR}/mosdns-panel" ]; then
            cp "${MOSDNS_BIN_DIR}/mosdns-panel" "${BACKUP_DIR}/mosdns-panel"
        fi
        mv -f "${TEMP_DIR}/mosdns-panel" "${MOSDNS_BIN_DIR}/mosdns-panel"
        chmod 755 "${MOSDNS_BIN_DIR}/mosdns-panel"
        DEPLOY_PANEL_SUCCESS=true
        PANEL_UPDATED=true
    else
        echo "Warning: Downloaded panel binary failed sanity check." >&2
    fi
fi

# Fallback to compilation if download failed
if [ "${DEPLOY_PANEL_SUCCESS}" = "false" ]; then
    echo "Attempting to compile Web Control Panel from local source..."
    if [ -d "${MOSDNS_DIR}/panel" ]; then
        cd "${MOSDNS_DIR}/panel"
        go mod tidy > /dev/null 2>&1 || true
        # Backup active panel
        if [ -f "${MOSDNS_BIN_DIR}/mosdns-panel" ]; then
            cp "${MOSDNS_BIN_DIR}/mosdns-panel" "${BACKUP_DIR}/mosdns-panel"
        fi
        if CGO_ENABLED=1 go build -o "${MOSDNS_BIN_DIR}/mosdns-panel"; then
            echo "Web Control Panel compiled successfully from source."
            chmod 755 "${MOSDNS_BIN_DIR}/mosdns-panel"
            PANEL_UPDATED=true
        else
            echo "Warning: Web Control Panel compilation failed." >&2
            # Restore backup if compilation overwrote or failed
            if [ -f "${BACKUP_DIR}/mosdns-panel" ]; then
                cp "${BACKUP_DIR}/mosdns-panel" "${MOSDNS_BIN_DIR}/mosdns-panel"
                chmod 755 "${MOSDNS_BIN_DIR}/mosdns-panel"
            fi
        fi
    else
        echo "Warning: Web Control Panel source code not found." >&2
    fi
fi

# 4. Restart Services and Verify Status
SERVICES_OK=true

if [ "${MOSDNS_UPDATED}" = "true" ]; then
    echo "Restarting mosdns service..."
    if systemctl restart mosdns.service; then
        sleep 1
        if ! systemctl is-active --quiet mosdns.service; then
            echo "Error: mosdns service failed to start after update." >&2
            SERVICES_OK=false
        fi
    else
        echo "Error: Failed to restart mosdns service." >&2
        SERVICES_OK=false
    fi
fi

if [ "${PANEL_UPDATED}" = "true" ] && [ "${SERVICES_OK}" = "true" ]; then
    echo "Restarting mosdns-panel service..."
    if systemctl restart mosdns-panel.service; then
        sleep 1
        if ! systemctl is-active --quiet mosdns-panel.service; then
            echo "Error: mosdns-panel service failed to start after update." >&2
            SERVICES_OK=false
        fi
    else
        echo "Error: Failed to restart mosdns-panel service." >&2
        SERVICES_OK=false
    fi
fi

# 5. Rollback on Failure
if [ "${SERVICES_OK}" = "false" ]; then
    echo "==========================================" >&2
    echo "WARNING: Service check failed! Rolling back changes..." >&2
    echo "==========================================" >&2
    
    if [ "${MOSDNS_UPDATED}" = "true" ] && [ -f "${BACKUP_DIR}/mosdns" ]; then
        echo "Restoring previous MosDNS core binary..."
        cp -f "${BACKUP_DIR}/mosdns" "${MOSDNS_BIN_DIR}/mosdns"
        chmod 755 "${MOSDNS_BIN_DIR}/mosdns"
        systemctl restart mosdns.service || true
    fi
    
    if [ "${PANEL_UPDATED}" = "true" ] && [ -f "${BACKUP_DIR}/mosdns-panel" ]; then
        echo "Restoring previous Web Control Panel binary..."
        cp -f "${BACKUP_DIR}/mosdns-panel" "${MOSDNS_BIN_DIR}/mosdns-panel"
        chmod 755 "${MOSDNS_BIN_DIR}/mosdns-panel"
        systemctl restart mosdns-panel.service || true
    fi
    
    rm -rf "${BACKUP_DIR}"
    exit 1
fi

rm -rf "${BACKUP_DIR}"
echo "=========================================="
echo "MosDNS & Web Control Panel updated successfully!"
echo "=========================================="
exit 0
