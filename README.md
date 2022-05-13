# mosdns-cn-debian-install
A shell script installs [mosdns-cn](https://github.com/IrineSistiana/mosdns-cn) on Debian(or derivatives) Linux.

### Prerequisite
A proper ip split tunneling for native and remote dns servers is required. 

See https://github.com/allanchen2019/ospf-over-wireguard for more detail.

### Install standalone (amd64 & arm64):
```
wget https://gist.githubusercontent.com/CJYKK/56f7bf83518a1ed00d0452787b8c91dd/raw/d447a22a98fa379cc027056e0ab21eb61b356738/setup.sh && chmod 777 ./setup.sh && sudo ./setup.sh
```


### Uninstall:
```
bash /opt/mosdns-cn/uninstall.sh
```
