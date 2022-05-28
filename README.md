English | [简体中文](./README_zh-CN.md)
# mosdns-cn-debian-install


### Prerequisite
Proper split tunneling for China and non-China IPs are required. 

See https://github.com/allanchen2019/ospf-over-wireguard for more detail.

### Install standalone (amd64 & arm64):
```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-cn-debian-install/main/AutoSetup.sh)
```


### Uninstall:
```
bash /opt/mosdns-cn/uninstall.sh
```
