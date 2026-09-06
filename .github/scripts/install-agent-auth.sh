#!/usr/bin/env bash
# Switch hysteria2 from a single shared password to per-agent credentials.
#
# Safe to run repeatedly. The shared password keeps working until it is turned
# off explicitly, so migrating disconnects nobody. If anything fails the old
# config is restored and the service restarted.
#
# Expects authd.sh and hysteria-agent to be in place already.
set -uo pipefail

CFG=/etc/hysteria/config.yaml
AUTHD=/etc/hysteria/authd.sh
DB=/etc/hysteria/agents.tsv
LEGACY=/etc/hysteria/legacy-password
CLI=/usr/local/bin/hysteria-agent
UNIT=hysteria-server
BACKUP="$CFG.bak.$(date -u +%Y%m%d%H%M%S)"

say()  { echo "$*" >&2; }
fail() { say "INSTALL_FAIL: $*"; exit 1; }

rollback() {
  say "INSTALL_ROLLBACK: $*"
  cat "$BACKUP" > "$CFG" 2>/dev/null
  systemctl restart "$UNIT" >/dev/null 2>&1
  sleep 2
  if systemctl is-active --quiet "$UNIT"; then
    say "INSTALL_ROLLBACK: previous config restored, service is running"
  else
    say "INSTALL_ROLLBACK: SERVICE IS DOWN - restore $BACKUP by hand"
  fi
  exit 1
}

[ "$(id -u)" = "0" ]  || fail "must run as root"
[ -f "$CFG" ]         || fail "$CFG not found"
[ -x "$AUTHD" ]       || fail "$AUTHD missing or not executable"
[ -x "$CLI" ]         || fail "$CLI missing or not executable"
id hysteria >/dev/null 2>&1 || fail "user 'hysteria' does not exist"

cp -a "$CFG" "$BACKUP" || fail "could not back up $CFG"
say "backup: $BACKUP"

PORT=$(sed -n 's/^[[:space:]]*listen:[[:space:]]*:\{0,1\}\([0-9]\{1,\}\).*/\1/p' "$CFG" | head -1)
[ -n "$PORT" ] || fail "could not read the listen port from $CFG"

# --- capture the shared password before rewriting -------------------------
if grep -qE '^[[:space:]]*type:[[:space:]]*command[[:space:]]*$' "$CFG"; then
  say "already using command auth, refreshing the supporting files only"
else
  shared=$(sed -n 's/^[[:space:]]*password:[[:space:]]*//p' "$CFG" | head -1)
  [ -n "$shared" ] || fail "could not read the current shared password"
  printf '%s\n' "$shared" > "$LEGACY" || fail "could not write $LEGACY"

  # Replace the whole auth: block. The block runs until the next key at
  # column zero, which is how this config is shaped.
  awk '
    /^auth:/ && !seen {
      print "auth:"
      print "  type: command"
      print "  command: /etc/hysteria/authd.sh"
      print ""
      seen = 1; inblock = 1
      next
    }
    inblock {
      if ($0 ~ /^[^[:space:]]/) { inblock = 0 } else { next }
    }
    { print }
  ' "$BACKUP" > "$CFG.new" || fail "could not rewrite the auth block"

  grep -qE '^[[:space:]]*type:[[:space:]]*command[[:space:]]*$' "$CFG.new" \
    || fail "rewritten config has no command auth"
  grep -q '^listen:' "$CFG.new" || fail "rewritten config lost its listen line"

  cat "$CFG.new" > "$CFG"   # keeps the original owner and mode
  rm -f "$CFG.new"
  say "auth block switched to command"
fi

# --- permissions ----------------------------------------------------------
[ -f "$DB" ] || : > "$DB"
chown root:hysteria "$DB" "$AUTHD" 2>/dev/null
chmod 640 "$DB"
chmod 750 "$AUTHD"
if [ -f "$LEGACY" ]; then
  chown root:hysteria "$LEGACY" 2>/dev/null
  chmod 640 "$LEGACY"
fi

# --- exercise the hook exactly as hysteria will ---------------------------
probe() { runuser -u hysteria -- "$AUTHD" 203.0.113.1 "$1" 0 0 >/dev/null 2>&1; }

if [ -f "$LEGACY" ]; then
  probe "$(cat "$LEGACY")" || rollback "hook rejects the shared password"
  say "selftest: shared password accepted"
fi

"$CLI" add __selftest__ >/dev/null 2>&1 || rollback "hysteria-agent add failed"
selftoken=$(awk -F'\t' '$1 == "__selftest__" { print $2; exit }' "$DB")
probe "__selftest__:$selftoken" || rollback "hook rejects a fresh agent credential"
probe "__selftest__:wrong-token" && rollback "hook accepts a wrong token"
"$CLI" revoke __selftest__ >/dev/null 2>&1
probe "__selftest__:$selftoken" && rollback "hook still accepts a revoked agent"
say "selftest: agent credential accepted, wrong token and revoked agent refused"

# --- restart and confirm it came back -------------------------------------
systemctl restart "$UNIT" || rollback "restart failed"
sleep 3
systemctl is-active --quiet "$UNIT" || rollback "service did not come back"
ss -lun 2>/dev/null | grep -q ":$PORT[[:space:]]" || rollback "port $PORT is not listening"

# clean the selftest row out of the audit trail
tmp=$(mktemp)
grep -v '^__selftest__	' "$DB" > "$tmp" 2>/dev/null
cat "$tmp" > "$DB"
rm -f "$tmp"

say "INSTALL_OK: per-agent auth active, shared password still accepted"
