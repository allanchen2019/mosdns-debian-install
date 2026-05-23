English | [简体中文](./README_zh-CN.md)

An automated shell installation script and production-grade routing configurations for [mosdns](https://github.com/IrineSistiana/mosdns) v5 on Debian/Ubuntu.

## 🚀 Architecture Diagram (MosDNS v5 Pipeline)

This project delivers a highly-optimized, low-latency, anti-pollution, and self-healing DNS resolution pipeline tailored for homelab environments.

```text
                     +-----------------------+
                     |   Client DNS Query    |
                     +-----------+-----------+
                                 |
                                 v
                     +-----------------------+
                     |   mem_cache Check     | <--- [Lazy Cache (persistent dump.cache)]
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

---

## ✨ Key Features

1. **⚡️ Low-Latency Lazy Cache (mem_cache)**:
   * 20,480 capacity cache with TTL extended up to 86,400s.
   * Auto-dumps in-memory cache to disk (`cache.dump`) every 10 minutes to eliminate cold-start latency spikes upon container restarts.
2. **🏠 LAN Domain Autonomy (local_router_sequence)**:
   * Direct routing for local domains (`*.lan`, `*.local`, `*.homelab`) and private PTR queries to local gateway (`192.168.4.1`).
   * Custom Regex `regexp:^[^.]+$` to block single-label hostname leakage to external DoT servers.
3. **🇨🇳 High-Performance China Split-Routing (local_sequence)**:
   * Direct concurrently resolved queries for verified Chinese domains (`china-list.txt`, `apple-cn.txt`) to top local public DNS (AliDNS & DNSPod).
4. **🔒 Secure Anti-Pollution DoT Tunnel (remote_sequence)**:
   * Encrypted DNS-over-TLS query concurrent transmission to Google (`8.8.8.8:853`) and Cloudflare (`1.1.1.1:853`).
   * Built-in 500ms timeout threshold resilient failover to domestic public DNS.
5. **🛡️ Dual-Validation Fallback Security (fallback_sequence)**:
   * First routes unclassified domains to local public DNS. If resolved IP is within domestic ranges (`cn_ip`), it is immediately accepted.
   * If the IP falls outside Chinese IP blocks (indicative of regular or polluted results), the response is dropped, and a mandatory secure DoT query is triggered to prevent DNS spoofing.
6. **🌐 Intelligent EDNS Client Subnet (ECS) Optimization (ecs_handler)**:
   * **`ecs_domestic`**: Automatically forwards or injects client subnets (`/24` for IPv4, `/48` for IPv6) for domestic domains to ensure precise regional CDN routing.
   * **`ecs_remote`**: Statically strips client subnets for foreign DNS requests to guarantee privacy and prevent foreign CDN servers from misrouting traffic cross-ocean.
7. **🚀 Production-Grade Self-Healing Maintenance Scripts**:
   * **`AutoSetup.sh`**: Lightweight, idempotent, fast bootstrap script free from bloated dependencies (no Python/PIP overhead) and guards against pre-existing repository conflicts.
   * **`install-mosdns.sh`**: High-availability installer that dynamically injects public resolvers temporarily to avoid offline DNS download deadlocks, and performs localhost port 53 validation queries before switching traffic.
   * **`update-geo.sh`**: Atomic resource dataset updates featuring size-and-line validation limits (10,000+ lines / 200KB+ threshold) to completely block corrupted/empty upstream assets. Uses decoupled (`backup-geo`) path protection.
   * **`update-bin.sh`**: Atomic executable binary updater with robust fallback CPU architecture detection (`uname -m` compatibility) and decoupled (`backup-bin`) backup protection to completely avoid concurrent rollback collisions.
   * **`uninstall.sh`**: Safe uninstaller that performs in-memory system DNS recovery and systemd-resolved stub resolve symlink reconstruction *first* before purging files to eliminate self-destruction failures.

---

## 🛠️ Usage & Commands

### 1-Click Interactive Console Menu (Supports Installation, Updates & Uninstallation)
```bash
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/main/AutoSetup.sh)
```
> [!TIP]
> Running this command directly launches the **MosDNS Terminal Interactive Menu**, enabling 1-click installation, Geo rule updates, binary hot-upgrades, and uninstallation.
> For ultra-low RAM devices (< 256MB), the installer option automatically downloads pre-compiled binaries from GitHub Releases to prevent OOM errors, with a fallback to local Go compilation (`go build`) as backup.

### 🖥️ Premium Glassmorphic Web Control Panel
After installation, a lightweight daemon `mosdns-panel.service` is spawned automatically:
* **Access URL**: `http://<YOUR_SERVER_IP>:8080` (accessible within your local LAN, featuring a dark-mode glassmorphic interface).
* **Key Capabilities**:
  * **Real-time Dashboard**: Dynamic Canvas charts mapping 24H queries alongside Prometheus cache size & high-precision hit rate scraping.
  * **Structured Query Audit**: Live stream query logs (Client IP, Domain, QType, Cache/Upstream status, Duration) persistent to SQLite.
  * **Configuration Editor**: Safely modify and syntax check your `config-v5.yaml` and blocklists directly in the browser. Domain lists are organized into **"Local/Direct"** and **"Remote/Proxy"** tabs, marked with read-only (🔒) and custom (✏️) tags, allowing one-click custom list creation pre-populated with format guidelines and example templates.
  * **Fine-Grained Game Rules Switches**: Game domains are compiled from the official V2Fly `domain-list-community` raw archive into 12 distinct lists (e.g., Steam, Nintendo, PlayStation, Epic Games, Blizzard, EA, Riot, Roblox, Tencent, Mihoyo, Bilibili, and other miscellaneous games). Each list features an independent, iOS-style **"Enable/Disable"** switch to comment/uncomment them in `config-v5.yaml` for flexible direct/proxy routing.
  * **Live Console**: Real-time Systemd logs stream and one-click execution of updates.

### Self-Healing Binary Update
```bash
/opt/mosdns/update-bin.sh
```

### Resource Dataset Update
```bash
/opt/mosdns/update-geo.sh
```

### Service Controls & Logging
```bash
# Check MosDNS Core status
systemctl status mosdns.service

# Check Web Panel status
systemctl status mosdns-panel.service

# View weekly update timers
systemctl status mosdns-update.timer
```

### Uninstallation (cleanly sweeps all files and panel service daemons)
```bash
/opt/mosdns/uninstall.sh
```

---

## 📄 License
This project is open-source. For more info, please see the source scripts.
