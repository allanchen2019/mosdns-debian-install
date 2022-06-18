#!/bin/bash
set -xeuo pipefail
clear

echo "下载依赖……"
apt update
apt install wget git unzip pip -y
echo "克隆存储库……"
git clone https://github.com/allanchen2019/mosdns-debian-install.git /opt/mosdns
chmod 777 -R /opt/mosdns
echo "运行安装脚本……"
bash /opt/mosdns/install-mosdns.sh
#systemctl status mosdns.service
echo "安装完成，运行journalctl -f |grep mosdns 观察dns查询状态。"
rm -rf ./AutoSetup.sh
