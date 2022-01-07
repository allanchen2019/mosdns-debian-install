### mosdns-cn-debian-install ###
A shell script installs mosdns-cn on Debian(or derived) Linux.

Choose script for arm64 or x86_64 accrodingly.

For x86_64(x86 VM):
```
apt install -y wget
bash <(wget --no-check-certificate -qO- https://raw.githubusercontent.com/allanchen2019/mosdns-cn-debian-install/main/mosdns-cn-install-amd64.sh)
```

For arm64(TVbox\r2s\N1\raspberry pi,etc ):
```
apt install -y wget
bash <(wget --no-check-certificate -qO- https://raw.githubusercontent.com/allanchen2019/mosdns-cn-debian-install/main/mosdns-cn-install-arm64.sh)
```
