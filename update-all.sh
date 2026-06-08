#!/bin/bash
# Description: Refactored, lossless update script supporting release and dev channels for MosDNS core and Web Control Panel
# Author: Antigravity
# Date: 2026-06-08

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

# 1. Parse update channel
CHANNEL="${1:-release}"
if [ "${CHANNEL}" != "release" ] && [ "${CHANNEL}" != "dev" ]; then
    echo "Error: Invalid update channel '${CHANNEL}'. Use 'release' or 'dev'." >&2
    exit 1
fi
echo "Selected update channel: ${CHANNEL}"

# 2. Detect Architecture
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

# Create backup directory for rollback
mkdir -p "${BACKUP_DIR}"

# 3. Safe Configuration & Database Backup before Git Checkout
echo "Backing up configurations, databases, and custom rules..."
BACKUP_TEMP="/tmp/mosdns_update_backup"
rm -rf "${BACKUP_TEMP}"
mkdir -p "${BACKUP_TEMP}"

if [ -f "${MOSDNS_DIR}/config-v5.yaml" ]; then
    cp "${MOSDNS_DIR}/config-v5.yaml" "${BACKUP_TEMP}/"
fi
# Backup SQLite panel database files
for f in "${MOSDNS_BIN_DIR}"/panel.db*; do
    if [ -f "$f" ]; then
        cp "$f" "${BACKUP_TEMP}/"
    fi
done
# Backup custom direct and local domain rules
for f in "${MOSDNS_BIN_DIR}"/direct-domain.txt "${MOSDNS_BIN_DIR}"/local-domain.txt; do
    if [ -f "$f" ]; then
        cp "$f" "${BACKUP_TEMP}/"
    fi
done

# 4. Fetch Git updates and align branch/tag
echo "Fetching updates from Git repository..."
git fetch --all --tags > /dev/null 2>&1 || true

if [ "${CHANNEL}" = "dev" ]; then
    CURRENT_BRANCH=$(git branch --show-current)
    if [ -n "${CURRENT_BRANCH}" ]; then
        echo "Updating current development branch: ${CURRENT_BRANCH}..."
        git reset --hard "origin/${CURRENT_BRANCH}"
    else
        # Detached HEAD scenario: discover target branch (develop -> dev -> default branch)
        if git show-ref --verify --quiet refs/remotes/origin/develop; then
            TARGET_BRANCH="develop"
        elif git show-ref --verify --quiet refs/remotes/origin/dev; then
            TARGET_BRANCH="dev"
        else
            TARGET_BRANCH=$(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5)
            TARGET_BRANCH=${TARGET_BRANCH:-main}
        fi
        echo "Switching to Dev target branch: ${TARGET_BRANCH}..."
        git checkout -f "${TARGET_BRANCH}" > /dev/null 2>&1
        git reset --hard "origin/${TARGET_BRANCH}"
    fi
else
    # Release channel: Checkout latest git tag
    LATEST_TAG=$(git describe --tags $(git rev-list --tags --max-count=1) 2>/dev/null || echo "latest")
    echo "Switching to Release tag: ${LATEST_TAG}..."
    git checkout -f "${LATEST_TAG}" > /dev/null 2>&1
    git reset --hard "${LATEST_TAG}"
fi

# 5. Restore Backup Configurations
echo "Restoring configurations, databases, and rules..."
if [ -f "${BACKUP_TEMP}/config-v5.yaml" ]; then
    cp -f "${BACKUP_TEMP}/config-v5.yaml" "${MOSDNS_DIR}/"
