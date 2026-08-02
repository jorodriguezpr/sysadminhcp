#!/bin/bash
# SysAdminHCP mail-stack — install from source, no external RPM/package-repo dependency for
# the components built here (notqmail, vpopmail, and whichever of the other 11 components
# are actually built — see each build/<name>/Makefile's own verified/unverified status).
#
# ⚠ THIS SCRIPT ITSELF IS NOT YET LIVE-VERIFIED, even though the build logic it ports IS:
# sysadminhcp/deploy/install-almalinux10.sh (the inline version — the one to actually run
# today) was live-verified end-to-end on a real AlmaLinux 10 box on 2026-08-02, including
# two real bugs found only by re-testing with actual vadddomain/vadduser/vpasswd/vdeluser
# calls and real SMTP/IMAP round-trips, not by trusting a script's own exit-0/"success"
# banner: (1) vpopmail's bundled cdb/conf-cc GCC-14 fix must be patched AFTER ./configure
# runs, not before — configure itself regenerates that file near the end of its own run and
# silently overwrites an earlier edit; (2) the vpopmail MySQL database/user/vpopmail.mysql
# config creation step was gated behind `rpm -q vpopmail`, which is permanently false once
# vpopmail is source-built — this script does NOT perform that database setup step at all
# (see below), so it doesn't carry that specific bug, but it also means running this script
# alone will build working vpopmail binaries with NO real auth database behind them. Either
# port that setup step here before relying on this script for a real install, or keep using
# install-almalinux10.sh directly. Don't run this against a real server expecting it to just
# work — read it first, and expect to fix real problems the same way today's session did.
set -euo pipefail

MAIL_STACK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MAIL_STACK_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root (use sudo)"
fi

# ─── OS detection + MariaDB dev headers (the actual root-cause fix) ────────────────────────
if command -v dnf >/dev/null 2>&1; then
  info "RHEL-family (dnf) detected — installing MariaDB Connector/C dev headers + build tools"
  dnf install -y mariadb-connector-c-devel gcc make curl tar \
    || error "Failed to install MariaDB dev headers — cannot build vpopmail without them"
elif command -v apt-get >/dev/null 2>&1; then
  info "Debian-family (apt) detected — installing MariaDB Connector/C dev headers + build tools"
  apt-get install -y libmariadb-dev libmariadb-dev-compat build-essential curl tar \
    || error "Failed to install MariaDB dev headers — cannot build vpopmail without them"
else
  error "Neither dnf nor apt-get found — this script only supports RHEL-family and Debian-family hosts"
fi

# ─── vpopmail/qmail users, groups, homedir (idempotent — same as install-almalinux10.sh) ───
groupadd -g 89 vchkpw 2>/dev/null || true
useradd -u 89 -g 89 vpopmail -s /sbin/nologin -d /home/vpopmail 2>/dev/null || true
mkdir -p /home/vpopmail && chown vpopmail:vchkpw /home/vpopmail && chmod 755 /home/vpopmail
groupadd nofiles 2>/dev/null || true
groupadd qmail 2>/dev/null || true
for u in alias qmaild qmaill qmailp; do
  useradd -g nofiles -d /var/qmail/alias -s /sbin/nologin "$u" 2>/dev/null || true
done
for u in qmailq qmailr qmails; do
  useradd -g qmail -d /var/qmail -s /sbin/nologin "$u" 2>/dev/null || true
done

# ─── Build everything (see Makefile — this is `make sources`) ──────────────────────────────
info "Building all components from source (see build/<component>/Makefile for each one's real vs. unverified status)..."
make sources

# ─── Deploy config templates ────────────────────────────────────────────────────────────────
info "Deploying qmail supervise run scripts, tcprules, spamdyke config, systemd units..."

mkdir -p /var/qmail/supervise/smtp/log/supervise /var/qmail/supervise/submission/log/supervise /var/qmail/supervise/send/log/supervise
install -m 755 config/qmail/supervise/smtp/run       /var/qmail/supervise/smtp/run
install -m 755 config/qmail/supervise/submission/run /var/qmail/supervise/submission/run
install -m 644 config/qmail/control/defaultdelivery  /var/qmail/control/defaultdelivery
install -m 755 config/qmail/rc                       /var/qmail/rc

mkdir -p /etc/tcprules.d
if [[ ! -f /etc/tcprules.d/tcp.smtp ]]; then
  install -m 644 config/qmail/tcprules/tcp.smtp /etc/tcprules.d/tcp.smtp
