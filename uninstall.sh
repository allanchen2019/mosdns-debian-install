#!/bin/bash

clear
cd /opt/mosdns-cn/bin
./mosdns-cn --service stop
./mosdns-cn --service uninstall
rm -rf /opt/mosdns-cn
sed -i '/mosdns-cn/d' /etc/crontab
