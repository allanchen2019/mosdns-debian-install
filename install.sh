#!/bin/bash
set -xeuo pipefail
clear
architecture=$(dpkg --print-architecture)

apt install -y unzip
cd /opt/mosdns-cn || exit
mkdir bin
cd bin || exit

wget --show-progress -t 5 -T 10 -cqO /opt/mosdns-cn/bin/mosdns-cn.zip https://github.com/IrineSistiana/mosdns-cn/releases/latest/download/mosdns-cn-linux-"$architecture".zip
wget --show-progress -t 5 -T 10 -cqO /opt/mosdns-cn/bin/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
wget --show-progress -t 5 -T 10 -cqO /opt/mosdns-cn/bin/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat

unzip -o mosdns-cn.zip
#cd mosdns-cn
./mosdns-cn --service install --config /opt/mosdns-cn/config.yaml
./mosdns-cn --service start
systemctl status mosdns-cn.service

/bin/bash -c 'echo "0 12 * * * root /opt/mosdns-cn/update-geo.sh" >> /etc/crontab'
