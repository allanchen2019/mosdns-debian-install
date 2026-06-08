[简体中文](./README.md) | English

An automated shell installation script and routing configurations for [mosdns](https://github.com/IrineSistiana/mosdns) v5 on Debian/Ubuntu.

## Architecture Diagram (MosDNS v5 Pipeline)

This project provides a DNS resolution pipeline tailored for homelab environments.

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

## Key Features

1. **Lazy Cache (mem_cache)**:
   * 20,480 capacity cache with TTL extended up to 86,400s.
   * Auto-dumps in-memory cache to disk (`cache.dump`) every 10 minutes to reduce cold-start latency spikes upon service restarts.
2. **LAN Domain Autonomy (local_router_sequence)**:
   * Direct routing for local domains (`*.lan`, `*.local`, `*.homelab`) and private PTR queries to local gateway.
   * Custom Regex `regexp:^[^.]+$` to block single-label hostname leakage to external DNS servers.
3. **China Split-Routing (local_sequence)**:
   * Direct queries for Chinese domains (`china-list.txt`, `apple-cn.txt`) to local public DNS.
4. **DoT Tunnel (remote_sequence)**:
   * DNS-over-TLS queries to public DNS servers.
   * Timeout fallback to local DNS.
5. **Fallback Security (fallback_sequence)**:
   * Routes unclassified domains to local public DNS. If resolved IP is within domestic ranges (`cn_ip`), it is accepted.
   * If the IP falls outside Chinese IP blocks, the response is dropped and verified via DoT.
6. **EDNS Client Subnet (ECS) (ecs_handler)**:
   * **`ecs_domestic`**: Forwards or injects client subnets (`/24` for IPv4, `/48` for IPv6) for domestic domains to aid CDN routing.
   * **`ecs_remote`**: Strips client subnets for external DNS requests for privacy.
7. **Maintenance Scripts**:
   * **`AutoSetup.sh`**: Script to bootstrap the installation.
   * **`install-mosdns.sh`**: Installs mosdns and verifies configuration.
   * **`update-geo.sh`**: Updates domain lists with validation checks.
   * **`update-bin.sh`**: Updates the panel binary.
   * **`uninstall.sh`**: Uninstalls the files and restores previous configurations.

---

## Usage & Commands

### 1-Click Interactive Console Menu (Supports Installation, Updates & Uninstallation)
```bash
bash <(curl -Ls https://raw.githubusercontent.com/allanchen2019/mosdns-debian-install/main/AutoSetup.sh)
```
> Running this command launches the **MosDNS Terminal Interactive Menu**, enabling installation, Geo rule updates, binary upgrades, and uninstallation.
> For low RAM devices (< 256MB), the installer option downloads pre-compiled binaries from GitHub Releases, with a fallback to local Go compilation (`go build`).

### Web Control Panel
After installation, the `mosdns-panel.service` is spawned automatically:
* **Access URL**: `http://<YOUR_SERVER_IP>:8080` (accessible within your local LAN).
* **Key Capabilities**:
  * **Dashboard**: Shows query counts and cache statistics.
  * **Query Audit**: Logs query history to SQLite.
  * **Configuration Editor**: Allows modifying `config-v5.yaml` and lists in the browser.
  * **Game Rules Switches**: Provides toggle switches for gaming domain lists.
  * **Console**: Shows logs and execution output.

### Binary Update
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

### Uninstallation
```bash
/opt/mosdns/uninstall.sh
```

---

## References & Acknowledgments

### References
- [MosDNS v5 Official Documentation](https://irinesistiana.github.io/mosdns/)
- [OSPF over WireGuard routing scheme](https://github.com/allanchen2019/ospf-over-wireguard)

### Acknowledgments
Special thanks to the following open-source projects whose designs and split-routing rules are directly or indirectly referenced in this project:
- **[IrineSistiana/mosdns](https://github.com/IrineSistiana/mosdns)**: The core DNS forwarder engine powering this project.
- **[v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)**: Provides accurate global domain routing list data.
- **[Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat)**: Provides stable automation sources for routing updates.
- **[felixonmars/dnsmasq-china-list](https://github.com/felixonmars/dnsmasq-china-list)**: Provides high-accuracy lists of domestic domains.

## License

This project is licensed under the **[MIT License](file:///opt/mosdns/LICENSE)**.
