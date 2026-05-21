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
6. **🚀 Production-Grade Self-Healing Maintenance Scripts**:
   * **`AutoSetup.sh`**: Lightweight, idempotent, fast bootstrap script free from bloated dependencies (no Python/PIP overhead) and guards against pre-existing repository conflicts.
   * **`install-mosdns.sh`**: High-availability installer that dynamically injects public resolvers temporarily to avoid offline DNS download deadlocks, and performs localhost port 53 validation queries before switching traffic.
   * **`update-geo.sh`**: Atomic resource dataset updates featuring size-and-line validation limits (10,000+ lines / 200KB+ threshold) to completely block corrupted/empty upstream assets. Uses decoupled (`backup-geo`) path protection.
   * **`update-bin.sh`**: Atomic executable binary updater with robust fallback CPU architecture detection (`uname -m` compatibility) and decoupled (`backup-bin`) backup protection to completely avoid concurrent rollback collisions.
   * **`uninstall.sh`**: Safe uninstaller that performs in-memory system DNS recovery and systemd-resolved stub resolve symlink reconstruction *first* before purging files to eliminate self-destruction failures.

---

## 🛠️ Usage & Commands

### 1-Click Installation
```bash
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/main/AutoSetup.sh)
```

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
# Check status
systemctl status mosdns.service

# View real-time query logging
tail -f /var/log/mosdns/mosdns.log

# Check weekly update timers
systemctl status mosdns-update.timer
```

---

## 📄 License
This project is open-source. For more info, please see the source scripts.
