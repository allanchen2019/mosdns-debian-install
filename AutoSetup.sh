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
            echo "正在启动 MosDNS 一键安装器..."
            if bash "${MOSDNS_DIR}/install-mosdns.sh"; then
                echo "=========================================="
                echo "安装完成！Web 面板服务与 DNS 服务已激活。"
                echo "=========================================="
            else
                echo "错误：安装脚本返回非零状态。" >&2
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
