[English](./README.md) | 简体中文

一个在Debian（或衍生版）上安装[mosdns](https://github.com/IrineSistiana/mosdns)的shell脚本与生产级高可用配置。

2023-3-19更新：兼容V5，要安装之前的就砍掉重练吧。

# 重要！先决条件：需要事先为DNS服务器做好IP分流。

有关更多详细信息，请参阅[此仓库](https://github.com/allanchen2019/ospf-over-wireguard)。

### 一键安装 (amd64 & arm64):
```bash
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/main/AutoSetup.sh)
```
> [!TIP]
> 针对内存小于 256MB 的超低配置环境，安装脚本会自动检测并从 GitHub Releases 接口安全下载已由 CI 预编译好的二进制文件以规避本地编译 OOM，同时会自动降级为本地源码编译（`go build`）作为兜底备份，实现 100% 极速免编译部署。

### 🖥️ MosDNS 毛玻璃 Web 控制面板:
一键部署完成后，系统会自动拉起 `mosdns-panel.service` 控制面板守护进程：
* **面板访问地址**：`http://<您的服务器IP>:8080` (支持内网局域网访问，自动适配暗黑/毛玻璃拟态 UI)
* **核心功能**：
  * **实时仪表盘**：动态绘制 24 小时 DNS 解析波动图和内置的 Prometheus 高精内存缓存命中率、缓存容量状态。
  * **解析日志审计**：流式推送实时解析详情（源 IP、查询域名、QType、缓存/上游命中状态、解析耗时）并持久化写入 SQLite。
  * **在线编辑器**：可视化修改并校验 `config-v5.yaml` 以及域名过滤规则文件。
  * **实时终端控制台**：系统日志滚屏回显与一键脚本运行。

### 自动守护更新 (Systemd Timer 机制):
项目已原生集成了 **Systemd 定时任务守护**，无需手动配置繁琐且容易失效的系统 `crontab`。
在安装完成后，系统会自动注册并启动 `mosdns-update.timer` 定时器，**默认在每周日凌晨 04:00 自动触发数据更新 (`update-geo.sh`) 与热重载自愈自检**。

你只需使用以下指令即可管理和审计定时任务：
```bash
# 查看定时更新任务的下一次触发时间与当前运行状态
systemctl status mosdns-update.timer

# 查看定时更新任务的历史运行日志与执行审计
journalctl -u mosdns-update.service -n 50
```

### 手动更新资源文件:
```bash
/opt/mosdns/update-geo.sh
```

### 手动只更新可执行二进制:
```bash
/opt/mosdns/update-bin.sh
```

### 卸载 (连同 Web 面板服务彻底清理):
```bash
/opt/mosdns/uninstall.sh
```

### 如不能正常安装，请先重置DNS:
```bash
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
*   **配置**：开启 20,480 容量 of Lazy Cache，TTL 最大延长至 86,400 秒。
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

#### 6. 🌐 智能 EDNS 客户端子网 (ECS) 调度优化 (ecs_handler)
*   **国内透传与注入 (`ecs_domestic`)**：在向国内 DNS（`local_sequence`/`fallback_sequence`）发起请求前执行。开启 `forward: true` 和 `send: true`。若下游已携带 ECS（如前端 AdGuard Home）则直接透传；若无则自动注入客户端所在的公网子网（IPv4 `/24`，IPv6 `/48`），保证国内 CDN 节点获取精准的本省本网解析调度，消除解析延迟。
*   **国外隐私去识别化 (`ecs_remote`)**：在流向海外加密通道（`remote_sequence`）前执行。强制设置 `forward: false` 和 `send: false`。在任何情况下彻底剥离内网私有网段及拓扑隐私，捍卫海外域名解析的私密性，并防止国外 CDN 服务商发生跨洋调度错配。

---

## 🛠️ 生产级高可用运维脚本系统

本项目配套的部署与维护脚本经历全方位的工业级重构，确保 100% 的**幂等性、自愈防断网、并发隔离与零下线升级能力**：

1. **`AutoSetup.sh` (极速免冗余引导)**
   * 精简了原本强制安装 PIP 等与 MosDNS 无关的庞大 Python 依赖，极大节省空间并加快部署速度。
   * 引入自适应 Git 更新机制，当 `/opt/mosdns` 存在时自动执行版本拉取对齐，完美支持二次幂等部署。
2. **`install-mosdns.sh` (零离线热安装器)**
   * **防止停用断网死锁**：在安装和卸载旧服务的生存周期中，临时接管系统 `/etc/resolv.conf` 配置为公共 DNS。100% 避免因旧服务停用导致 `wget` 无法解析 GitHub 域名的尴尬死锁。
   * **金丝雀可用性校验**：新服务启动后，先对本地 `127.0.0.1:53` 进行权威域名解析自检，确认完全健康后，才正式将系统解析主服务器切回本地回环地址。
3. **`update-geo.sh` (数据包物理校验更新)**
   * 采用原子性临时下载方案，内置双阈值限制校验（行数必须大于 10,000 行，文件体积必须大于 200KB）。彻底防御因网络超时或运营商劫持下载到空包、乱码直接导致 MosDNS 解析挂死。
   * **并发隔离保护**：独立使用 `backup-geo` 备份空间，避免并发更新时临时备份文件被互相覆盖。
4. **`update-bin.sh` (二进制零死锁热升级)**
   * 升级架构判定引擎（兼容 `uname -m` 兜底），完美适配 Alpine/极简 LXC 等未装 `dpkg` 的精简系统。
   * 使用 `mv` 虚拟文件系统原子替换，彻底绕过 Linux 经典的 `Text file busy` 进程占用报错。
   * 独立使用 `backup-bin` 备份空间，升级失败 2 秒内启动自动回滚自愈机制，绝不离线。
5. **`uninstall.sh` (无下线优雅卸载回滚)**
   * **防自杀崩溃机制**：先在内存中抢先一步完成 DNS 状态重写与 `systemd-resolved` 软链接重建，最后再删除自身物理文件夹，避免由于脚本自身先于恢复指令删除而导致回滚被迫瘫痪的致命漏洞。

---

## ⚙️ 运维与日志审计

### A. 定时资源更新自愈机制
*   系统已集成 systemd 定时器守护：`mosdns-update.timer`，每周日凌晨 04:00 自动触发，无需依赖传统 crontab。
*   查看下一次自动更新触发点：
    ```bash
    systemctl status mosdns-update.timer
    ```

### B. 生产级日志与归档审计
*   服务日志输出路径已规范至稳固的物理文件：`/var/log/mosdns/mosdns.log`
*   已部署 `/etc/logrotate.d/mosdns` 日志轮转，采用 `copytruncate` 模式每日切割，保留 30 天历史数据，彻底解决 LXC 空间撑爆的后顾之忧。
*   实时日志回显审计：
    ```bash
    tail -f /var/log/mosdns/mosdns.log | grep -E '\[router_hit\]|\[remote_hit_resilient\]'
    ```

---

## 📄 License
This project is open-source. For more info, please see the source scripts.
