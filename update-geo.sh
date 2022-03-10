#!/bin/bash
#update geofile
cd /opt/mosdns-cn/bin
wget -O /opt/mosdns-cn/bin/geoip.dat https://ghproxy.com/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
wget -O /opt/mosdns-cn/bin/geosite.dat https://ghproxy.com/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
./mosdns-cn --service restart
