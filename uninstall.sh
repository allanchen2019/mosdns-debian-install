#!/bin/bash
# Description: Safe, verified, clean uninstaller for MosDNS
# Author: Antigravity
# Date: 2026-05-22

set -uo pipefail

echo "=========================================="
echo "Starting MosDNS Uninstallation..."
echo "=========================================="

# 1. Check Root Privilege
if [ "$EUID" -ne 0 ]; then
    echo "Fatal: Please run this script as root." >&2
    exit 1
fi

# 2. Stop and Disable MosDNS & Control Panel Daemons
echo "Stopping and disabling MosDNS service..."
if systemctl is-active --quiet mosdns.service || systemctl is-enabled --quiet mosdns.service 2>/dev/null; then
    systemctl stop mosdns.service || true
    systemctl disable mosdns.service || true
fi
# Forcefully kill any orphaned mosdns processes
pkill -9 mosdns || true

echo "Stopping and disabling MosDNS Control Panel service..."
if systemctl is-active --quiet mosdns-panel.service || systemctl is-enabled --quiet mosdns-panel.service 2>/dev/null; then
    systemctl stop mosdns-panel.service || true
    systemctl disable mosdns-panel.service || true
fi
# Forcefully kill any orphaned panel processes
pkill -9 mosdns-panel || true

# Remove systemd service configurations
if [ -f "/etc/systemd/system/mosdns.service" ]; then
    rm -f "/etc/systemd/system/mosdns.service"
fi
if [ -f "/etc/systemd/system/mosdns-panel.service" ]; then
    rm -f "/etc/systemd/system/mosdns-panel.service"
fi
systemctl daemon-reload
systemctl reset-failed

# 3. Restore System DNS to high-availability defaults
echo "Restoring system DNS resolution configuration..."
if [ -L "/etc/resolv.conf" ]; then
    rm -f "/etc/resolv.conf"
fi

# We write standard public resolvers first to guarantee instantaneous network recovery
cat << 'EOF' > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# 4. Rollback and Re-enable systemd-resolved (if preferred/available)
echo "Re-enabling and starting systemd-resolved..."
if systemctl list-unit-files | grep -q systemd-resolved.service; then
    systemctl enable systemd-resolved.service >/dev/null 2>&1 || true
    systemctl restart systemd-resolved.service || true
    
    # Standard Debian/Ubuntu practice: Link resolv.conf back to systemd-resolved stub
    echo "Linking /etc/resolv.conf back to systemd-resolved stub..."
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

echo "DNS resolution has been successfully restored."

# 5. Clean up MosDNS program directory (Executed as the absolute final step to prevent self-destruction failure)
echo "Cleaning up MosDNS deployment files..."
MOSDNS_DIR="/opt/mosdns"

DELETE_STATS="n"
DELETE_USER_CONFIGS="n"

if [ -t 0 ]; then
    read -p "是否清除所有解析日志与历史统计数据库？(y/N, 默认: N): " input_val
    if [ "${input_val}" = "y" ] || [ "${input_val}" = "Y" ]; then
        DELETE_STATS="y"
    fi
    
    read -p "是否清除用户自定义的配置文件与规则列表(如 config-v5.yaml、local-domain.txt 等)？(y/N, 默认: N): " input_val_config
    if [ "${input_val_config}" = "y" ] || [ "${input_val_config}" = "Y" ]; then
        DELETE_USER_CONFIGS="y"
    fi
fi

# Define online/downloaded rules to always clean up if uninstalling
ONLINE_RULES=("china-list.txt" "apple-cn.txt" "proxy-list.txt" "cn_ipv4.txt" "cn_ipv6.txt")

# We want to determine what to delete
if [ "${DELETE_STATS}" = "y" ]; then
    echo "Clearing stats database and log files..."
    rm -f "/var/log/mosdns/mosdns.log"
    rm -f "${MOSDNS_DIR}/bin/panel.db"* || true
fi

# Clean up binaries and online rules
rm -f "${MOSDNS_DIR}/bin/mosdns" "${MOSDNS_DIR}/bin/mosdns-panel" || true
for file in "${ONLINE_RULES[@]}"; do
    rm -f "${MOSDNS_DIR}/bin/${file}" || true
done

# Check what to do with configs and user lists
if [ "${DELETE_USER_CONFIGS}" = "y" ]; then
    echo "Clearing user configurations and custom rules lists..."
    rm -f "${MOSDNS_DIR}/config-v5.yaml" || true
    # Find and delete all remaining .txt files in bin/
    if [ -d "${MOSDNS_DIR}/bin" ]; then
        find "${MOSDNS_DIR}/bin" -name "*.txt" -delete || true
    fi
fi

# Clean up build/source dirs and other deployment files
rm -rf "${MOSDNS_DIR}/panel" || true
rm -rf "${MOSDNS_DIR}/.git" || true
rm -rf "${MOSDNS_DIR}/.github" || true
rm -f "${MOSDNS_DIR}/.gitignore" "${MOSDNS_DIR}/README.md" "${MOSDNS_DIR}/README_zh-CN.md" || true
rm -f "${MOSDNS_DIR}/install-mosdns.sh" "${MOSDNS_DIR}/update-bin.sh" "${MOSDNS_DIR}/update-geo.sh" "${MOSDNS_DIR}/update-all.sh" "${MOSDNS_DIR}/AutoSetup.sh" || true

# If everything is deleted, remove directory entirely
# Check if config, DB or any custom .txt files still exist
KEEP_DIR=false
if [ "${DELETE_USER_CONFIGS}" = "n" ] && [ -f "${MOSDNS_DIR}/config-v5.yaml" ]; then
    KEEP_DIR=true
fi
if [ "${DELETE_STATS}" = "n" ] && [ -f "${MOSDNS_DIR}/bin/panel.db" ]; then
    KEEP_DIR=true
fi
# Check if there are any remaining .txt files (which must be user-defined)
if [ -d "${MOSDNS_DIR}/bin" ] && [ -n "$(find "${MOSDNS_DIR}/bin" -name "*.txt" 2>/dev/null)" ]; then
    KEEP_DIR=true
fi

if [ "${KEEP_DIR}" = "false" ]; then
    echo "No files to preserve. Removing MosDNS directory..."
    rm -rf "${MOSDNS_DIR}" > /dev/null 2>&1 || true
else
    echo "Preserved requested user configurations/database files under ${MOSDNS_DIR}."
    rm -f "${MOSDNS_DIR}/uninstall.sh" > /dev/null 2>&1 || true
fi

echo "=========================================="
echo "MosDNS uninstallation completed successfully!"
echo "=========================================="
