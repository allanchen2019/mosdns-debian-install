# mosdns-cn-debian-install
A shell script installs [mosdns-cn](https://github.com/IrineSistiana/mosdns-cn) on Debian(or derived) Linux.

Edit my-config.yaml for your taste or just run the script for lazy guy.

### Install (tested on amd64 & arm64):
```
apt install -y wget
bash <(wget --no-check-certificate -qO- https://raw.githubusercontent.com/allanchen2019/mosdns-cn-debian-install/main/mosdns-cn-install.sh)
```
### Uninstall:
```
bash <(wget --no-check-certificate -qO- https://raw.githubusercontent.com/allanchen2019/mosdns-cn-debian-install/main/uninstall.sh)
```


Default configuration use [V2Ray 路由规则文件加强版](https://github.com/Loyalsoldier/v2ray-rules-dat) for split dns resolving and DoH upstream servers.

Click [mosdns-cn](https://github.com/IrineSistiana/mosdns-cn) for more information.
