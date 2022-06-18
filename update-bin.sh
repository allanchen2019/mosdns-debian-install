#!/bin/bash
set -euo pipefail
clear
architecture=$(dpkg --print-architecture)
cd /opt/mosdns/bin || exit
rm -rf mosdns*
wget --show-progress -t 5 -T 10 -cqO mosdns.zip https://github.com/IrineSistiana/mosdns/releases/latest/download/mosdns-linux-"$architecture".zip
unzip -o *.zip
./mosdns -s restart
echo "#### 程序更新完成 ####"
