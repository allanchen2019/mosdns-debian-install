[English](./README.md) | 简体中文

一个在Debian（或衍生版）上安装[mosdns](https://github.com/IrineSistiana/mosdns)的shell脚本。

2022-6-28更新：尝试兼容mosdns v4,早期阶段上游更新频繁，不一定追得上（

注意：如更新v4先执行卸载再安装，main分支为mosdns-cn，卸载需用对应脚本:

```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-cn-debian-install/main/uninstall.sh)
```

默认配置为中国大陆域名分流、去广告、中国Apple域名CDN加速，

上游内外DNS采用DoT协议，启用query pipelining连接复用，

本项目依据mosdns演进有频繁小调整，~~非必要不折腾~~。


# 重要！先决条件：需要事先为DNS服务器做好IP分流。

有关更多详细信息，请参阅[此仓库](https://github.com/allanchen2019/ospf-over-wireguard)。

### 独立安装 (amd64 & arm64):
```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/master/AutoSetup.sh)
```

### 可选：每天7:00自动更新各种列表，crontab -e后添加：

```
0 7 * * * bash /opt/mosdns/update-geo.sh  >> /var/log/cron.log 2>&1
```
### 保存退出。

### 更新资源文件:
```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/master/update-geo.sh)
```

### 只更新可执行二进制:
```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/master/update-bin.sh)
```
### 卸载:
```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/master/uninstall.sh)
```

### 如不能正常安装，请先重置DNS:
```
rm -rf /etc/resolv.conf
cat << EOF >/etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
systemctl enable systemd-resolved.service
systemctl restart systemd-resolved.service
cd ~
```