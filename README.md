# mosdns-cn-debian-install
A shell script installs [mosdns-cn](https://github.com/IrineSistiana/mosdns-cn) on Debian(or derivatives) Linux.

Edit config.yaml for your taste or just run the script for lazy guy.

### Install standalone (tested on amd64 & arm64):
```
apt install -y wget git
cd /opt
git clone https://ghproxy.com/https://github.com/allanchen2019/mosdns-cn-debian-install.git
mv mosdns-cn-debian-install mosdns-cn
cd mosdns-cn
chmod+ x *.sh
./install.sh
```


### Uninstall:
```
sh /opt/mosdns-cn/uninstall.sh
```


Default configuration use [V2Ray 路由规则文件加强版](https://github.com/Loyalsoldier/v2ray-rules-dat) for split dns resolving and DoH upstream servers.
