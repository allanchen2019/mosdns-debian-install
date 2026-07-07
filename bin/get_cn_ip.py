#!/usr/bin/env python3
import urllib.request
import ipaddress
import sys
import re

def fetch_apnic_data(url):
    print(f"Downloading APNIC data from {url}...")
    req = urllib.request.Request(
        url, 
        headers={'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)'}
    )
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=15) as response:
                return response.read().decode('utf-8')
        except Exception as e:
            print(f"Attempt {attempt + 1} failed: {e}")
            if attempt == 2:
                return None

def parse_and_generate(url, out_v4, out_v6):
    content = fetch_apnic_data(url)
    if not content:
        print("Fatal: Failed to retrieve APNIC stats.")
        sys.exit(1)

    print("Parsing APNIC stats for CN allocations...")
    ipv4_list = []
    ipv6_list = []

    for line in content.splitlines():
        if not line or line.startswith('#'):
            continue
        parts = line.split('|')
        if len(parts) >= 7:
            # Format: registry|cc|type|start|value|date|status
            registry, cc, rtype, start, value, date, status = parts[:7]
            if cc == 'CN':
                if rtype == 'ipv4':
                    try:
                        ip_start = start
                        ip_count = int(value)
                        prefix_len = 32 - ip_count.bit_length() + 1
                        network = ipaddress.IPv4Network(f"{ip_start}/{prefix_len}", strict=False)
                        ipv4_list.append(network)
                    except ValueError:
                        continue
                elif rtype == 'ipv6':
                    try:
                        ip_start = start
                        prefix_len = int(value)
                        network = ipaddress.IPv6Network(f"{ip_start}/{prefix_len}", strict=False)
                        ipv6_list.append(network)
                    except ValueError:
                        continue

    print(f"Found {len(ipv4_list)} raw IPv4 ranges and {len(ipv6_list)} raw IPv6 ranges.")

    # Merge subnets to optimize size
    print("Collapsing subnets...")
    collapsed_v4 = list(ipaddress.collapse_addresses(ipv4_list))
    collapsed_v6 = list(ipaddress.collapse_addresses(ipv6_list))

    print(f"Optimized to {len(collapsed_v4)} IPv4 ranges and {len(collapsed_v6)} IPv6 ranges.")

    # Write IPv4
    with open(out_v4, 'w', encoding='utf-8') as f:
        f.write("# China Mainland IPv4 CIDR - APNIC collapsed\n")
        for net in collapsed_v4:
            f.write(f"{net}\n")

    # Write IPv6
    with open(out_v6, 'w', encoding='utf-8') as f:
        f.write("# China Mainland IPv6 CIDR - APNIC collapsed\n")
        for net in collapsed_v6:
            f.write(f"{net}\n")

    print(f"Written output to {out_v4} and {out_v6} successfully.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: get_cn_ip.py <output_ipv4_path> <output_ipv6_path>")
        sys.exit(1)

    apnic_url = "https://ftp.apnic.net/stats/apnic/delegated-apnic-latest"
    parse_and_generate(apnic_url, sys.argv[1], sys.argv[2])
