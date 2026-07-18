#!/bin/bash
# SysAdminHCP qmail-queue wrapper
#
# Reads the message (fd 0) and envelope (fd 1) concurrently into temp files
# to prevent pipe-buffer deadlock, extracts the sender domain for rate
# limiting and stats counters and DKIM signing, then exec's the real
# qmail-queue with the temp files as fd 0/1.  Temp files are unlinked before
# exec so they are cleaned up even if the process is killed.
#
# Prerequisites (run as root after panel install):
#   cp -p /var/qmail/bin/qmail-queue /var/qmail/bin/qmail-queue.real
#   cp deploy/qmail-queue-check.sh /var/qmail/bin/qmail-queue
#   chmod 755 /var/qmail/bin/qmail-queue && chown root:root /var/qmail/bin/qmail-queue
#   restorecon /var/qmail/bin/qmail-queue 2>/dev/null || true
#   mkdir -p /var/lib/sysadminhcp/email-rate
#   chown -R vpopmail /var/lib/sysadminhcp/email-rate
#   cp deploy/dkim-sign-message.py /var/qmail/bin/dkim-sign-message.py
#   chmod 755 /var/qmail/bin/dkim-sign-message.py
#
# qmail-queue.real must retain its original setuid (qmailq:qmail 4711):
#   chown qmailq:qmail /var/qmail/bin/qmail-queue.real
#   chmod 4711 /var/qmail/bin/qmail-queue.real
#
# Rate limits config: /var/qmail/control/sysadminhcp-ratelimits
#   One line per domain:  example.com 100    (0 or missing = unlimited)
#
# DKIM signing (Ubuntu/Debian only — see enableDkimUbuntu() in mailService.ts):
#   Gated on /var/qmail/control/dkim-signing-enabled (global switch, panel Settings
#   toggle) AND /var/qmail/control/domainkeys/<domain>/private (per-domain key, panel
#   "Generate DKIM Keys" button). Requires python3-dkim (apt package).

REAL_QQ=/var/qmail/bin/qmail-queue.real
RATE_DIR=/var/lib/sysadminhcp/email-rate
LIMITS_CONF=/var/qmail/control/sysadminhcp-ratelimits

# ── Read both pipes concurrently into temp files ──────────────────────
# qmail-smtpd passes the message on fd 0 and the envelope on fd 1.
# Both are readable pipes.  We must read them concurrently: qmail-smtpd
# writes the message first; if it exceeds the pipe buffer (~64 KB) while
# we are not reading fd 0, a deadlock results.
#
# We move fd 1 to fd 3 so that the first background cat can use stdin
# (fd 0) for the message and the second can read fd 3 for the envelope.

MSG_TMP=$(mktemp /tmp/qqmsg.XXXXXX)
ENV_TMP=$(mktemp /tmp/qqenv.XXXXXX)

exec 3<&1       # save envelope pipe on fd 3
exec 1>/dev/null  # fd 1 no longer needed in this shell

# timeout 120s: tcpserver may not set O_CLOEXEC on the pipe fds, so the
# parent keeps a write-end copy alive forever; without a timeout the cats
# hang indefinitely and block every SMTP worker slot.
# <&0 is required: in non-interactive bash, & redirects stdin to /dev/null
# unless an explicit stdin redirect is present — without it, MSG_TMP is empty.
timeout 120 cat <&0 > "$MSG_TMP" &
MSG_PID=$!
timeout 120 cat <&3 > "$ENV_TMP" &
ENV_PID=$!

exec 3>&-       # parent no longer needs fd 3

wait $MSG_PID $ENV_PID

# ── Extract sender domain from envelope ───────────────────────────────
# Envelope: F<sender>\0  T<rcpt>\0  T<rcpt>\0  \0
# 'F' prefix marks the sender. head -c 256 is safe for any real address.
DOMAIN=""
SENDER=$(head -c 256 "$ENV_TMP" | tr '\0' '\n' | head -1 | sed 's/^F//')
if [[ "$SENDER" == *@* ]]; then
  DOMAIN="${SENDER##*@}"
  DOMAIN="${DOMAIN,,}"
  # Reject bounce/null-sender pseudo-domains like "[]" or "#" — only count real domains
  [[ "$DOMAIN" =~ ^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$ ]] || DOMAIN=""
