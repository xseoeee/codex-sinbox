# VLESS Reality for v2rayN

A minimal Debian/Ubuntu installer for a single VLESS + Reality + Vision inbound using the official sing-box APT repository.

## Install

Run as root. Replace the IP address with the VPS public IPv4:

```bash
SERVER_IP=77.73.8.41 bash <(curl -fsSL https://raw.githubusercontent.com/xseoeee/codex-sinbox/main/vless-reality-v2rayn.sh)
```

The script uses TCP 443 and prints a `vless://` link for direct import into v2rayN. It stops if TCP 443 is already occupied and does not change existing sing-box, Nginx, or Argo services.

## Notes

- Allow TCP 443 in the VPS provider firewall if one is enabled.
- The script supports Debian and Ubuntu with systemd.
- Latency depends on the real network path; no installer can guarantee a target latency.
