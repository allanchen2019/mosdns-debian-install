#!/bin/bash
set -xeuo pipefail
clear

cd /opt/mosdns-cn/bin || exit

./mosdns-cn --service stop
./mosdns-cn --service uninstall

rm -rf /opt/mosdns-cn
sed -i '/mosdns-cn/d' /etc/crontab
systemctl daemon-reload

rm -rf /etc/resolv.conf
cat << EOF >/etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

systemctl enable systemd-resolved.service
systemctl restart systemd-resolved.service
cd ~
echo "#### 卸载完成 ####"
