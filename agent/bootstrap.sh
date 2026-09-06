#!/bin/sh
# Build a ready VPN config from the shared template.
#
#   VPN_HOST=... VPN_PORT=... VPN_PASSWORD=... sh bootstrap.sh
#
# Required : VPN_HOST, VPN_PORT, VPN_PASSWORD
# Optional : VPN_SNI (www.bing.com), VPN_INSECURE (true),
#            VPN_LISTEN_ADDR (127.0.0.1), VPN_LISTEN_PORT (11080),
#            VPN_PROFILE (agent | karing), VPN_OUT (./vpn-config.json)
set -eu

BASE="https://raw.githubusercontent.com/compas-psy/vpn/claude/vpn-server-karing-config-4hjw9e"

: "${VPN_HOST:?VPN_HOST is required}"
: "${VPN_PORT:?VPN_PORT is required}"
: "${VPN_PASSWORD:?VPN_PASSWORD is required}"

export VPN_HOST VPN_PORT VPN_PASSWORD
export VPN_SNI="${VPN_SNI:-www.bing.com}"
export VPN_INSECURE="${VPN_INSECURE:-true}"
export VPN_LISTEN_ADDR="${VPN_LISTEN_ADDR:-127.0.0.1}"
export VPN_LISTEN_PORT="${VPN_LISTEN_PORT:-11080}"

VPN_PROFILE="${VPN_PROFILE:-agent}"
VPN_OUT="${VPN_OUT:-./vpn-config.json}"

case "$VPN_PROFILE" in
  agent)  URL="$BASE/agent/singbox-agent-proxy.json" ;;
  karing) URL="$BASE/karing/karing-hysteria2-ru-direct.json" ;;
  *) echo "VPN_PROFILE must be 'agent' or 'karing'" >&2; exit 2 ;;
esac

for tool in curl python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required" >&2; exit 1; }
done

TMPL=$(mktemp)
trap 'rm -f "$TMPL"' EXIT
curl -fsSL "$URL" -o "$TMPL"

python3 - "$TMPL" "$VPN_OUT" <<'PY'
import json, os, sys

src, dst = sys.argv[1], sys.argv[2]
host = os.environ["VPN_HOST"]

with open(src, encoding="utf-8") as fh:
    cfg = json.load(fh)

for outbound in cfg.get("outbounds", []):
    if outbound.get("tag") != "proxy":
        continue
    outbound["server"] = host
    outbound["server_port"] = int(os.environ["VPN_PORT"])
    outbound["password"] = os.environ["VPN_PASSWORD"]
    tls = outbound.setdefault("tls", {})
    tls["server_name"] = os.environ["VPN_SNI"]
    tls["insecure"] = os.environ["VPN_INSECURE"].strip().lower() in ("1", "true", "yes")

for inbound in cfg.get("inbounds", []):
    if inbound.get("tag") == "agent-in":
        inbound["listen"] = os.environ["VPN_LISTEN_ADDR"]
        inbound["listen_port"] = int(os.environ["VPN_LISTEN_PORT"])

# the server's own name must resolve outside the tunnel
for rule in cfg.get("dns", {}).get("rules", []):
    if rule.get("domain") == ["__SERVER__"]:
        rule["domain"] = [host]

with open(dst, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY

chmod 600 "$VPN_OUT"
echo "wrote $VPN_OUT (profile: $VPN_PROFILE)"
if [ "$VPN_PROFILE" = "agent" ]; then
  echo "run: sing-box run -c $VPN_OUT"
  echo "use: export ALL_PROXY=socks5h://$VPN_LISTEN_ADDR:$VPN_LISTEN_PORT"
fi
