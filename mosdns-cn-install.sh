#!/bin/bash

clear
architecture=$(dpkg --print-architecture)

apt install -y unzip
mkdir -p /opt/mosdns-cn
cd /opt/mosdns-cn
curl -fsSLo-  https://github.com/IrineSistiana/mosdns-cn/releases/latest/download/mosdns-cn-linux-"$architecture".zip
curl -fsSLo-  https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
curl -fsSLo-  https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
curl -fsSLo-  https://raw.githubusercontent.com/allanchen2019/mosdns-cn-debian-install/main/my-config.yaml
unzip mosdns-cn-linux-$architecture".zip
./mosdns-cn --service install --config my-config.yaml
./mosdns-cn --service start
systemctl status mosdns-cn.service