fi

# ── Rate limit helpers ────────────────────────────────────────────────
get_limit() {
  local dom="$1"
  [[ -f "$LIMITS_CONF" && -n "$dom" ]] || { echo 0; return; }
  local lim
  lim=$(grep -i "^${dom} " "$LIMITS_CONF" 2>/dev/null | awk '{print $2}' | head -1)
  [[ "$lim" =~ ^[0-9]+$ ]] && echo "$lim" || echo 0
}

get_hourly_count() {
  local dom="$1"
  local tag; tag=$(date +%Y%m%d%H)
  local cf="${RATE_DIR}/${dom}/${tag}"
  [[ -f "$cf" ]] && { cat "$cf" 2>/dev/null || echo 0; } || echo 0
}

increment_counter() {
  local dom="$1"
  local tag; tag=$(date +%Y%m%d%H)
  local dir="${RATE_DIR}/${dom}"
  local cf="${dir}/${tag}"
  mkdir -p "$dir" 2>/dev/null || true
  local cur
  cur=$(cat "$cf" 2>/dev/null || echo 0)
  echo $(( cur + 1 )) > "$cf" 2>/dev/null || true
  find "$dir" -type f -mmin +2880 -delete 2>/dev/null &
}

# ── Rate limit check + counter increment ──────────────────────────────
if [[ -n "$DOMAIN" ]]; then
  LIMIT=$(get_limit "$DOMAIN")
  if [[ "$LIMIT" -gt 0 ]]; then
    CURRENT=$(get_hourly_count "$DOMAIN")
    if [[ "$CURRENT" -ge "$LIMIT" ]]; then
      rm -f "$MSG_TMP" "$ENV_TMP"
      exit 71
    fi
  fi
  # Always track — stats and rate limiting
  increment_counter "$DOMAIN"
fi

# ── DKIM signing (Ubuntu/Debian only — see enableDkimUbuntu() in mailService.ts) ──────
# Gated on two independent checks so this is a zero-overhead no-op unless both are true:
# a global marker (the Settings-page toggle) and a per-domain private key (the existing
# "Generate DKIM Keys" button, unchanged). Any failure here — missing tool, bad key,
# non-zero exit, empty output — falls back to the original unsigned message; signing must
# never block or corrupt mail delivery.
DKIM_MARKER=/var/qmail/control/dkim-signing-enabled
if [[ -f "$DKIM_MARKER" && -n "$DOMAIN" && -f "/var/qmail/control/domainkeys/${DOMAIN}/private" ]]; then
  SIGNED_TMP=$(mktemp /tmp/qqsigned.XXXXXX)
  if timeout 10 python3 /var/qmail/bin/dkim-sign-message.py "$DOMAIN" "/var/qmail/control/domainkeys/${DOMAIN}/private" < "$MSG_TMP" > "$SIGNED_TMP" 2>/dev/null && [[ -s "$SIGNED_TMP" ]]; then
    mv "$SIGNED_TMP" "$MSG_TMP"
  else
    rm -f "$SIGNED_TMP"
  fi
fi

# ── Open temp files on spare fds, delete them, then exec ─────────────
# Opening on fds 3/4 first keeps the inodes alive after rm so they are
# auto-cleaned when the exec'd process closes those fds.
exec 3< "$MSG_TMP" 4< "$ENV_TMP"
rm -f "$MSG_TMP" "$ENV_TMP"

# exec real qmail-queue: fd 0 = message, fd 1 = envelope (both from temps)
exec "$REAL_QQ" 0<&3 1<&4 3>&- 4>&-

# exec failed — temp files are already gone, exit temp-fail
exit 71
