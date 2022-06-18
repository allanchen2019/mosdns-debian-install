#!/bin/bash
set -euo pipefail
clear

echo "Downloading dependency……"
apt update
apt install wget git unzip pip -y
echo "Cloning repo……"
git clone https://github.com/allanchen2019/mosdns-debian-install.git /opt/mosdns
chmod 777 -R /opt/mosdns
echo "Running……"
bash /opt/mosdns/install-mosdns.sh
#systemctl status mosdns.service
echo "Finished! Run journalctl -f |grep mosdns to see what happend."
rm -rf ./AutoSetup.sh
