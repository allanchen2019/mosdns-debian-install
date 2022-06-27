#!/bin/bash
set -euo pipefail
architecture=$(dpkg --print-architecture)

cd /opt/mosdns || exit
mkdir bin
cd bin || exit
echo "下载域名表……"
wget --show-progress -t 5 -T 10 -cqO mosdns.zip https://github.com/IrineSistiana/mosdns/releases/latest/download/mosdns-linux-"$architecture".zip
wget --show-progress -t 5 -T 10 -cqO accelerated-domains.china.conf https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf
wget --show-progress -t 5 -T 10 -cqO apple.china.conf https://github.com/felixonmars/dnsmasq-china-list/raw/master/apple.china.conf
wget --show-progress -t 5 -T 10 -cqO merge_cidr.py https://gist.github.com/allanchen2019/55e8dc52138d134e6fb03379c7c3f57e/raw/54cd4fd150192f96c89c65a5c434943156c12ac1/merge_cidr.py
wget --show-progress -t 5 -T 10 -cqO anti-ad-domains.txt https://raw.githubusercontent.com/privacy-protection-tools/anti-AD/master/anti-ad-domains.txt
sed -r 's/.{8}//' accelerated-domains.china.conf > accelerated-domains.china.conf2
sed -r 's/.{16}$//' accelerated-domains.china.conf2 > accelerated-domains.china.conf.raw.txt
sed -r 's/.{8}//' apple.china.conf > apple.china.conf2
sed -r 's/.{16}$//' apple.china.conf2 > apple.china.conf.raw.txt

python3 -m pip install netaddr requests > /dev/null 2>&1
echo "生成cnip……"
python3 merge_cidr.py -s apnic -s ipip > chnroutes.txt
echo "停用systemd-resolved……"
systemctl stop systemd-resolved.service > /dev/null 2>&1
systemctl disable systemd-resolved.service > /dev/null 2>&1
systemctl daemon-reload > /dev/null 2>&1
echo "启动mosdns……"
unzip -o mosdns.zip > /dev/null 2>&1
./mosdns service install -c /opt/mosdns/config-v4.yaml > /dev/null 2>&1
./mosdns service start > /dev/null 2>&1
systemctl enable mosdns.service


