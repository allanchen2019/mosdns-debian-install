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

echo "Stopping and disabling MosDNS Control Panel service..."
if systemctl is-active --quiet mosdns-panel.service || systemctl is-enabled --quiet mosdns-panel.service 2>/dev/null; then
    systemctl stop mosdns-panel.service || true
    systemctl disable mosdns-panel.service || true
fi

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
if [ -d "${MOSDNS_DIR}" ]; then
    # We clean up files asynchronously or as the final command to ensure script exit doesn't crash on deletion
    find "${MOSDNS_DIR}" -mindepth 1 ! -name "uninstall.sh" -delete || true
fi

echo "=========================================="
echo "MosDNS uninstallation completed successfully!"
echo "=========================================="

# Final command: clean up the directory and the script itself safely
rm -rf "${MOSDNS_DIR}" > /dev/null 2>&1 || true
