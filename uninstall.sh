#!/bin/bash
set -xeuo pipefail
clear

systemctl stop mosdns-cn.service
systemctl disable mosdns-cn.service
rm /etc/systemd/system/mosdns-cn.service
systemctl daemon-reload
systemctl reset-failed

rm -rf /opt/mosdns-cn
sed -i '/mosdns-cn/d' /etc/crontab
echo "Uninstall complete."