fi
if [ -d "${BACKUP_TEMP}" ]; then
    cp -f "${BACKUP_TEMP}"/panel.db* "${MOSDNS_BIN_DIR}/" 2>/dev/null || true
    cp -f "${BACKUP_TEMP}"/*.txt "${MOSDNS_BIN_DIR}/" 2>/dev/null || true
fi
rm -rf "${BACKUP_TEMP}"

# 6. Update Web Control Panel
PANEL_UPDATED=false
DEPLOY_PANEL_SUCCESS=false

if [ "${CHANNEL}" = "dev" ]; then
    # Dev channel: always build locally from the latest source code
    echo "Compiling Web Control Panel locally from latest source code..."
    if [ -d "${MOSDNS_DIR}/panel" ]; then
        cd "${MOSDNS_DIR}/panel"
        go mod tidy > /dev/null 2>&1 || true
        if [ -f "${MOSDNS_BIN_DIR}/mosdns-panel" ]; then
            cp "${MOSDNS_BIN_DIR}/mosdns-panel" "${BACKUP_DIR}/mosdns-panel"
        fi
        COMMIT_ID=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        if CGO_ENABLED=1 go build -ldflags "-s -w -X main.panelVersion=dev-${COMMIT_ID}" -o "${MOSDNS_BIN_DIR}/mosdns-panel"; then
            echo "Web Control Panel compiled successfully from source."
            chmod 755 "${MOSDNS_BIN_DIR}/mosdns-panel"
            DEPLOY_PANEL_SUCCESS=true
            PANEL_UPDATED=true
        else
            echo "Error: Local compilation failed." >&2
            exit 1
        fi
    else
        echo "Error: Web Control Panel source code not found." >&2
        exit 1
    fi
else
    # Release channel: download precompiled release binary corresponding to LATEST_TAG
    LATEST_TAG=$(git describe --tags $(git rev-list --tags --max-count=1) 2>/dev/null || echo "latest")
    PANEL_URL="https://github.com/allanchen2019/mosdns-debian-install/releases/download/${LATEST_TAG}/mosdns-panel-linux-${arch_suffix}"
    echo "Downloading precompiled Web Control Panel from ${PANEL_URL}..."
    if wget --timeout=15 --tries=2 -qO "${TEMP_DIR}/mosdns-panel" "${PANEL_URL}"; then
        chmod +x "${TEMP_DIR}/mosdns-panel"
        if "${TEMP_DIR}/mosdns-panel" -h 2>&1 | grep -q "port"; then
            echo "Precompiled control panel verified successfully."
            if [ -f "${MOSDNS_BIN_DIR}/mosdns-panel" ]; then
                cp "${MOSDNS_BIN_DIR}/mosdns-panel" "${BACKUP_DIR}/mosdns-panel"
            fi
            mv -f "${TEMP_DIR}/mosdns-panel" "${MOSDNS_BIN_DIR}/mosdns-panel"
            chmod 755 "${MOSDNS_BIN_DIR}/mosdns-panel"
            DEPLOY_PANEL_SUCCESS=true
            PANEL_UPDATED=true
        else
            echo "Warning: Precompiled binary failed sanity check. Falling back to local compilation..." >&2
        fi
    fi

    # Fallback to local compilation if download failed
    if [ "${DEPLOY_PANEL_SUCCESS}" = "false" ]; then
        echo "Compiling Web Control Panel from checked out tag source..."
        if [ -d "${MOSDNS_DIR}/panel" ]; then
            cd "${MOSDNS_DIR}/panel"
            go mod tidy > /dev/null 2>&1 || true
            if [ -f "${MOSDNS_BIN_DIR}/mosdns-panel" ]; then
                cp "${MOSDNS_BIN_DIR}/mosdns-panel" "${BACKUP_DIR}/mosdns-panel"
            fi
            VERSION_VAL="${LATEST_TAG}"
            if [ -z "${VERSION_VAL}" ] || [ "${VERSION_VAL}" = "latest" ]; then
                VERSION_VAL=$(git describe --tags --exact-match 2>/dev/null || echo "")
                if [ -z "${VERSION_VAL}" ]; then
                    COMMIT_ID=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
                    VERSION_VAL="dev-${COMMIT_ID}"
                fi
            fi
            if CGO_ENABLED=1 go build -ldflags "-s -w -X main.panelVersion=${VERSION_VAL}" -o "${MOSDNS_BIN_DIR}/mosdns-panel"; then
                echo "Web Control Panel compiled successfully from source."
                chmod 755 "${MOSDNS_BIN_DIR}/mosdns-panel"
                DEPLOY_PANEL_SUCCESS=true
                PANEL_UPDATED=true
            else
                echo "Error: Local compilation failed." >&2
                exit 1
            fi
        else
            echo "Error: Web Control Panel source code not found." >&2
            exit 1
        fi
    fi
fi

# 7. Update MosDNS Core Binary (download latest release of IrineSistiana/mosdns)
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

# 8. Ensure custom filter lists exist and have default rules
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

# 9. Restart Services and Verify Status
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

# 10. Rollback on Failure
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
echo "MosDNS & Web Control Panel updated successfully via channel: ${CHANNEL}!"
echo "=========================================="
exit 0
