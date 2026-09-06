#!/usr/bin/env bash
# Read-only inventory of the VPN server.
#
# The tar archive goes to STDOUT so that one ssh session both builds and
# delivers it - a second session may not see the same /tmp. Everything else
# must go to STDERR; anything printed on stdout corrupts the archive.
set -uo pipefail

OUT=$(mktemp -d /tmp/vpninfo.XXXXXX) || OUT=/tmp/vpninfo.d
rm -rf "${OUT:?}"/* 2>/dev/null
mkdir -p "$OUT/files"

sect() { echo; echo "########## $* ##########"; }

{
  sect uname;            uname -a
  sect os-release;       cat /etc/os-release 2>/dev/null
  sect uptime;           uptime
  sect date;             date -u
  sect id;               id
  sect disk;             df -h 2>/dev/null
  sect listening-ports;  (ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null)
  sect processes;        ps aux 2>/dev/null | head -80
  sect docker-version;   docker --version 2>/dev/null; docker compose version 2>/dev/null
  sect docker-ps;        docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null
  sect docker-images;    docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' 2>/dev/null
  sect systemd-running;  systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null
  sect systemd-enabled;  systemctl list-unit-files --state=enabled --no-pager --no-legend 2>/dev/null
  sect systemd-failed;   systemctl list-units --state=failed --no-pager --no-legend 2>/dev/null
  sect toplevel-dirs;    ls -la / /opt /srv /root /home 2>/dev/null
  sect sizes;            du -sh /opt/* /srv/* /root/* 2>/dev/null | head -60
  sect firewall;         (nft list ruleset 2>/dev/null || iptables-save 2>/dev/null) | head -300
  sect ufw;              ufw status verbose 2>/dev/null
  sect cron;             crontab -l 2>/dev/null; ls -la /etc/cron.d 2>/dev/null
  sect binaries
  for b in hysteria hysteria2 mieru mita sing-box xray v2ray trojan-go naive caddy nginx tar gzip; do
    command -v "$b" >/dev/null 2>&1 && { echo "-- $b -> $(command -v "$b")"; "$b" version 2>&1 | head -5; }
  done
  sect compose-files
  find / -xdev -maxdepth 6 \( -name 'docker-compose*.y*ml' -o -name 'compose.y*ml' \) -not -path '*/node_modules/*' 2>/dev/null | head -50
  sect config-candidates
  find /etc /opt /srv /root /usr/local/etc -xdev -maxdepth 4 \
    \( -iname '*hysteria*' -o -iname '*mieru*' -o -iname '*mita*' -o -iname '*sing-box*' -o -iname '*xray*' -o -iname '*v2ray*' \) 2>/dev/null | head -200
  sect git-repos
  find /opt /srv /root /home -xdev -maxdepth 4 -type d -name .git 2>/dev/null | head -30
} > "$OUT/00-system.txt" 2>&1

# --- per-container detail -------------------------------------------------
if command -v docker >/dev/null 2>&1; then
  docker ps -a --format '{{.Names}}' 2>/dev/null | while IFS= read -r c; do
    [ -n "$c" ] || continue
    safe=$(printf '%s' "$c" | tr -c 'A-Za-z0-9._-' '_')
    docker inspect "$c"         > "$OUT/docker-inspect-$safe.json" 2>&1
    docker logs --tail 400 "$c" > "$OUT/docker-logs-$safe.txt"     2>&1
  done
fi

# --- systemd units of interest -------------------------------------------
if command -v systemctl >/dev/null 2>&1; then
  systemctl list-unit-files --no-pager --no-legend 2>/dev/null \
    | awk '{print $1}' \
    | grep -Ei 'hysteria|mieru|mita|sing-?box|xray|v2ray|trojan|naive|caddy|nginx|vpn|shadow' \
    | head -30 | while IFS= read -r u; do
        safe=$(printf '%s' "$u" | tr -c 'A-Za-z0-9._-' '_')
        { echo "===== systemctl cat $u ====="
          systemctl cat "$u" 2>&1
          echo "===== systemctl status $u ====="
          systemctl status "$u" --no-pager 2>&1 | head -40
          echo "===== journalctl -u $u -n 300 ====="
          journalctl -u "$u" -n 300 --no-pager 2>&1
        } > "$OUT/unit-$safe.txt"
      done
fi

# --- text config files ----------------------------------------------------
collect_dir() {
  d="$1"
  [ -d "$d" ] || return 0
  find "$d" -xdev -type f -size -256k \
    ! -path '*/.git/*' ! -path '*/node_modules/*' ! -path '*/.venv/*' ! -path '*/venv/*' \
    ! -path '*/.cache/*' ! -path '*/.local/*' ! -path '*/.ssh/*' ! -path '*/site-packages/*' \
    ! -name 'id_rsa*' ! -name 'id_ed25519*' ! -name 'id_ecdsa*' ! -name 'authorized_keys' ! -name 'known_hosts' \
    ! -name '*.key' ! -name '*.pem' ! -name '*.crt' ! -name '*.cer' ! -name '*.p12' ! -name '*.pfx' \
    ! -name 'privkey*' ! -name 'fullchain*' ! -name 'shadow' ! -name 'gshadow' \
    ! -name '*.log' ! -name '*.db' ! -name '*.sqlite*' ! -name '*.tar*' ! -name '*.gz' ! -name '*.zip' ! -name '*.pyc' \
    2>/dev/null | head -1500 | while IFS= read -r f; do
      if [ ! -s "$f" ] || grep -Iq . "$f" 2>/dev/null; then
        mkdir -p "$OUT/files$(dirname "$f")" 2>/dev/null
        cp -a "$f" "$OUT/files$f" 2>/dev/null
      fi
    done
}
for d in /opt /srv /root /etc/hysteria /etc/hysteria2 /etc/mieru /etc/mita /etc/sing-box \
         /etc/xray /etc/v2ray /etc/caddy /etc/nginx/conf.d /etc/nginx/sites-enabled \
         /usr/local/etc /etc/systemd/system /etc/letsencrypt/renewal; do
  collect_dir "$d"
done

echo "COLLECT_OK files=$(find "$OUT" -type f | wc -l) dir=$OUT" >&2

if command -v gzip >/dev/null 2>&1; then
  tar czf - -C "$OUT" . 2>/dev/null
else
  echo "COLLECT_NOTE gzip missing, sending an uncompressed tar" >&2
  tar cf - -C "$OUT" . 2>/dev/null
fi

rm -rf "${OUT:?}"
