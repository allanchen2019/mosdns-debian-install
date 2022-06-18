#!/bin/bash
#update geofile
set -euo pipefail
clear
cd /opt/mosdns/bin || exit

wget -O accelerated-domains.china.conf https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf
wget -O apple.china.conf https://github.com/felixonmars/dnsmasq-china-list/raw/master/apple.china.conf
#wget -O google.china.conf https://github.com/felixonmars/dnsmasq-china-list/raw/master/google.china.conf
#wget -O chnroutes.txt https://github.com/misakaio/chnroutes2/raw/master/chnroutes.txt
wget -O anti-ad-domains.txt https://raw.githubusercontent.com/privacy-protection-tools/anti-AD/master/anti-ad-domains.txt
sed -r 's/.{8}//' accelerated-domains.china.conf > accelerated-domains.china.conf2
sed -r 's/.{16}$//' accelerated-domains.china.conf2 > accelerated-domains.china.conf.raw.txt
sed -r 's/.{8}//' apple.china.conf > apple.china.conf2
sed -r 's/.{16}$//' apple.china.conf2 > apple.china.conf.raw.txt
#sed -r 's/.{8}//' google.china.conf > google.china.conf2
#sed -r 's/.{16}$//' google.china.conf2 > google.china.conf.raw.txt
python3 merge_cidr.py -s apnic -s ipip > chnroutes.txt
./mosdns -s restart
echo "#### 资源文件更新完成 ####"
