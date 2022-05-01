#!/bin/bash
#update geofile
set -xeuo pipefail
clear

cd /opt/mosdns-cn/bin || exit

wget --show-progress -t 5 -T 10 -cqO /opt/mosdns-cn/bin/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
wget --show-progress -t 5 -T 10 -cqO /opt/mosdns-cn/bin/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
wget -O accelerated-domains.china.conf https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf
wget -O chnroutes.txt https://github.com/misakaio/chnroutes2/raw/master/chnroutes.txt
wget -O anti-ad-domains.txt https://raw.githubusercontent.com/privacy-protection-tools/anti-AD/master/anti-ad-domains.txt
sed -r 's/.{8}//' accelerated-domains.china.conf > accelerated-domains.china.conf2
sed -r 's/.{16}$//' accelerated-domains.china.conf2 > accelerated-domains.china.conf.raw.txt

./mosdns-cn --service restart
journalctl -f
