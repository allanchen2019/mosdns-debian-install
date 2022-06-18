#!/bin/bash
set -euo pipefail
clear

/opt/mosdns/bin/mosdns -s stop
/opt/mosdns/bin/mosdns -s uninstall
systemctl daemon-reload
rm -rf /opt/mosdns 

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