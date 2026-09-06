#!/bin/sh
# hysteria2 external authentication hook.
#
# Invoked as: authd.sh <client-addr> <auth-payload> <tx-rate> <rx-rate>
# Exit 0 admits the client; stdout becomes the name hysteria logs for it.
#
# Agents authenticate with "<name>:<token>". The database is re-read on every
# authentication, so `hysteria-agent add|revoke` takes effect at once - no
# restart, no dropped sessions.
#
# While /etc/hysteria/legacy-password exists, the old shared password is also
# accepted. Delete it (`hysteria-agent legacy off`) once every client has moved
# to its own credential.
set -u

DB=/etc/hysteria/agents.tsv
LEGACY=/etc/hysteria/legacy-password

ADDR="${1:-}"
AUTH="${2:-}"

log() { logger -t hysteria-auth -- "$*" 2>/dev/null || true; }

case "$AUTH" in
  *:*)
    name="${AUTH%%:*}"
    token="${AUTH#*:}"
    if [ -n "$name" ] && [ -n "$token" ] && [ -f "$DB" ]; then
      known=$(awk -F'\t' -v n="$name" '$1 == n && $3 == "enabled" { print $2; exit }' "$DB")
      if [ -n "$known" ] && [ "$known" = "$token" ]; then
        log "accept agent=$name addr=$ADDR"
        echo "$name"
        exit 0
      fi
    fi
    log "reject agent=${name:-?} addr=$ADDR"
    ;;
esac

if [ -f "$LEGACY" ] && [ "$AUTH" = "$(cat "$LEGACY")" ]; then
  log "accept legacy addr=$ADDR"
  echo "legacy"
  exit 0
fi

log "reject addr=$ADDR"
exit 1
