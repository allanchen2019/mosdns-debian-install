#!/bin/bash
set -xeuo
clear

rm -rf /opt/mosdns-cn
sed -i '/mosdns-cn/d' /etc/crontab

systemctl stop mosdns-cn.service
systemctl disable mosdns-cn.service
rm /etc/systemd/system/mosdns-cn.service
systemctl daemon-reload
systemctl reset-failed

systemctl enable systemd-resolved.service
systemctl restart systemd-resolved.service

echo "Uninstall complete."
