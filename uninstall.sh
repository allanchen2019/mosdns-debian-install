#!/bin/bash
set -xeuo
clear

mosdns-cn --service stop
mosdns-cn --service uninstall

rm -rf /opt/mosdns-cn
sed -i '/mosdns-cn/d' /etc/crontab
cd ~
systemctl daemon-reload

rm -rf /etc/resolv.conf
cat << EOF >/etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

systemctl enable systemd-resolved.service
systemctl restart systemd-resolved.service

echo "Uninstall complete."
