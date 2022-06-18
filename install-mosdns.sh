#!/bin/bash
set -euo pipefail
architecture=$(dpkg --print-architecture)

cd /opt/mosdns || exit
mkdir bin
cd bin || exit

wget --show-progress -t 5 -T 10 -cqO mosdns.zip https://github.com/IrineSistiana/mosdns/releases/latest/download/mosdns-linux-"$architecture".zip
wget --show-progress -t 5 -T 10 -cqO accelerated-domains.china.conf https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf
wget --show-progress -t 5 -T 10 -cqO apple.china.conf https://github.com/felixonmars/dnsmasq-china-list/raw/master/apple.china.conf
wget --show-progress -t 5 -T 10 -cqO merge_cidr.py https://gist.github.com/allanchen2019/55e8dc52138d134e6fb03379c7c3f57e/raw/54cd4fd150192f96c89c65a5c434943156c12ac1/merge_cidr.py
wget --show-progress -t 5 -T 10 -cqO anti-ad-domains.txt https://raw.githubusercontent.com/privacy-protection-tools/anti-AD/master/anti-ad-domains.txt
sed -r 's/.{8}//' accelerated-domains.china.conf > accelerated-domains.china.conf2 > /dev/null 2>&1
sed -r 's/.{16}$//' accelerated-domains.china.conf2 > accelerated-domains.china.conf.raw.txt > /dev/null 2>&1
sed -r 's/.{8}//' apple.china.conf > apple.china.conf2 > /dev/null 2>&1
sed -r 's/.{16}$//' apple.china.conf2 > apple.china.conf.raw.txt > /dev/null 2>&1

python3 -m pip install netaddr requests > /dev/null 2>&1
python3 merge_cidr.py -s apnic -s ipip > chnroutes.txt

systemctl stop systemd-resolved.service > /dev/null 2>&1
systemctl disable systemd-resolved.service > /dev/null 2>&1
systemctl daemon-reload > /dev/null 2>&1

unzip -o mosdns.zip > /dev/null 2>&1
./mosdns -s install -c /opt/mosdns/config.yaml
./mosdns -s start
systemctl enable mosdns.service > /dev/null 2>&1