else
  warn "/etc/tcprules.d/tcp.smtp already exists — leaving it alone (not overwriting a real ruleset)"
fi
command -v tcprules >/dev/null 2>&1 \
  && tcprules /etc/tcprules.d/tcp.smtp.cdb /etc/tcprules.d/tcp.smtp.tmp < /etc/tcprules.d/tcp.smtp \
  || warn "tcprules not found (ucspi-tcp not built/installed?) — SMTP will refuse all connections until /etc/tcprules.d/tcp.smtp.cdb exists"

mkdir -p /etc/spamdyke /var/spamdyke/graylist
if [[ ! -f /etc/spamdyke/spamdyke.conf ]]; then
  install -m 644 config/spamdyke/spamdyke.conf /etc/spamdyke/spamdyke.conf
else
  warn "/etc/spamdyke/spamdyke.conf already exists — leaving it alone"
fi

install -m 755 config/systemd/qmail-smtp-start.sh       /usr/local/bin/qmail-smtp-start.sh
install -m 755 config/systemd/qmail-submission-start.sh /usr/local/bin/qmail-submission-start.sh
install -m 644 config/systemd/qmail-send.service        /etc/systemd/system/qmail-send.service
install -m 644 config/systemd/qmail-smtp.service         /etc/systemd/system/qmail-smtp.service
install -m 644 config/systemd/qmail-submission.service   /etc/systemd/system/qmail-submission.service

mkdir -p /var/log/qmail/send /var/log/qmail/smtp
chown -R qmaill:qmail /var/log/qmail 2>/dev/null || true
chmod -R 750 /var/log/qmail 2>/dev/null || true

# ─── Dovecot SQL auth — idempotent password reuse, same logic as install-almalinux10.sh ────
# (Regenerating this password unconditionally on every re-run silently desyncs Dovecot's
# stored credential from the real MySQL password, breaking IMAP/POP3/webmail login for every
# mailbox on the server — this is a real, previously-hit bug, not defensive boilerplate.)
DB_PASS=""
if [[ -f /etc/dovecot/dovecot-sql.conf.ext ]]; then
  DB_PASS=$(sed -n "s/.*user=sysadminhcp password=\([^ ]*\).*/\1/p" /etc/dovecot/dovecot-sql.conf.ext | head -1)
fi
[[ -z "$DB_PASS" ]] && DB_PASS=$(openssl rand -hex 12 2>/dev/null || echo 'sysadminhcp123')
sed "s/__SYSADMINHCP_DB_PASS__/${DB_PASS}/" config/dovecot/dovecot-sql.conf.ext > /etc/dovecot/dovecot-sql.conf.ext
chmod 600 /etc/dovecot/dovecot-sql.conf.ext
install -m 644 config/dovecot/conf.d/auth-sql.conf.ext /etc/dovecot/conf.d/auth-sql.conf.ext
warn "Dovecot's own 'sysadminhcp' MySQL user must actually have this password set — this"
warn "script does not create that MySQL user; see install-almalinux10.sh's CREATE USER step"
warn "if the mail-stack install path needs to do this independently in the future."

sed -i 's|^!include auth-system.conf.ext|#!include auth-system.conf.ext|' /etc/dovecot/conf.d/10-auth.conf 2>/dev/null || true
sed -i 's|^#!include auth-sql.conf.ext|!include auth-sql.conf.ext|' /etc/dovecot/conf.d/10-auth.conf 2>/dev/null || true
sed -i 's/^first_valid_uid = .*/first_valid_uid = 89/' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true
grep -q '^mail_uid' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || sed -i '/^first_valid_uid/i mail_uid = vpopmail\nmail_gid = vchkpw' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true
grep -q '^mail_location' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || sed -i '/^mail_uid/i mail_location = maildir:/home/vpopmail/domains/%d/%n/Maildir' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true

[[ ! -h /usr/sbin/sendmail ]] && ln -s /var/qmail/bin/sendmail /usr/sbin/sendmail 2>/dev/null || true

systemctl daemon-reload
systemctl enable --now qmail-send qmail-smtp qmail-submission dovecot 2>&1 || warn "One or more services failed to start — check systemctl status for each"

info "Install-from-source complete. This has NOT been live-verified end-to-end — see"
info "QMAILTOASTER-SELF-HOST-PLAN.md's verification checklist (real vadduser, real SMTP"
info "delivery, real IMAP login) before trusting this on anything but a disposable test box."
