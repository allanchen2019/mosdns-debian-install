#!/bin/bash
#update geofile
set -euo pipefail
clear
cd /opt/mosdns/bin || exit

wget -O accelerated-domains.china.conf https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf > /dev/null
wget -O apple.china.conf https://github.com/felixonmars/dnsmasq-china-list/raw/master/apple.china.conf > /dev/null
wget -O anti-ad-domains.txt https://raw.githubusercontent.com/privacy-protection-tools/anti-AD/master/anti-ad-domains.txt > /dev/null
sed -r 's/.{8}//' accelerated-domains.china.conf > accelerated-domains.china.conf2 > /dev/null
sed -r 's/.{16}$//' accelerated-domains.china.conf2 > accelerated-domains.china.conf.raw.txt > /dev/null
sed -r 's/.{8}//' apple.china.conf > apple.china.conf2 > /dev/null
sed -r 's/.{16}$//' apple.china.conf2 > apple.china.conf.raw.txt > /dev/null
python3 merge_cidr.py -s apnic -s ipip > chnroutes.txt 
./mosdns -s restart
echo "~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "#### 资源文件更新完成 ####"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~"