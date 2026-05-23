#!/bin/bash
# Description: Automated, verified, isolated update script for MosDNS resource files
# Author: Antigravity
# Date: 2026-05-22

set -euo pipefail

# 1. Anchoring working directory (prevent cron PWD issues)
cd "$(dirname "$0")"

MOSDNS_DIR="/opt/mosdns"
MOSDNS_BIN_DIR="${MOSDNS_DIR}/bin"
BACKUP_DIR="${MOSDNS_BIN_DIR}/backup-geo" # Isolated backup dir to prevent collision with bin backup
TEMP_DIR=$(mktemp -d)

# Cleanup on exit
cleanup() {
    rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

echo "=========================================="
echo "Starting MosDNS resource files update..."
echo "=========================================="

# Define upstream URLs (using Loyalsoldier's trusted repositories)
URL_CHINA_LIST="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/china-list.txt"
URL_APPLE_CN="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/apple-cn.txt"
URL_PROXY_LIST="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/proxy-list.txt"
URL_GAMES_CN="https://raw.githubusercontent.com/v2fly/domain-list-community/master/data/category-games-cn"
URL_GEOIP_CN="https://raw.githubusercontent.com/Loyalsoldier/geoip/release/text/cn.txt"

# 2. Download files to temporary directory with retries and timeout
download_file() {
    local url=$1
    local dest=$2
    echo "Downloading ${url}..."
    if ! wget --timeout=15 --tries=3 -qO "${dest}" "${url}"; then
        echo "Error: Failed to download ${url}" >&2
        return 1
    fi
    return 0
}

if ! download_file "${URL_CHINA_LIST}" "${TEMP_DIR}/china-list.txt" || \
   ! download_file "${URL_APPLE_CN}" "${TEMP_DIR}/apple-cn.txt" || \
   ! download_file "${URL_PROXY_LIST}" "${TEMP_DIR}/proxy-list.txt" || \
   ! download_file "${URL_GAMES_CN}" "${TEMP_DIR}/geosite_category-games@cn.txt.raw" || \
   ! download_file "${URL_GEOIP_CN}" "${TEMP_DIR}/cn.txt"; then
    echo "Fatal: Resource downloading failed. Aborting update." >&2
    exit 1
fi

# 2.5 Clean and format the games list to keep pure standard domain list formats
echo "Processing China games list..."
grep -E -v "^(#|include:)" "${TEMP_DIR}/geosite_category-games@cn.txt.raw" | grep -v "^$" | sed 's/ @.*//' > "${TEMP_DIR}/geosite_category-games@cn.txt" || true

# 3. Process GeoIP list (split CN IP into IPv4 and IPv6)
echo "Processing China IP list..."
grep -v ':' "${TEMP_DIR}/cn.txt" > "${TEMP_DIR}/cn_ipv4.txt" || true
grep ':' "${TEMP_DIR}/cn.txt" > "${TEMP_DIR}/cn_ipv6.txt" || true

# 4. Validate files to prevent empty/corrupted files from breaking MosDNS
validate_file() {
    local file=$1
    local min_lines=$2
    local min_size=$3 # in bytes
    
    if [ ! -f "${file}" ]; then
        echo "Validation failed: ${file} does not exist." >&2
        return 1
    fi
    
    local line_count
    line_count=$(wc -l < "${file}")
    local file_size
    file_size=$(stat -c%s "${file}")
    
    if [ "${line_count}" -lt "${min_lines}" ] || [ "${file_size}" -lt "${min_size}" ]; then
        echo "Validation failed for ${file} (lines: ${line_count}/${min_lines}, size: ${file_size}/${min_size}B)" >&2
        return 1
    fi
    return 0
}

echo "Validating downloaded resource files..."
if ! validate_file "${TEMP_DIR}/china-list.txt" 10000 200000 || \
   ! validate_file "${TEMP_DIR}/apple-cn.txt" 100 2000 || \
   ! validate_file "${TEMP_DIR}/proxy-list.txt" 1000 20000 || \
   ! validate_file "${TEMP_DIR}/geosite_category-games@cn.txt" 10 100 || \
   ! validate_file "${TEMP_DIR}/cn_ipv4.txt" 1000 20000 || \
   ! validate_file "${TEMP_DIR}/cn_ipv6.txt" 100 2000; then
    echo "Fatal: Resource validation failed. Aborting update." >&2
    exit 1
fi

echo "All files validated successfully."

# 5. Prepare backup of current files in isolated backup-geo directory
mkdir -p "${BACKUP_DIR}"
declare -a FILES=("china-list.txt" "apple-cn.txt" "proxy-list.txt" "geosite_category-games@cn.txt" "cn_ipv4.txt" "cn_ipv6.txt")

for file in "${FILES[@]}"; do
    if [ -f "${MOSDNS_BIN_DIR}/${file}" ]; then
        cp "${MOSDNS_BIN_DIR}/${file}" "${BACKUP_DIR}/${file}"
    fi
done

# 6. Atomic deploy (copy verified files to production directory)
echo "Deploying new resource files..."
for file in "${FILES[@]}"; do
    cp "${TEMP_DIR}/${file}" "${MOSDNS_BIN_DIR}/${file}"
done

# Set permissions
chmod 644 "${MOSDNS_BIN_DIR}"/*.txt

# 7. Restart service and verify runtime status
if [ -f "/etc/systemd/system/mosdns.service" ] || systemctl list-unit-files mosdns.service >/dev/null 2>&1; then
    echo "Restarting mosdns service..."
    if systemctl restart mosdns.service; then
        sleep 2
        if systemctl is-active --quiet mosdns.service; then
            echo "=========================================="
            echo "MosDNS resource files updated successfully!"
            echo "=========================================="
            # Clean up backups on success
            rm -rf "${BACKUP_DIR}"
            exit 0
        fi
    fi

    # 8. Rollback if service fails to start
    echo "==========================================" >&2
    echo "WARNING: MosDNS failed to start with new files! Rolling back..." >&2
    echo "==========================================" >&2

    for file in "${FILES[@]}"; do
        if [ -f "${BACKUP_DIR}/${file}" ]; then
            cp "${BACKUP_DIR}/${file}" "${MOSDNS_BIN_DIR}/${file}"
        else
            rm -f "${MOSDNS_BIN_DIR}/${file}"
        fi
    done

    systemctl restart mosdns.service || true
    echo "Rollback completed. MosDNS restored to previous working state." >&2
    rm -rf "${BACKUP_DIR}"
    exit 1
else
    echo "=========================================="
    echo "MosDNS resource files deployed successfully (service not yet registered)."
    echo "=========================================="
    rm -rf "${BACKUP_DIR}"
    exit 0
fi
