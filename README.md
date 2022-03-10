# mosdns-cn-debian-install
A shell script installs [mosdns-cn](https://github.com/IrineSistiana/mosdns-cn) on Debian(or derivatives) Linux.

### Prerequisite
A proper ip split tunneling for native and remote dns servers is required. 

See https://github.com/allanchen2019/ospf-over-wireguard for more detail.

### Install standalone (amd64 & arm64):
```
apt install -y wget git
cd /opt
git clone https://ghproxy.com/https://github.com/allanchen2019/mosdns-cn-debian-install.git
mv mosdns-cn-debian-install mosdns-cn
cd mosdns-cn
chmod +x *.sh
./install.sh
```


### Uninstall:
```
sh /opt/mosdns-cn/uninstall.sh
```
