#!/bin/bash
# Description: Interactive Installer & Manager Menu for MosDNS
# Author: Antigravity
# Date: 2026-05-23

set -uo pipefail # Avoid set -e so that menu loop doesn't exit on subcommand failures

# 1. Check Root Privilege
if [ "$EUID" -ne 0 ]; then
    echo "Fatal: Please run this script as root." >&2
    exit 1
fi

MOSDNS_DIR="/opt/mosdns"

# 2. Check if we need to clone/update repository first
bootstrap_repo() {
    # If current script path is not under /opt/mosdns, bootstrap/update the repository first
    if [ "${PWD}" != "${MOSDNS_DIR}" ] && [ "${0}" != "${MOSDNS_DIR}/AutoSetup.sh" ] && [ "${0}" != "./AutoSetup.sh" ]; then
        echo "=========================================="
        echo "Initializing MosDNS Pre-requisites..."
        echo "=========================================="
        echo "Installing minimal system dependencies (wget, unzip, git, golang-go, gcc)..."
        apt-get update -y > /dev/null 2>&1 || true
        apt-get install -y wget unzip git golang-go gcc > /dev/null 2>&1

        local backup_conf=false
        local backup_rules=false
        local backup_db=false
        
        if [ -f "${MOSDNS_DIR}/config-v5.yaml" ]; then
            cp "${MOSDNS_DIR}/config-v5.yaml" /tmp/config-v5.yaml.tmp
            backup_conf=true
        fi
        
        # Back up all user-defined rules lists (*.txt files in bin/ except online downloaded ones)
        if [ -d "${MOSDNS_DIR}/bin" ]; then
            rm -rf /tmp/mosdns_user_rules
            mkdir -p /tmp/mosdns_user_rules
            for f in "${MOSDNS_DIR}/bin"/*.txt; do
                [ -e "$f" ] || continue
                local fname=$(basename "$f")
                if [ "$fname" != "china-list.txt" ] && [ "$fname" != "apple-cn.txt" ] && \
                   [ "$fname" != "proxy-list.txt" ] && [ "$fname" != "cn_ipv4.txt" ] && \
                   [ "$fname" != "cn_ipv6.txt" ]; then
                    cp "$f" /tmp/mosdns_user_rules/
                    backup_rules=true
                fi
            done
        fi
        
        if [ -f "${MOSDNS_DIR}/bin/panel.db" ]; then
            cp "${MOSDNS_DIR}/bin/panel.db" /tmp/panel.db.tmp
            backup_db=true
        fi
        if [ -f "${MOSDNS_DIR}/bin/panel.db-wal" ]; then
            cp "${MOSDNS_DIR}/bin/panel.db-wal" /tmp/panel.db-wal.tmp
        fi
        if [ -f "${MOSDNS_DIR}/bin/panel.db-shm" ]; then
            cp "${MOSDNS_DIR}/bin/panel.db-shm" /tmp/panel.db-shm.tmp
        fi

        if [ -d "${MOSDNS_DIR}" ]; then
            echo "Found existing directory at ${MOSDNS_DIR}."
            if [ -d "${MOSDNS_DIR}/.git" ]; then
                echo "Updating local repository via git fetch..."
                cd "${MOSDNS_DIR}"
                git fetch --all > /dev/null 2>&1 || true
                git reset --hard origin/main > /dev/null 2>&1 || true
            else
                echo "Directory exists but is not a git repository. Backing up and re-cloning..."
                mv "${MOSDNS_DIR}" "${MOSDNS_DIR}_bak_$(date +%s)"
                git clone -b main https://github.com/allanchen2019/mosdns-debian-install.git "${MOSDNS_DIR}"
            fi
        else
            echo "Cloning MosDNS deployment repository..."
            git clone -b main https://github.com/allanchen2019/mosdns-debian-install.git "${MOSDNS_DIR}"
        fi
        
        # Restore configuration, custom rules, and DB backups
        if [ "${backup_conf}" = true ]; then
            cp -f /tmp/config-v5.yaml.tmp "${MOSDNS_DIR}/config-v5.yaml"
            rm -f /tmp/config-v5.yaml.tmp
        fi
        if [ "${backup_rules}" = true ]; then
            mkdir -p "${MOSDNS_DIR}/bin"
            cp -f /tmp/mosdns_user_rules/* "${MOSDNS_DIR}/bin/"
            rm -rf /tmp/mosdns_user_rules
        fi
        if [ "${backup_db}" = true ]; then
            mkdir -p "${MOSDNS_DIR}/bin"
            cp -f /tmp/panel.db.tmp "${MOSDNS_DIR}/bin/panel.db"
            rm -f /tmp/panel.db.tmp
            if [ -f /tmp/panel.db-wal.tmp ]; then
                cp -f /tmp/panel.db-wal.tmp "${MOSDNS_DIR}/bin/panel.db-wal"
                rm -f /tmp/panel.db-wal.tmp
            fi
            if [ -f /tmp/panel.db-shm.tmp ]; then
                cp -f /tmp/panel.db-shm.tmp "${MOSDNS_DIR}/bin/panel.db-shm"
                rm -f /tmp/panel.db-shm.tmp
            fi
        fi

        chmod 755 -R "${MOSDNS_DIR}"
        echo "Repository bootstrapped successfully. Executing menu from ${MOSDNS_DIR}..."
        exec bash "${MOSDNS_DIR}/AutoSetup.sh" "$@"
    fi
}

bootstrap_repo

# Menu loop
while true; do
    echo "=================================================="
    echo "         MosDNS v5一键智能控制面板系统           "
    echo "=================================================="
    echo "  [1] 安装/重装 MosDNS 主服务与 Web 控制面板"
    echo "      提示: 自动配置乐观缓存、高可用分流及 8080 面板"
    echo ""
    echo "  [2] 更新 Geoip/Geosite DNS 分流规则数据"
    echo "      提示: 自动下载直连与代理规则，过滤防污染 IP"
    echo ""
    echo "  [3] 热更新/降级 MosDNS 核心主程序"
    echo "      提示: 原子替换主程序二进制，防 Text file busy"
    echo ""
    echo "  [4] 彻底卸载 MosDNS 主服务及控制面板"
    echo "      提示: 彻底清除服务守护进程，还原系统网络 DNS 指向"
    echo ""
    echo "  [5] 退出管理菜单"
    echo "=================================================="
    read -p "请输入选项数字 [1-5]: " choice
    echo "=================================================="

    case "${choice}" in
        1)
            # Detect current environment
            if [ ! -f "${MOSDNS_DIR}/bin/mosdns" ]; then
                echo "检测到系统未安装 MosDNS，正在执行全新安装..."
                if bash "${MOSDNS_DIR}/install-mosdns.sh"; then
                    echo "=========================================="
                    echo "安装完成！Web 面板服务与 DNS 服务已激活。"
                    echo "=========================================="
                else
                    echo "错误：安装脚本返回非零状态。" >&2
                fi
            else
                echo "检测到系统中已安装 MosDNS。"
                echo "--------------------------------------------------"
                echo "  [1] 升级/更新（保留配置与数据，更新二进制及面板）[默认]"
                echo "  [2] 覆盖重装（重新运行安装程序，默认保留配置）"
                echo "  [3] 返回主菜单"
                echo "--------------------------------------------------"
                read -p "请选择操作 [1-3, 默认 1]: " sub_choice
                sub_choice=${sub_choice:-1}
                
                case "${sub_choice}" in
                    1)
                        echo "正在执行无损升级/更新..."
                        if bash "${MOSDNS_DIR}/update-all.sh"; then
                            echo "=========================================="
                            echo "更新完成！二进制主程序及控制面板已成功更新。"
                            echo "=========================================="
                        else
                            echo "错误：更新脚本返回非零状态。" >&2
                        fi
                        ;;
                    2)
                        echo "正在准备覆盖重装..."
                        read -p "是否将配置文件 config-v5.yaml 恢复为默认设置？(y/N, 默认: N): " reset_conf
                        reset_conf=${reset_conf:-n}
                        if [ "${reset_conf}" = "y" ] || [ "${reset_conf}" = "Y" ]; then
                            echo "正在恢复默认配置文件..."
                            if [ -f "${MOSDNS_DIR}/config-v5.yaml" ]; then
                                cp "${MOSDNS_DIR}/config-v5.yaml" "${MOSDNS_DIR}/config-v5.yaml.bak_$(date +%s)"
                            fi
                            git checkout HEAD -- "${MOSDNS_DIR}/config-v5.yaml" || true
                        else
                            echo "保留当前配置文件 config-v5.yaml。"
                        fi
                        
                        read -p "是否清除所有用户自定义的规则列表(如 local-domain.txt 等)？(y/N, 默认: N): " reset_rules
                        reset_rules=${reset_rules:-n}
                        if [ "${reset_rules}" = "y" ] || [ "${reset_rules}" = "Y" ]; then
                            echo "正在清除自定义规则列表..."
                            if [ -f "${MOSDNS_DIR}/bin/local-domain.txt" ]; then
                                cp "${MOSDNS_DIR}/bin/local-domain.txt" "${MOSDNS_DIR}/bin/local-domain.txt.bak_$(date +%s)"
                            fi
                            git checkout HEAD -- "${MOSDNS_DIR}/bin/local-domain.txt" || true
                            
                            # Remove other custom *.txt lists
                            for f in "${MOSDNS_DIR}/bin"/*.txt; do
                                [ -e "$f" ] || continue
                                local fname=$(basename "$f")
                                if [ "$fname" != "china-list.txt" ] && [ "$fname" != "apple-cn.txt" ] && \
                                   [ "$fname" != "proxy-list.txt" ] && [ "$fname" != "cn_ipv4.txt" ] && \
                                   [ "$fname" != "cn_ipv6.txt" ] && [ "$fname" != "local-domain.txt" ]; then
                                    rm -f "$f"
                                fi
                            done
                        else
                            echo "保留所有用户自定义的规则列表。"
                        fi
                        
                        if bash "${MOSDNS_DIR}/install-mosdns.sh"; then
                            echo "=========================================="
                            echo "重装完成！服务已重新激活。"
                            echo "=========================================="
                        else
                            echo "错误：重装脚本返回非零状态。" >&2
                        fi
                        ;;
                    *)
                        echo "已取消操作。"
                        ;;
                esac
            fi
            ;;
        2)
            echo "正在手动执行 Geo 规则更新..."
            if bash "${MOSDNS_DIR}/update-geo.sh"; then
                echo "=========================================="
                echo "更新成功！规则已重载并使能。"
                echo "=========================================="
            else
                echo "错误：更新规则失败。" >&2
            fi
            ;;
        3)
            echo "正在手动执行核心程序升级..."
            if bash "${MOSDNS_DIR}/update-bin.sh"; then
                echo "=========================================="
                echo "程序升级成功，服务已热重载。"
                echo "=========================================="
            else
                echo "错误：程序升级失败。" >&2
            fi
            ;;
        4)
            read -p "确定要彻底卸载 MosDNS 及其 Web 面板吗？此操作不可逆！(y/n): " confirm
            if [ "${confirm}" = "y" ] || [ "${confirm}" = "Y" ]; then
                echo "正在执行一键卸载清理..."
                # Since uninstall.sh deletes the repo, we copy it to /tmp to execute, preventing script truncation crash
                cp "${MOSDNS_DIR}/uninstall.sh" /tmp/mosdns_uninstall.sh
                chmod +x /tmp/mosdns_uninstall.sh
                exec bash /tmp/mosdns_uninstall.sh
            else
                echo "已取消卸载操作。"
            fi
            ;;
        5)
            echo "感谢使用！再见。"
            exit 0
            ;;
        *)
            echo "无效选项，请输入 1 到 5 之间的数字。"
            ;;
    esac
    echo ""
    read -p "按回车键返回主菜单..." temp
    clear
done
