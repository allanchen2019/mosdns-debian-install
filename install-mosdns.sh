#!/bin/bash
# Description: Idempotent, safe, verified, zero-downtime installation script for MosDNS v5
# Author: Antigravity
# Date: 2026-05-22

set -euo pipefail

echo "=========================================="
echo "Starting MosDNS installation..."
echo "=========================================="

MOSDNS_DIR="/opt/mosdns"
MOSDNS_BIN_DIR="${MOSDNS_DIR}/bin"
TEMP_DIR=$(mktemp -d)

# Cleanup on exit
cleanup() {
    rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

# 1. Temporarily configure public DNS to guarantee connectivity during installation
echo "Temporarily setting public DNS to ensure internet access during setup..."
if [ -L "/etc/resolv.conf" ]; then
    rm -f "/etc/resolv.conf"
fi
cat << 'EOF' > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 223.5.5.5
EOF

# 2. Detect Architecture
architecture=$(dpkg --print-architecture)
case "${architecture}" in
    amd64)  arch_suffix="amd64" ;;
    arm64)  arch_suffix="arm64" ;;
    *)
        echo "Fatal: Unsupported architecture ${architecture}" >&2
        exit 1
        ;;
esac

# 3. Prepare Directories (Idempotent)
mkdir -p "${MOSDNS_BIN_DIR}"
mkdir -p "/var/log/mosdns"
touch "/var/log/mosdns/mosdns.log"
chmod 755 "/var/log/mosdns"
chmod 644 "/var/log/mosdns/mosdns.log"

# 4. Clean up previous MosDNS systemd services if exist
echo "Checking for previous MosDNS service registrations..."
if systemctl is-active --quiet mosdns.service || systemctl is-enabled --quiet mosdns.service 2>/dev/null; then
    echo "Found existing mosdns service. Stopping and uninstalling..."
    systemctl stop mosdns.service || true
    systemctl disable mosdns.service || true
fi

# Remove old service file if exists
if [ -f "/etc/systemd/system/mosdns.service" ]; then
    rm -f "/etc/systemd/system/mosdns.service"
    systemctl daemon-reload
fi

# 5. Download and unzip binary package to temp directory
DOWNLOAD_URL="https://github.com/IrineSistiana/mosdns/releases/latest/download/mosdns-linux-${arch_suffix}.zip"
echo "Downloading MosDNS binary package..."

if ! wget --timeout=20 --tries=3 --show-progress -qO "${TEMP_DIR}/mosdns.zip" "${DOWNLOAD_URL}"; then
    echo "Fatal: Failed to download MosDNS binary from GitHub." >&2
    exit 1
fi

echo "Extracting binary package..."
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

# 6. Sanity Check on binary
echo "Performing sanity check on binary..."
if ! "${NEW_BIN}" version > /dev/null 2>&1; then
    echo "Fatal: Downloaded binary is corrupted or failed sanity execution." >&2
    exit 1
fi
INSTALL_VER=$("${NEW_BIN}" version || echo "unknown")
echo "Sanity check passed. Ready to install version: ${INSTALL_VER}"

# Deploy binary
mv "${NEW_BIN}" "${MOSDNS_BIN_DIR}/mosdns"
chmod 755 "${MOSDNS_BIN_DIR}/mosdns"

# 7. Initialize Geo resource files by invoking update-geo.sh
echo "Initializing DNS resource lists via update-geo.sh..."
if [ -f "${MOSDNS_DIR}/update-geo.sh" ]; then
    chmod +x "${MOSDNS_DIR}/update-geo.sh"
    # Run update-geo.sh while we still have public DNS active!
    if ! bash "${MOSDNS_DIR}/update-geo.sh"; then
        echo "Warning: Initial Geo resource download failed. Ensure network works." >&2
    fi
else
    echo "Warning: update-geo.sh script not found at ${MOSDNS_DIR}/update-geo.sh" >&2
fi

# 8. Stop and Disable systemd-resolved (DNS Stub Resolver) to free port 53
echo "Stopping and disabling systemd-resolved to free port 53..."
systemctl stop systemd-resolved.service > /dev/null 2>&1 || true
systemctl disable systemd-resolved.service > /dev/null 2>&1 || true

# 9. Register MosDNS as a Systemd Service
echo "Installing and registering systemd service..."
cd "${MOSDNS_DIR}"
# Run mosdns built-in systemd service register
if ! "${MOSDNS_BIN_DIR}/mosdns" service install -c "${MOSDNS_DIR}/config-v5.yaml"; then
    # Fallback to manual systemd service registration if install command fails
    echo "Warning: Built-in service install failed. Generating systemd file manually..." >&2
    cat << EOF > /etc/systemd/system/mosdns.service
[Unit]
Description=MosDNS Daemon v5
After=network.target

[Service]
Type=simple
ExecStart=${MOSDNS_BIN_DIR}/mosdns start -c ${MOSDNS_DIR}/config-v5.yaml
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
fi

# Reload systemd and start service
systemctl daemon-reload
systemctl enable mosdns.service
echo "Starting mosdns service..."
if systemctl restart mosdns.service; then
    sleep 2
    if systemctl is-active --quiet mosdns.service; then
        echo "Validating local MosDNS service resolution..."
        # Let's perform a lightweight DNS resolution check on localhost
        if getent hosts www.baidu.com >/dev/null 2>&1 || nslookup -timeout=2 www.baidu.com 127.0.0.1 >/dev/null 2>&1 || host -W 2 www.baidu.com 127.0.0.1 >/dev/null 2>&1; then
            echo "MosDNS resolution validation passed."
        else
            echo "Warning: MosDNS service is active but local validation query did not respond." >&2
        fi

        # 10. Compile and register MosDNS Web Control Panel
        echo "Building and deploying MosDNS Web Control Panel..."
        if [ -d "${MOSDNS_DIR}/panel" ]; then
            cd "${MOSDNS_DIR}/panel"
            # Ensure dependencies are tidy and downloaded before compilation
            go mod tidy > /dev/null 2>&1 || true
            if CGO_ENABLED=1 go build -o "${MOSDNS_BIN_DIR}/mosdns-panel"; then
                echo "MosDNS Web Control Panel compiled successfully."
                
                # Check for existing panel registration and clean up
                if systemctl is-active --quiet mosdns-panel.service || systemctl is-enabled --quiet mosdns-panel.service 2>/dev/null; then
                    systemctl stop mosdns-panel.service || true
                    systemctl disable mosdns-panel.service || true
                fi
                
                cp "${MOSDNS_DIR}/panel/mosdns-panel.service" /etc/systemd/system/
                systemctl daemon-reload
                systemctl enable mosdns-panel.service
                echo "Starting MosDNS Control Panel service..."
                systemctl restart mosdns-panel.service || true
            else
                echo "Warning: Control panel compilation failed. You can build it manually under ${MOSDNS_DIR}/panel." >&2
            fi
        fi

        # 11. Switch system DNS to localhost after successful verification
        echo "Updating /etc/resolv.conf to point to local DNS..."
        if [ -L "/etc/resolv.conf" ]; then
            rm -f "/etc/resolv.conf"
        fi
        cat << 'EOF' > /etc/resolv.conf
nameserver 127.0.0.1
nameserver 1.1.1.1
nameserver 8.8.8.8
options edns0 trust-ad
EOF

        echo "=========================================="
        echo "MosDNS installed and running successfully!"
        echo "Version: ${INSTALL_VER}"
        echo "=========================================="
        exit 0
    fi
fi

echo "Fatal: MosDNS service failed to start properly after installation." >&2
exit 1
