#!/bin/bash
set -euo pipefail
architecture=$(dpkg --print-architecture)

cd /opt/mosdns || exit
mkdir bin
cd bin || exit
echo "下载mosdns和域名表……"
wget --show-progress -t 5 -T 10 -cqO mosdns.zip https://github.com/IrineSistiana/mosdns/releases/latest/download/mosdns-linux-"$architecture".zip
wget --show-progress -t 5 -T 10 -cqO accelerated-domains.china.conf https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf
wget --show-progress -t 5 -T 10 -cqO apple.china.conf https://github.com/felixonmars/dnsmasq-china-list/raw/master/apple.china.conf
sed -r 's/.{8}//' accelerated-domains.china.conf > accelerated-domains.china.conf2
sed -r 's/.{16}$//' accelerated-domains.china.conf2 > accelerated-domains.china.conf.raw.txt
sed -r 's/.{8}//' apple.china.conf > apple.china.conf2
sed -r 's/.{16}$//' apple.china.conf2 > apple.china.conf.raw.txt

echo "停用systemd-resolved……"
systemctl stop systemd-resolved.service > /dev/null 2>&1
systemctl disable systemd-resolved.service > /dev/null 2>&1
systemctl daemon-reload > /dev/null 2>&1
echo "启动mosdns……"
unzip -o mosdns.zip > /dev/null 2>&1
./mosdns service install -c /opt/mosdns/config-v5.yaml > /dev/null 2>&1
./mosdns service start > /dev/null 2>&1
systemctl enable mosdns.service


