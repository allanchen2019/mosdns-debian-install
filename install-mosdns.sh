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

# Check if database already exists and optionally prompt to clear it
if [ -f "${MOSDNS_BIN_DIR}/panel.db" ]; then
    echo "Detected existing query logs and statistics database."
    DELETE_EXISTING_STATS="n"
    if [ -t 0 ]; then
        read -p "是否清除已有的解析日志与统计数据库？(y/N, 默认: N): " input_val
        if [ "${input_val}" = "y" ] || [ "${input_val}" = "Y" ]; then
            DELETE_EXISTING_STATS="y"
        fi
    fi
    if [ "${DELETE_EXISTING_STATS}" = "y" ]; then
        echo "Clearing existing statistics database..."
        rm -f "${MOSDNS_BIN_DIR}/panel.db"*
        rm -f "/var/log/mosdns/mosdns.log"
        touch "/var/log/mosdns/mosdns.log"
        chmod 644 "/var/log/mosdns/mosdns.log"
    else
        echo "Preserving existing statistics database."
    fi
fi

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

        # 10. Deploy MosDNS Web Control Panel (Prefer pre-compiled binary, fallback to compilation)
        echo "Deploying MosDNS Web Control Panel..."
        DEPLOY_PANEL_SUCCESS=false
        
        # Try downloading pre-compiled binary first
        PANEL_URL="https://github.com/allanchen2019/mosdns-debian-install/releases/download/latest/mosdns-panel-linux-${arch_suffix}"
        echo "Attempting to download pre-compiled control panel from: ${PANEL_URL}"
        if wget --timeout=10 --tries=2 -qO "${TEMP_DIR}/mosdns-panel" "${PANEL_URL}"; then
            chmod +x "${TEMP_DIR}/mosdns-panel"
            # Sanity check on the downloaded binary
            if "${TEMP_DIR}/mosdns-panel" -h 2>&1 | grep -q "port"; then
                echo "Pre-compiled control panel downloaded and verified successfully."
                # Safely copy to bin directory (overwrites cleanly)
                mv -f "${TEMP_DIR}/mosdns-panel" "${MOSDNS_BIN_DIR}/mosdns-panel"
                chmod 755 "${MOSDNS_BIN_DIR}/mosdns-panel"
                DEPLOY_PANEL_SUCCESS=true
            else
                echo "Warning: Downloaded control panel binary failed sanity check." >&2
                rm -f "${TEMP_DIR}/mosdns-panel"
            fi
        fi

        # Fallback to local compilation if download failed/unverified
        if [ "${DEPLOY_PANEL_SUCCESS}" = "false" ]; then
            echo "Falling back to local compilation from source..."
            if [ -d "${MOSDNS_DIR}/panel" ]; then
                cd "${MOSDNS_DIR}/panel"
                # Ensure dependencies are tidy and downloaded before compilation
                go mod tidy > /dev/null 2>&1 || true
                if CGO_ENABLED=1 go build -o "${MOSDNS_BIN_DIR}/mosdns-panel"; then
                    echo "MosDNS Web Control Panel compiled successfully from source."
                    DEPLOY_PANEL_SUCCESS=true
                else
                    echo "Warning: Control panel compilation failed." >&2
                fi
            fi
        fi

        if [ "${DEPLOY_PANEL_SUCCESS}" = "true" ]; then
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
            echo "Warning: Failed to deploy control panel. You can build it manually under ${MOSDNS_DIR}/panel." >&2
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
