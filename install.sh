#!/bin/bash

clear
architecture=$(dpkg --print-architecture)

apt install -y unzip git
#mkdir -p /opt/mosdns-cn
cd /opt
git clone https://ghproxy.com/https://github.com/allanchen2019/mosdns-cn-debian-install.git
mv mosdns-cn-debian-install mosdns-cn
cd mosdns-cn
chmod +x *.sh
mkdir -p bin
cd bin

wget --show-progress -t 5 -T 10 -cqO /opt/mosdns-cn/bin/mosdns-cn.zip https://ghproxy.com/https://github.com/IrineSistiana/mosdns-cn/releases/latest/download/mosdns-cn-linux-"$architecture".zip
wget --show-progress -t 5 -T 10 -cqO /opt/mosdns-cn/bin/geoip.dat https://ghproxy.com/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
wget --show-progress -t 5 -T 10 -cqO /opt/mosdns-cn/bin/geosite.dat https://ghproxy.com/https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat

unzip -o mosdns-cn.zip
#cd mosdns-cn
./mosdns-cn --service install --config ./..config.yaml
./mosdns-cn --service start
systemctl status mosdns-cn.service

/bin/bash -c 'echo "0 12 * * * root /opt/mosdns-cn/update-geo.sh" >> /etc/crontab'
