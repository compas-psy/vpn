#!/bin/sh
# Issue, list and revoke per-agent VPN credentials.
#
#   hysteria-agent add <name>       issue or rotate a credential, print it
#   hysteria-agent list             show every agent and its state
#   hysteria-agent revoke <name>    disable an agent, keeping the audit row
#   hysteria-agent enable <name>    re-enable a revoked agent
#   hysteria-agent legacy off       stop accepting the old shared password
#   hysteria-agent legacy status    is the shared password still accepted
#
# Changes take effect immediately: the auth hook re-reads the database on every
# authentication. Nothing here restarts hysteria.
set -eu

DB=/etc/hysteria/agents.tsv
LEGACY=/etc/hysteria/legacy-password
OWNER_GROUP=hysteria

die() { echo "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "run as root"

ensure_db() {
  if [ ! -f "$DB" ]; then
    : > "$DB"
    chown root:"$OWNER_GROUP" "$DB" 2>/dev/null || true
    chmod 640 "$DB"
  fi
}

valid_name() {
  case "$1" in
    ''|*[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

new_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

set_state() {
  name="$1"; state="$2"
  ensure_db
  grep -q -- "^$name	" "$DB" || die "no such agent: $name"
  tmp=$(mktemp)
  awk -F'\t' -v OFS='\t' -v n="$name" -v s="$state" \
    '$1 == n { $3 = s } { print }' "$DB" > "$tmp"
  cat "$tmp" > "$DB"
  rm -f "$tmp"
  echo "$name: $state"
}

cmd="${1:-}"
case "$cmd" in
  add)
    name="${2:-}"
    valid_name "$name" || die "usage: hysteria-agent add <name>   (A-Z a-z 0-9 . _ -)"
    ensure_db
    token=$(new_token)
    tmp=$(mktemp)
    grep -v -- "^$name	" "$DB" > "$tmp" 2>/dev/null || true
    printf '%s\t%s\t%s\t%s\n' "$name" "$token" enabled "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$tmp"
    cat "$tmp" > "$DB"
    rm -f "$tmp"
    echo "VPN_PASSWORD=$name:$token"
    ;;

  list)
    ensure_db
    printf '%-24s %-10s %s\n' NAME STATE CREATED
    awk -F'\t' '{ printf "%-24s %-10s %s\n", $1, $3, $4 }' "$DB"
    ;;

  revoke) set_state "${2:?usage: hysteria-agent revoke <name>}" revoked ;;
  enable) set_state "${2:?usage: hysteria-agent enable <name>}" enabled ;;

  legacy)
    case "${2:-status}" in
      off)
        rm -f "$LEGACY"
        echo "shared password disabled; only per-agent credentials are accepted"
        ;;
      status)
        if [ -f "$LEGACY" ]; then
          echo "shared password: STILL ACCEPTED (run 'hysteria-agent legacy off' when every client has migrated)"
        else
          echo "shared password: disabled"
        fi
        ;;
      *) die "usage: hysteria-agent legacy off|status" ;;
    esac
    ;;

  *)
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
