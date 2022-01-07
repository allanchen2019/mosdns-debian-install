#!/bin/bash

clear
architecture=$(dpkg --print-architecture)

apt install -y unzip
mkdir -p /opt/mosdns-cn
cd /opt/mosdns-cn
wget --show-progress -t 5 -T 10 -cqO /opt/mosdns-cn/mosdns-cn.zip https://github.com/IrineSistiana/mosdns-cn/releases/latest/download/mosdns-cn-linux-"$architecture".zip
wget --show-progress -t 5 -T 10 -cqO /opt/mosdns-cn/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
wget --show-progress -t 5 -T 10 -cqO /opt/mosdns-cn/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
wget --show-progress -t 5 -T 10 -cqO /opt/mosdns-cn/my-config.yaml https://raw.githubusercontent.com/allanchen2019/mosdns-cn-debian-install/main/my-config.yaml
unzip mosdns-cn.zip
./mosdns-cn --service install --config my-config.yaml
./mosdns-cn --service start
systemctl status mosdns-cn.service
