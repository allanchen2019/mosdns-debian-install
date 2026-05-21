[English](./README.md) | 简体中文

一个在Debian（或衍生版）上安装[mosdns](https://github.com/IrineSistiana/mosdns)的shell脚本。

2023-3-19更新：兼容V5，要安装之前的就砍掉重练吧。


# 重要！先决条件：需要事先为DNS服务器做好IP分流。

有关更多详细信息，请参阅[此仓库](https://github.com/allanchen2019/ospf-over-wireguard)。

### 独立安装 (amd64 & arm64):
```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/v5/AutoSetup.sh)
```

### 可选：每天7:00自动更新各种列表，`crontab -e` 后添加：

```
0 7 * * * bash /opt/mosdns/update-geo.sh  >> /var/log/cron.log 2>&1
```
### 保存退出。

### 更新资源文件:
```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/v5/update-geo.sh)
```

### 只更新可执行二进制:
```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/v5/update-bin.sh)
```
### 卸载:
```
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/v5/uninstall.sh)
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
---

## 🚀 Homelab 核心 DNS 转发架构 (MosDNS v5)

当前 MosDNS v5 已完成了生产级的高级分流、防污染和内网解析自治优化。其解析逻辑流水线（Pipeline）如下图所示：

```text
                     +-----------------------+
                     |   Client DNS Query    |
                     +-----------+-----------+
                                 |
                                 v
                     +-----------------------+
                     |   mem_cache Check     | <--- [乐观缓存 (持久化至 cache.dump)]
                     +-----------+-----------+
                                 |
                  +--------------+--------------+
                  |                             |
            [Cache Hit]                   [Cache Miss]
                  |                             |
                  v                             v
           +--------------+            +-----------------+
           | Return Resp  |            | Match Rule Set? |
           +--------------+            +--------+--------+
                                                |
         +-------------------+------------------+------------------+
         | (A) Local Domain  | (B) China Domain | (C) Proxy Domain | (D) Default Fallback
         |   - *.lan, *.local|   - china-list   |   - proxy-list   |   - Other Domains
         |   - Single Label  |   - apple-cn     |                  |
         |   - Private PTR   |                  |                  |
         v                   v                  v                  v
  +--------------+    +--------------+   +--------------+   +---------------+
  | MikroTik GW  |    | China Public |   |  Secure DoT  |   |  China Public |
  | 192.168.4.1  |    |  119.29.29.29|   | 8.8.8.8:853  |   |    Query      |
  |              |    |   223.5.5.5  |   | 1.1.1.1:853  |   +-------+-------+
  +------+-------+    +------+-------+   +------+-------+           |
         |                   |                  |                   v
         |                   |                  |             [Is Resp IP?]
         |                   |                  |             /           \
         |                   |                  |         [CN IP]        [Foreign IP]
         |                   |                  |          /                   \
         |                   |                  |         v                     v
         |                   |                  |  +-------------+       +--------------+
         |                   |                  |  | Accept IP & |       | Drop Resp &  |
         |                   |                  |  | Return      |       | Query DoT    |
         |                   |                  |  +-------------+       +-------+------+
         |                   |                  |         |                      |
         v                   v                  v         v                      v
  +---------------------------------------------------------------------------------+
  |                            Return Answer to Client                              |
  +---------------------------------------------------------------------------------+
```

### 📋 核心解析规则与设计决策

#### 1. ⚡️ 内存乐观缓存 (mem_cache)
*   **配置**：开启 20,480 容量的 Lazy Cache，TTL 最大延长至 86,400 秒。
*   **持久化**：每 10 分钟自动将内存缓存 Dump 至本地 `/opt/mosdns/bin/cache.dump`。
*   **收益**：服务重启或资源更新后瞬间读取 Dump 缓存文件，消解冷启动导致的内网 DNS 抖动，常用域名解析延迟在微秒级（`0 ms` 级体验）。

#### 2. 🏠 局域网自治分流 (local_router_sequence)
*   **匹配规则**：`local-domain.txt`（包含 `*.lan`, `*.local`, `*.homelab` 域名及私有 IP 段的反向 PTR 解析）。
*   **单 Label 拦截**：采用 `regexp:^[^.]+$` 完美闭环无后缀的局域网主机名解析（如 `pve`, `nas`）。
*   **上游转发**：全量路由给本地网关网卡 `192.168.4.1` (MikroTik Router)。
*   **收益**：消除了内网 DNS 隐私向外网 DoT 泄漏的安全风险，本地域名解析响应时间从 `60ms+` 缩短至 `<10ms`。

#### 3. 🇨🇳 国内直连分流 (local_sequence)
*   **匹配规则**：`china-list.txt`, `apple-cn.txt` 及直连白名单。
*   **上游转发**：阿里公共 DNS（`223.5.5.5`）与腾讯公共 DNS（`119.29.29.29`）并发请求。
*   **收益**：保证国内 CDN 节点完美调度，无解析偏差。

#### 4. 🔒 海外防污染加密通道 (remote_sequence)
*   **匹配规则**：`proxy-list.txt` 域名。
*   **上游转发**：Google DoT (`tls://8.8.8.8:853`) 与 Cloudflare DoT (`tls://1.1.1.1:853`) 并发请求，规避运营商劫持。
*   **自愈兜底**：使用自愈型 `fallback` 策略，以海外安全通道为主，若超时 500ms，无缝平滑降级至国内公共 DNS 保障网络高可用。

#### 5. 🛡️ 双保险兜底拦截 (fallback_sequence)
*   对于未命中规则列表的未知域名，先发起国内 DNS 请求。
*   如果解析返回的 IP **属于国内 IP 段 (`cn_ip`)**，则立刻采信并返回响应；
*   如果解析返回的 IP **不属于国内 IP 段（或被污染成海外 IP）**，则果断丢弃该响应，强制唤醒海外 DoT 加密通道重试，确保 100% 抵御常规 DNS 劫持与污染。

---

## 🛠️ 运维与日志审计

### A. 定时资源更新自愈机制
脚本位于 `/opt/mosdns/update-geo.sh`，采用原子性临时下载与大小校验防空容灾设计，更新失败会自动还原备份，绝不引发 DNS 服务宕机。
*   系统已集成 systemd 定时器守护：`mosdns-update.timer`，每周日凌晨 04:00 自动触发，无需依赖传统 crontab。
*   查看下一次自动更新触发点：
    ```bash
    systemctl status mosdns-update.timer
    ```

### B. 生产级日志与归档审计
*   服务日志输出路径已规范至稳固的物理文件：`/var/log/mosdns/mosdns.log`。
*   已部署 `/etc/logrotate.d/mosdns` 日志轮转，采用 `copytruncate` 模式每日切割，保留 30 天历史数据，彻底解决 LXC 空间撑爆的后顾之忧。
*   实时日志回显审计：
    ```bash
    tail -f /var/log/mosdns/mosdns.log | grep -E '\[router_hit\]|\[remote_hit_resilient\]'
    ```
