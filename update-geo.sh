#!/bin/bash
# Description: Automated, verified, isolated update script for MosDNS resource files
# Author: Antigravity
# Date: 2026-05-23

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

# Define upstream URLs (using Loyalsoldier's trusted repositories and V2Fly source zip)
URL_CHINA_LIST="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/china-list.txt"
URL_APPLE_CN="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/apple-cn.txt"
URL_PROXY_LIST="https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt"
URL_GEOIP_CN="https://raw.githubusercontent.com/Loyalsoldier/geoip/release/text/cn.txt"
URL_GAMES_ZIP="https://github.com/v2fly/domain-list-community/archive/2fed2eca355a003db3cc4ada1c58c49be876c6a4.zip"

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
   ! download_file "${URL_GEOIP_CN}" "${TEMP_DIR}/cn.txt" || \
   ! download_file "${URL_GAMES_ZIP}" "${TEMP_DIR}/domain-list-community.zip"; then
    echo "Fatal: Resource downloading failed. Aborting update." >&2
    exit 1
fi

# 2.2 Decode and parse GFWList if the URL is from gfwlist
if [[ "${URL_PROXY_LIST}" == *"gfwlist"* ]]; then
    echo "GFWList source detected. Decoding and parsing domains..."
    mv "${TEMP_DIR}/proxy-list.txt" "${TEMP_DIR}/proxy-list-raw.txt"
    python3 -c '
import base64, re, sys
def clean_domain(line):
    line = line.strip()
    if not line or line.startswith(("!", "[")) or line.startswith("@@"):
        return None
    if line.startswith("||"):
        domain = line[2:]
    elif line.startswith("|http://") or line.startswith("|https://"):
        domain = line.split("://", 1)[1]
    elif line.startswith("|"):
        domain = line[1:]
    else:
        domain = line
    for char in ("/", ":", "?", "*"):
        if char in domain:
            domain = domain.split(char)[0]
    domain = domain.strip(".")
    if re.match(r"^[a-zA-Z0-9][-a-zA-Z0-9]{0,62}(\.[a-zA-Z0-9][-a-zA-Z0-9]{0,62})+$", domain):
        return domain
    return None

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        content = f.read().strip()
    missing_padding = len(content) % 4
    if missing_padding:
        content += "=" * (4 - missing_padding)
    decoded = base64.b64decode(content).decode("utf-8")
    domains = set()
    for line in decoded.splitlines():
        dom = clean_domain(line)
        if dom:
            domains.add(dom)
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        for dom in sorted(list(domains)):
            f.write(dom + "\n")
except Exception as e:
    print(f"Error parsing gfwlist: {e}", file=sys.stderr)
    sys.exit(1)
' "${TEMP_DIR}/proxy-list-raw.txt" "${TEMP_DIR}/proxy-list.txt"
fi


# 2.3 Unzip domain-list-community archive
echo "Extracting domain-list-community archive..."
unzip -q -d "${TEMP_DIR}" "${TEMP_DIR}/domain-list-community.zip"
EXTRACTED_DIR=$(find "${TEMP_DIR}" -maxdepth 1 -type d -name "domain-list-community-*" | head -n 1)
if [ -z "${EXTRACTED_DIR}" ] || [ ! -d "${EXTRACTED_DIR}/data" ]; then
    echo "Fatal: Failed to extract domain-list-community." >&2
    exit 1
fi
DATA_DIR="${EXTRACTED_DIR}/data"

# 2.5 Clean and format the games list to keep pure standard domain list formats
echo "Processing and compiling game lists from archive..."

