#!/bin/bash
set -xeuo
clear
architecture=$(dpkg --print-architecture)
cd /opt/mosdns-cn/bin || exit
rm -rf mosdns-cn*
wget --show-progress -t 5 -T 10 -cqO mosdns-cn.zip https://github.com/IrineSistiana/mosdns-cn/releases/latest/download/mosdns-cn-linux-"$architecture".zip
unzip -o *.zip
./mosdns-cn --service restart
echo "#### 程序更新完成 ####"
