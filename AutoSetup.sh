#!/bin/bash
set -euo pipefail
clear

echo "下载依赖……"
apt update
apt install wget git unzip pip -y
echo "克隆库……"
git clone https://github.com/allanchen2019/mosdns-debian-install.git /opt/mosdns
chmod 777 -R /opt/mosdns
echo "执行安装……"
bash /opt/mosdns/install-mosdns.sh

if systemctl status mosdns.service |grep -q "running"; then
        echo "安装完成，mosdns已运行！"
    else
        echo "Emm...好像哪里不太对，mosdns没运行..."
fi
rm -rf ./AutoSetup.sh
