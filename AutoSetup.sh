#!/bin/bash

echo "下载依赖……"
apt update
apt install wget git unzip -y
echo "克隆存储库……"
git clone https://github.com/allanchen2019/mosdns-cn-debian-install.git /opt/mosdns-cn
chmod 777 -R /opt/mosdns-cn
echo "运行安装脚本……"
bash /opt/mosdns-cn/install-mosdns.sh
rm -rf ./AutoSetup.sh

systemctl status mosdns-cn.service
