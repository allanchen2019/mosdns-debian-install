English | [简体中文](./README_zh-CN.md)


Default configuration for Mainland China domain split query, anti-ad and Apple domain in China CDN.

2022-6-28 UPDATE: Attempt to adapt mosdns v4.

NOTE：The previous mosdns-cn is in "main" branch.
For update to v4, first uninstall mosdns-cn:

```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-cn-debian-install/main/uninstall.sh)
```



Upstream local and remote DNS uses DoT protocol, query pipelining enabled.

The project has frequent small adjustments based on the evolution of [mosdns](https://github.com/IrineSistiana/mosdns), 

~~Have fun if you are brave enough~~

### Prerequisite
# IMPORTANT ! Require proper split IP tunneling. 

See https://github.com/allanchen2019/ospf-over-wireguard for more detail.

### Install standalone (amd64 & arm64):
```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/master/AutoSetup.sh)
```

### For auto-update resource files, `crontab -e` and add the following line:
```
0 7 * * * bash /opt/mosdns/update-geo.sh  >> /var/log/cron.log 2>&1
```
### Save & Exit.


### Update resource files:
```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/master/update-geo.sh)
```

### Update application binary only:
```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/master/update-bin.sh)
```


### Uninstall:
```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/master/uninstall.sh)
```

### Reset DNS if install failed:
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