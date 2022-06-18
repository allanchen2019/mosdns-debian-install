#!/bin/bash
set -euo pipefail
clear

cd /opt/mosdns/bin || exit

./mosdns -s stop
./mosdns -s uninstall

rm -rf /opt/mosdns 
sed -i '/mosdns/d' /etc/crontab
systemctl daemon-reload

rm -rf /etc/resolv.conf
cat << EOF >/etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

systemctl enable systemd-resolved.service
systemctl restart systemd-resolved.service
cd ~
echo "~~~~~~~~"
echo "卸载完成"
echo "~~~~~~~~"