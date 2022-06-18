#!/bin/bash
#set -xu
clear
echo "~~~~~~~~~~~~~~~~"
echo "卸载mosdns......"
echo "~~~~~~~~~~~~~~~~"
systemctl stop mosdns.service
systemctl disable mosdns.service
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
echo "卸载完成!"
echo "~~~~~~~~"