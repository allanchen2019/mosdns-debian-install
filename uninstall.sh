#!/bin/bash
set -xeuo pipefail
clear
cd /opt/mosdns-cn/bin || exit
./mosdns-cn --service stop
./mosdns-cn --service uninstall
rm -rf /opt/mosdns-cn
sed -i '/mosdns-cn/d' /etc/crontab
echo "Uninstall complete."
