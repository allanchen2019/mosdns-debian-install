### mosdns-cn-debian-install ###
A shell script installs mosdns-cn on Debian(or derived) Linux.

Choose script for arm64 or x86_64 accrodingly.

For arm64(aarch64):

apt install -y wget
bash <(wget --no-check-certificate -qO- https://raw.githubusercontent.com/allanchen2019/mosdns-cn-debian-install/main/mosdns-cn-install-arm64.sh)
