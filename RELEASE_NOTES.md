# Release v5.1.4

## 版本更新要点 (Release Highlights)

- **APNIC 官方源本地生成 CN IP 列表 (Direct CN IP Generation from APNIC)**:
  - 引入 `bin/get_cn_ip.py`，直接从 APNIC 官方每日统计数据（`delegated-apnic-latest`）动态拉取并生成国内 IPv4 及 IPv6 CIDR 路由段。
  - 彻底摆脱第三方 GitHub 仓库更新延迟与格式依赖，与 RouterOS / 上游路由表策略保持 100% 同源与时效一致性。

- **直连对等 AS 优质 IP 与域名双层加速 (Dual-Layer Premium Peer ASN Acceleration)**:
  - 在 `update-geo.sh` 与 `bin/direct-domain.txt` 中同步扩充境外直连对等优质 Anycast / CDN 网段（涵盖 Microsoft AS8075、Apple AS714、Akamai AS20940、Alibaba Cloud SG/US AS45102、Tencent Cloud Intl AS133100 等）以及常用国内直连域名，实现双层直连保障与低延迟解析。

- **DNS 反向解析防环与私有 IP 墙 (PTR Loop Prevention & Private IP Filtering)**:
  - 优化 `config-v5.yaml` 路由序列：针对网关自身（如 `192.168.4.1`）发起的 `192.168.0.0/16` PTR 反向查询在未命中时直接秒回 `NXDOMAIN` (reject 3)，杜绝 DNS 回源死循环。
  - 入口直接拦截并拒绝非本地私有网段（10.0.0.0/8, 172.16.0.0/12 等）反向解析，降低无意义的上游递归查询。

- **GFWList 官方源 Base64 自动解码与提取 (GFWList Base64 Auto-Decoding)**:
  - 重构 `update-geo.sh` 代理列表拉取模块，支持从 GFWList 官方源获取后自动进行 Base64 解码与精确域名清洗，保障代理域名列表的时效性与准确性。

- **MosDNS 核心服务精确运行时间统计 (MosDNS Service Uptime Monitoring)**:
  - Web 控制面板重构 Uptime 获取机制，通过 `systemctl show mosdns.service --property=ActiveEnterTimestamp` 精确获取并展示 MosDNS 核心守护进程的真实运行时间。

- **忽略规则优化 (Ignore Rule Cleanliness)**:
  - 将 `bin/backup-all/` 纳入 `.gitignore`，防止升级过程中的临时备份文件污染 Git 工作区。

## 一键更新与升级命令 (One-Key Update Commands)

### 1. 已经是 v5.x 的用户（本地更新命令）：
```bash
# 升级至最新 Release 稳定版
bash /opt/mosdns/update-all.sh release

# 升级至最新 Dev 开发版
bash /opt/mosdns/update-all.sh dev
```

### 2. 远程/全新安装一键升级命令：
```bash
# 使用一键菜单进行安装或升级
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/main/AutoSetup.sh)
```

