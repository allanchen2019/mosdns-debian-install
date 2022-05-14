#!/bin/bash
set -xeuo pipefail
clear
architecture=$(dpkg --print-architecture)

wget --show-progress -t 5 -T 10 -cqO /opt/mosdns-cn/bin/mosdns-cn.zip https://github.com/IrineSistiana/mosdns-cn/releases/latest/download/mosdns-cn-linux-"$architecture".zip
cd /opt/mosdns-cn/bin || exit
unzip -o *.zip

./mosdns-cn --service restart
journalctl -f
