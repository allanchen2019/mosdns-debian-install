[English](./README_EN.md) | 简体中文

在 Debian（或其衍生版）上安装 [mosdns](https://github.com/IrineSistiana/mosdns) 的 shell 脚本与分流配置。

# 重要！先决条件：需要事先为 DNS 服务器做好 IP 分流。

有关更多详细信息，请参阅[此仓库](https://github.com/allanchen2019/ospf-over-wireguard)。

### 一键交互菜单 (支持安装、升级与卸载):
```bash
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/main/AutoSetup.sh)
```
> 运行此命令将启动 **MosDNS 终端交互菜单**，支持安装、更新 Geo 规则、升级主程序、卸载等。
> 针对低内存环境，安装选项会从 GitHub Releases 下载预编译的二进制文件，若下载失败则自动降级为本地源码编译（`go build`）。

### MosDNS Web 控制面板:
安装完成后，系统会运行 `mosdns-panel.service` 守护进程：
* **面板访问地址**：`http://<您的服务器IP>:8080` (支持内网访问)
* **核心功能**：
  * **仪表盘**：展示解析流量趋势、乐观缓存命中指标、系统资源占用（CPU/内存）、系统服务运行日志、运行时长、动态版本标签，以及 **24H 热门客户端 Top 10** 实时统计列表。
  * **解析日志审计**：支持 **无限滚动连续加载（无需翻页）**，可通过点击客户端 IP 链接实现一键过滤检索，并支持带过滤条件的 UTF-8 BOM CSV 日志文件导出。
  * **在线编辑器**：修改并检查 `config-v5.yaml` 及规则列表。内置预检引擎（沙箱运行及端口过滤）与缺失引用规则文件拦截预警，将配置与规则区分为只读列表与自定义可编辑列表。
  * **游戏分流开关**：支持细粒度的游戏规则列表（如 Steam, Nintendo, PlayStation, Epic Games, Blizzard, EA, Riot, Roblox, Tencent, Mihoyo, Bilibili 及其他游戏），并配备独立的启用开关。
  * **自升级与服务控制**：支持一键重启、启动或停止 DNS 守护进程。运维卡片支持一键面板升级、SQLite 数据库备份，可在网页端直接切换 **Release 稳定版** 或 **Dev 开发版** 更新通道，并可勾选“自动合并上游修改”选项（使用 `git merge-file` 实现配置与规则的三向智能合并，若发生冲突自动降级退回以防止解析中断）。升级时提供原子级无损备份恢复与页面重连检测。
  * **布局自适应**：精美暗色毛玻璃主题，引入独立滚动容器解决卡片垂直溢出问题，全面优化了窄屏/移动端下的卡片式数据堆叠。

### 定时任务更新 (Systemd Timer):
在安装完成后，系统会自动运行 `mosdns-update.timer` 定时器，默认在每周日凌晨 04:00 自动触发数据更新 (`update-geo.sh`)。

可以使用以下指令管理该定时任务：
```bash
# 查看定时更新任务状态
systemctl status mosdns-update.timer

# 查看定时更新任务的日志
journalctl -u mosdns-update.service -n 50
```

### 本地维护指令:
```bash
# 手动更新至指定通道的最新版（可附带 true/false 参数选择是否合并上游修改，默认 false）
/opt/mosdns/update-all.sh [release|dev] [true|false]

# 手动更新 Geo 规则列表
/opt/mosdns/update-geo.sh

# 优雅卸载 mosdns 及控制面板
/opt/mosdns/uninstall.sh
```

### 若不能正常安装，请先恢复 DNS 配置:
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

## Homelab 核心 DNS 转发架构 (MosDNS v5)

本配置提供了适用于局域网环境 of DNS 解析与分流逻辑。其解析逻辑流水线（Pipeline）如下图所示：

```text
                     +-----------------------+
                     |   Client DNS Query    |
                     +-----------+-----------+
                                 |
                                 v
                     +-----------------------+
                     |   mem_cache Check     | <--- [内存缓存 (持久化至 cache.dump)]
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

### 解析规则与设计

#### 1. 内存缓存 (mem_cache)
*   **配置**：开启 20,480 容量 of Lazy Cache，TTL 最大延长至 86,400 秒。
*   **持久化**：每 10 分钟自动将内存缓存 Dump 至本地 `/opt/mosdns/bin/cache.dump`。
*   **收益**：服务重启或资源更新后读取缓存文件，减少冷启动导致的局域网解析延迟。

#### 2. 局域网解析 (local_router_sequence)
*   **匹配规则**：`local-domain.txt`（包含 `*.lan`, `*.local`, `*.homelab` 域名及私有 IP 段的反向 PTR 解析）。
*   **单 Label 拦截**：采用 `regexp:^[^.]+$` 匹配无后缀的局域网主机名解析（如 `pve`, `nas`）。
*   **上游转发**：路由给本地网关。

#### 3. 优化分流路由 (local_sequence)
*   **匹配规则**：`china-list.txt`, `apple-cn.txt` 及直连白名单。
*   **顺序重排**：匹配时将代理规则集 (`proxy-list.txt`) 置于国内规则之前检查，防止重合规则域名被泄露。
*   **上游转发**：向阿里公共 DNS（`223.5.5.5`）与腾讯公共 DNS（`119.29.29.29`）发起并发请求。

#### 4. 加密通道 (remote_sequence)
*   **匹配规则**：`proxy-list.txt` 域名。
*   **上游转发**：向 Google DoT (`tls://8.8.8.8:853`) 与 Cloudflare DoT (`tls://1.1.1.1:853`) 发起并发请求，规避运营商劫持。
*   **自愈兜底**：使用 fallback 策略，以安全通道为主，若超时 500ms，则降级至国内公共 DNS 保证可用性。

#### 5. 兜底拦截 (fallback_sequence)
*   对于未命中规则列表的未知域名，先发起国内 DNS 请求。
*   如果解析返回的 IP 属于国内 IP 段 (`cn_ip`)，则直接采信并返回响应；
*   如果解析返回的 IP 不属于国内 IP 段，则丢弃该响应，强制通过 DoT 加密通道重试，防范解析污染。

#### 6. EDNS 客户端子网 (ECS) 调度 (ecs_handler)
*   **国内透传与注入 (`ecs_domestic`)**：在向国内 DNS 发起请求前执行。若下游已携带 ECS 则透传；若无则自动注入客户端所在的公网子网，以获取更精确 of CDN 解析调度。
*   **国外隐私去识别化 (`ecs_remote`)**：在流向海外加密通道前执行。清除内网私有网段及拓扑隐私，保护解析的私密性。

#### 7. 动态版本编译标识
*   自动识别 local 编译状态与 GitHub Actions 远程编译 checkout 分支/Tag，自动注入并映射编译标识为 Release 版本号 (如 `v5.1.3`) 或开发版最新 Commit ID (如 `dev-bfe0194`)。

---

## 运维脚本系统

本项目配套的部署与维护脚本提供以下功能：

1. **`AutoSetup.sh` (自动引导脚本)**
   * 移除无关的依赖安装，加快部署速度。
   * 支持二次幂等部署。
2. **`install-mosdns.sh` (热安装器)**
   * **临时接管 DNS**：在安装和卸载期间，临时将系统 DNS 配置为公共 DNS，避免因旧服务停用导致解析死锁。
   * **启动可用性校验**：新服务启动后，先对本地 `127.0.0.1:53` 进行域名解析自检，确认无误后才切换为主 DNS。
   * **直连与局域网自治初始化**：自动检测并初始化 `direct-domain.txt`（默认填入 Taobao、AliCDN 和 `.cn` 的直连路由规则）和 `local-domain.txt`。
3. **`update-all.sh` (自升级与版本切换)**
   * **无损备份升级**：支持 `release` 稳定版及 `dev` 开发版通道。升级前自动对运行配置、SQLite 数据库、域名规则等资产执行临时空间原子化备份并在升级后完美恢复。
   * **防检出阻断**：执行 Git checkout 时增加 `-f` 强制切换标识，彻底避免用户修改配置或本地更新引起的分支冲突问题。
4. **`update-geo.sh` (数据包更新与校验)**
   * 采用原子性临时下载，并内置文件行数与体积限制校验，防止下载到空包或损坏的文件。
   * **并发隔离**：使用独立的备份空间，避免并发更新时临时备份文件被互相覆盖。
5. **`uninstall.sh` (优雅卸载)**
   * 优先重写 DNS 状态并重建 `systemd-resolved` 软链接，最后再清理物理文件夹，避免由于脚本自身被删导致回滚瘫痪。

---

## 运维与日志审计

### A. 定时资源更新
*   系统集成了 systemd 定时器：`mosdns-update.timer`，每周日凌晨 04:00 自动触发，无需依赖 cron。
*   查看自动更新任务状态：
    ```bash
    systemctl status mosdns-update.timer
    ```

### B. 日志与归档审计
*   服务日志输出路径为：`/var/log/mosdns/mosdns.log`
*   已配置 `/etc/logrotate.d/mosdns` 日志轮转，每日切割，保留 30天历史数据。
*   实时日志回显：
    ```bash
    tail -f /var/log/mosdns/mosdns.log | grep -E '\[router_hit\]|\[remote_hit_resilient\]'
    ```

---

## 参考资料与致谢 (References & Acknowledgments)

### 参考资料 (References)
- [MosDNS v5 官方文档](https://irinesistiana.github.io/mosdns/)
- [OSPF over WireGuard 分流方案](https://github.com/allanchen2019/ospf-over-wireguard)

### 致谢项目 (Acknowledgments)
特别感谢以下开源项目，本项目的设计与分流数据直接或间接地引用了它们：
- **[IrineSistiana/mosdns](https://github.com/IrineSistiana/mosdns)**：本项目核心所依赖 of DNS 转发引擎。
- **[v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)**：提供丰富准确的全球域名分流规则数据。
- **[Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat)**：为规则更新脚本提供稳定的自动化路由规则源。
- **[felixonmars/dnsmasq-china-list](https://github.com/felixonmars/dnsmasq-china-list)**：提供国内直连域名的精确数据支持。

## 开源协议 (License)

本项目采用 **[MIT 协议](file:///opt/mosdns/LICENSE)** 开源。
