#!/usr/bin/env bash
# Install one VLESS + Reality + Vision inbound for v2rayN.
# Supported systems: Debian / Ubuntu with systemd.
# Usage: SERVER_IP=203.0.113.10 bash vless-reality-v2rayn.sh
set -Eeuo pipefail

readonly SERVICE_NAME="vless-reality"
readonly CONFIG_DIR="/etc/${SERVICE_NAME}"
readonly CONFIG_FILE="${CONFIG_DIR}/config.json"
readonly LISTEN_PORT="443"
readonly SNI="www.cloudflare.com"

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

[[ ${EUID:-999} -eq 0 ]] || die "Run this script as root."
[[ -r /etc/os-release ]] || die "Cannot identify the operating system."
. /etc/os-release
[[ ${ID:-} == "debian" || ${ID:-} == "ubuntu" ]] || die "Only Debian and Ubuntu are supported."
command -v systemctl >/dev/null || die "systemd is required."

SERVER_IP=${SERVER_IP:-}
[[ $SERVER_IP =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || \
  die "Set your public IPv4 first, for example: SERVER_IP=77.73.8.41 bash $0"

if ss -ltn '( sport = :443 )' | grep -q LISTEN; then
  die "TCP 443 is already in use. Do not stop the existing service blindly; choose a free port or inspect it with: ss -ltnp '( sport = :443 )'"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gpg openssl

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
chmod a+r /etc/apt/keyrings/sagernet.asc
cat >/etc/apt/sources.list.d/sagernet.sources <<'EOF'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
EOF
apt-get update
apt-get install -y sing-box

SING_BOX_BIN=$(command -v sing-box)
[[ -x $SING_BOX_BIN ]] || die "The official sing-box package did not install correctly."

KEYPAIR=$($SING_BOX_BIN generate reality-keypair)
PRIVATE_KEY=$(awk '/PrivateKey:/ {print $2}' <<<"$KEYPAIR")
PUBLIC_KEY=$(awk '/PublicKey:/ {print $2}' <<<"$KEYPAIR")
UUID=$(cat /proc/sys/kernel/random/uuid)
SHORT_ID=$(openssl rand -hex 8)

install -d -m 0700 "$CONFIG_DIR"
cat >"$CONFIG_FILE" <<EOF
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "::",
      "listen_port": ${LISTEN_PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${SNI}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [
    {"type": "direct", "tag": "direct"}
  ]
}
EOF
chmod 600 "$CONFIG_FILE"

"$SING_BOX_BIN" check -c "$CONFIG_FILE"

cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=VLESS Reality service for v2rayN
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${SING_BOX_BIN} run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
PrivateTmp=yes
ProtectHome=yes
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
  ufw allow ${LISTEN_PORT}/tcp
fi

sleep 1
systemctl --no-pager --full status "$SERVICE_NAME"

LINK="vless://${UUID}@${SERVER_IP}:${LISTEN_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#VLESS-Reality"
install -m 0600 /dev/null "${CONFIG_DIR}/v2rayn-link.txt"
printf '%s\n' "$LINK" >"${CONFIG_DIR}/v2rayn-link.txt"

printf '\nV2RayN node link (also saved in %s):\n%s\n' "${CONFIG_DIR}/v2rayn-link.txt" "$LINK"
printf '\nIf the provider has a cloud firewall, allow TCP %s. Test from Windows:\n' "$LISTEN_PORT"
printf 'Test-NetConnection %s -Port %s\n' "$SERVER_IP" "$LISTEN_PORT"

