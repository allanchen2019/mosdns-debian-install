clear
architecture=$(dpkg --print-architecture)
cd mosdns-cn
wget --show-progress -t 5 -T 10 -cqO /opt/mosdns-cn/mosdns-cn.zip https://github.com/IrineSistiana/mosdns-cn/releases/latest/download/mosdns-cn-linux-"$architecture".zip
unzip mosdns-cn.zip
./mosdns-cn --service restart
journalctl -xeu mosdns-cn.service