# Declare the recursive include resolver
resolve_include() {
    local file_name=$1
    local file_path="${DATA_DIR}/${file_name}"
    
    if [ ! -f "${file_path}" ]; then
        echo "Warning: file ${file_name} not found in data dir" >&2
        return
    fi
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Trim leading/trailing spaces natively
        line="${line#${line%%[![:space:]]*}}"
        line="${line%${line##*[![:space:]]}}"
        # Ignore comments and empty lines
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            continue
        fi
        
        if [[ "$line" =~ ^include: ]]; then
            local inc_name=${line#include:}
            inc_name=$(echo "$inc_name" | sed 's/ @.*//')
            resolve_include "$inc_name"
        else
            local clean_line=$(echo "$line" | sed 's/ @.*//')
            if [ -n "${clean_line}" ]; then
                echo "${clean_line}"
            fi
        fi
    done < "${file_path}"
}

# Compile the 11 major categories
echo "Compiling major game lists..."
declare -a MAJOR_CATEGORIES=("steam" "nintendo" "playstation" "epicgames" "blizzard" "ea" "riot" "roblox" "tencent-games" "mihoyo-cn" "bilibili-game")

for cat in "${MAJOR_CATEGORIES[@]}"; do
    echo "Compiling geosite_${cat}.txt..."
    resolve_include "${cat}" | sort -u > "${TEMP_DIR}/geosite_${cat}.txt" || true
done

# Compile category-games-other
echo "Compiling category-games-other..."
is_major() {
    local cat=$1
    for major in "${MAJOR_CATEGORIES[@]}"; do
        if [ "${cat}" = "${major}" ]; then
            return 0
        fi
    done
    return 1
}

compile_other() {
    local parent=$1
    local file_path="${DATA_DIR}/${parent}"
    if [ ! -f "${file_path}" ]; then
        return
    fi
    
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#${line%%[![:space:]]*}}"
        line="${line%${line##*[![:space:]]}}"
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            continue
        fi
        
        if [[ "$line" =~ ^include: ]]; then
            local inc_name=${line#include:}
            inc_name=$(echo "$inc_name" | sed 's/ @.*//')
            if ! is_major "${inc_name}"; then
                resolve_include "${inc_name}"
            fi
        else
            local clean_line=$(echo "$line" | sed 's/ @.*//')
            if [ -n "${clean_line}" ]; then
                echo "${clean_line}"
            fi
        fi
    done < "${file_path}"
}

(compile_other "category-games-cn" && compile_other "category-games-!cn") | sort -u > "${TEMP_DIR}/geosite_category-games-other.txt" || true

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
   ! validate_file "${TEMP_DIR}/cn_ipv4.txt" 1000 20000 || \
   ! validate_file "${TEMP_DIR}/cn_ipv6.txt" 100 2000; then
    echo "Fatal: Core resource validation failed. Aborting update." >&2
    exit 1
fi

declare -a GAME_FILES=(
    "geosite_steam.txt"
    "geosite_nintendo.txt"
    "geosite_playstation.txt"
    "geosite_epicgames.txt"
    "geosite_blizzard.txt"
    "geosite_ea.txt"
    "geosite_riot.txt"
    "geosite_roblox.txt"
    "geosite_tencent-games.txt"
    "geosite_mihoyo-cn.txt"
    "geosite_bilibili-game.txt"
    "geosite_category-games-other.txt"
)

for gf in "${GAME_FILES[@]}"; do
    if ! validate_file "${TEMP_DIR}/${gf}" 2 15; then
        echo "Fatal: Game list validation failed for ${gf}. Aborting update." >&2
        exit 1
    fi
done

echo "All files validated successfully."

# 5. Prepare backup of current files in isolated backup-geo directory
mkdir -p "${BACKUP_DIR}"
declare -a FILES=("china-list.txt" "apple-cn.txt" "proxy-list.txt" "cn_ipv4.txt" "cn_ipv6.txt" \
                  "geosite_steam.txt" "geosite_nintendo.txt" "geosite_playstation.txt" \
                  "geosite_epicgames.txt" "geosite_blizzard.txt" "geosite_ea.txt" \
                  "geosite_riot.txt" "geosite_roblox.txt" "geosite_tencent-games.txt" \
                  "geosite_mihoyo-cn.txt" "geosite_bilibili-game.txt" "geosite_category-games-other.txt")

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
