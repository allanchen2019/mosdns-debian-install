#!/bin/bash
#update geofile
set -xeuo pipefail
clear

cd /opt/mosdns-cn/bin || exit
wget -O /opt/mosdns-cn/bin/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
wget -O /opt/mosdns-cn/bin/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
./mosdns-cn --service restart
journalctl -xeu mosdns-cn.service
