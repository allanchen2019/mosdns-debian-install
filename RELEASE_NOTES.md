# Release v5.1.6

## 版本更新要点 (Release Highlights)

- **跨境加密解析稳定性与 SNI 修复 (Encrypted Upstream Reliability)**:
  - 将 Cloudflare/Google DoT 上游恢复为域名 URL，并通过 `dial_addr` 固定到对应 Anycast IP，修复 IP 直连导致的 TLS SNI/证书不匹配。
  - 新增 Cloudflare/Google DoH 备用通道；跨境解析只在 DoT 与 DoH 之间容灾，绝不回落到国内明文 DNS，降低污染、超时和 YouTube/CDN 间歇卡顿风险。

- **分流缓存隔离 (Path-Isolated Caches)**:
  - 按直连、代理、兜底路径拆分缓存与持久化文件，避免规则变化或错误上游答案跨路径复用。
  - 保留 ECS 关闭策略，避免 RFC 1918 私网地址泄露并维持公网 CDN 正常调度。

- **IoT 与现有路由策略保留 (Routing Compatibility)**:
  - 保留现有国内直连、代理域名、IoT 专用解析及路由器查询路径；Akamai AS20940 等 BGP 直连策略不在 MosDNS 内改写。

- **验证 (Validation)**:
  - 已验证 Gemini、YouTube、国内直连域名与 DNSSEC 故障域名；生产服务重启后缓存加载、DoH 故障切换和海外明文泄露检查均通过。

## Upgrade Notes

- This release updates the MosDNS configuration package; the bundled MosDNS binary remains upstream `v5.3.4`.
- Runtime cache dumps and rollback backups are intentionally not included in Git.

---

# Release v5.1.5

## 版本更新要点 (Release Highlights)

- **RFC 7871 私网 ECS 污染修复与国内 CDN 调度恢复 (Domestic ECS Fix & CDN Recovery)**:
  - 修复了 `ecs_domestic` 插件向公网 DNS 发送局域网 RFC 1918 私网 IP（如 `192.168.x.x`）导致阿里/淘宝等公网 CDN GSLB 智能调度异常的重大隐患。
  - 关闭主动私网 ECS 封装后，公网 CDN GSLB 恢复根据出口公网 IP 精准就近调度，彻底解决淘宝及阿里系核心静态资源（`img.alicdn.com`、`gw.alicdn.com`）因降级至隔离集群（`*.usd.alibabadns.com` / `45.253.17.68`）引发的 3s+ 握手超时与白屏问题。

- **双栈 Anycast 优质对等网段对称补齐 (Dual-Stack Anycast IPv6 Parity)**:
  - 在 `update-geo.sh` 脚本中同步为 `cn_ipv6.txt` 注入 Microsoft (AS8075)、Apple (AS714)、Akamai (AS20940)、Alibaba Cloud SG/US/HK & Taobao Global (AS45102/AS24429)、Tencent Cloud Intl (AS133100) 的 IPv6 Anycast CIDR。
  - 彻底消除 dual-stack 域名在 Happy Eyeballs 并发连接时 IPv4 直连秒开而 IPv6 因判定非 CN-IP 触发丢弃走慢速 DoT 的非对称延迟问题。

- **DoT 兜底容灾策略抗抖动优化 (Resilient Fallback & Standby Prewarming)**:
  - 优化 `config-v5.yaml` 中的 `remote_fallback_strategy`，将超时阈值收敛至 `300ms`，并开启 `always_standby: true`（并行预热备用链路）。
  - 彻底消除跨境 DoT（853 端口）偶发性网络 QoS 抖动导致的 500ms+ 硬等待卡顿。

- **生产环境运行日志降噪与存储寿命保护 (Production Log Level & Flash Protection)**:
  - 将生产环境运行日志级别从 `debug` 调整为 `info`，消除高频 DNS 查询刷盘 I/O 损耗，遏制 SQLite (`panel.db`) 数据库异常暴涨，保护容器磁盘及嵌入式闪存寿命。

- **Lazy Cache 异步周期调优 (Lazy Cache TTL Tuning)**:
  - 将 `lazy_cache_ttl` 从 24 小时收敛至 2 小时 (`7200s`)，降低失效冷门域名的无效后台高频轮询。

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

