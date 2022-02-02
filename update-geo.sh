#!/bin/bash
#update geofile
cd /opt/mosdns-cn
wget -O /opt/mosdns-cn/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
wget -O /opt/mosdns-cn/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
./mosdns-cn --service restart