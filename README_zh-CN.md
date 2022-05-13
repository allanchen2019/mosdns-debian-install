[English](./README.md) | 简体中文
# mosdns-cn-debian-install
一个在Debian（或衍生版）上安装[mosdns-cn](https://github.com/IrineSistiana/mosdns-cn)的shell脚本。

### 先决条件
需要事先为DNS服务器做好IP分流

有关更多详细信息，请参阅[此仓库](https://github.com/allanchen2019/ospf-over-wireguard)。

### 独立安装（amd64和arm64）：
```
wget https://raw.githubusercontent.com/allanchen2019/mosdns-cn-debian-install/main/AutoSetup.sh && chmod 777 ./setup.sh && sudo ./setup.sh
```


### 卸载：
```
bash /opt/mosdns-cn/uninstall.sh
```
