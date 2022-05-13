#!/bin/bash
echo "下载依赖……"
apt update
apt install wget git unzip -y
echo "克隆存储库……"
git clone https://github.com/allanchen2019/mosdns-cn-debian-install.git /opt/mosdns-cn
chmod 777 -R /opt/mosdns-cn
echo "运行安装脚本……"
bash /opt/mosdns-cn/install.sh
echo "--------------------"
echo "完成！您已成功安装mosdns-cn！"
echo "若您需要卸载，请使用“bash /opt/mosdns-cn/uninstall.sh”指令。"
echo "--------------------"
rm -rf ./AutoSetup.sh
