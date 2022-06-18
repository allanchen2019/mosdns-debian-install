#!/bin/bash
#update geofile
set -euo pipefail
clear
cd /opt/mosdns/bin || exit

wget -O accelerated-domains.china.conf https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf
wget -O apple.china.conf https://github.com/felixonmars/dnsmasq-china-list/raw/master/apple.china.conf
wget -O anti-ad-domains.txt https://raw.githubusercontent.com/privacy-protection-tools/anti-AD/master/anti-ad-domains.txt
sed -r 's/.{8}//' accelerated-domains.china.conf > accelerated-domains.china.conf2
sed -r 's/.{16}$//' accelerated-domains.china.conf2 > accelerated-domains.china.conf.raw.txt
sed -r 's/.{8}//' apple.china.conf > apple.china.conf2
sed -r 's/.{16}$//' apple.china.conf2 > apple.china.conf.raw.txt
python3 merge_cidr.py -s apnic -s ipip > chnroutes.txt 
./mosdns -s restart
echo "~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "……………资源文件更新完成……………"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~"