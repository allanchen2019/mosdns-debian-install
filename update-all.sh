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
PANEL_URL="https://github.com/allanchen2019/mosdns-debian-install/releases/latest/download/mosdns-panel-linux-${arch_suffix}"
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

# 3.5 Ensure custom filter lists exist and have default rules
echo "Verifying presence of default custom domain filter lists..."
# Initialize/update direct-domain.txt
target_direct_path="${MOSDNS_BIN_DIR}/direct-domain.txt"
if [ ! -f "${target_direct_path}" ]; then
    echo "Creating default direct-domain.txt with custom direct routing rules..."
    cat << 'EOF' > "${target_direct_path}"
# MosDNS 自定义域名列表 - direct-domain.txt
# 每行输入一个规则，例如 domain:example.com

domain:taobao.com
domain:alicdn.com
domain:tbcdn.cn
domain:cn
EOF
    chmod 644 "${target_direct_path}"
else
    echo "Updating existing direct-domain.txt with default direct routing rules..."
    for rule in "domain:taobao.com" "domain:alicdn.com" "domain:tbcdn.cn" "domain:cn"; do
        if ! grep -qxF "${rule}" "${target_direct_path}"; then
            echo "${rule}" >> "${target_direct_path}"
        fi
    done
fi

# Initialize/update local-domain.txt
target_local_path="${MOSDNS_BIN_DIR}/local-domain.txt"
if [ ! -f "${target_local_path}" ]; then
    echo "Creating default local-domain.txt with private network routing rules..."
    cat << 'EOF' > "${target_local_path}"
domain:lan
domain:local
domain:homelab
domain:home
domain:internal
domain:10.in-addr.arpa
domain:168.192.in-addr.arpa
domain:17.172.in-addr.arpa
domain:18.172.in-addr.arpa
domain:19.172.in-addr.arpa
domain:20.172.in-addr.arpa
domain:21.172.in-addr.arpa
domain:22.172.in-addr.arpa
domain:23.172.in-addr.arpa
domain:24.172.in-addr.arpa
domain:25.172.in-addr.arpa
domain:26.172.in-addr.arpa
domain:27.172.in-addr.arpa
domain:28.172.in-addr.arpa
domain:29.172.in-addr.arpa
domain:30.172.in-addr.arpa
domain:31.172.in-addr.arpa
domain:16.172.in-addr.arpa
regexp:^[^.]+$
EOF
    chmod 644 "${target_local_path}"
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
