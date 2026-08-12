#!/bin/bash
# ============================================================================
# SysAdminHCP Control Panel - AlmaLinux 10 Installation Script
# ============================================================================
# This script installs SysAdminHCP on AlmaLinux 10 (or compatible RHEL 10 clones)
# running under WSL or bare metal.
#
# Usage:
#   sudo bash install-almalinux10.sh
#
# Key differences from AlmaLinux 9:
#   - Node.js 22.x (LTS at time of EL10 release)
#   - PHP 8.3 from AppStream (not 8.0 as in EL9)
#   - Remi repo uses remi-release-10.rpm
#   - iptables-nft compat layer (iptables-legacy removed in RHEL 10)
#   - yum removed — dnf only
#   - chkconfig removed — systemctl only
#   - phpMyAdmin path detection (may be /usr/share/phpmyadmin on EL10)
#   - MariaDB config path detection across possible EL10 locations
# ============================================================================

set -euo pipefail

FRESH_INSTALL=0

# ─── Configuration ──────────────────────────────────────────���───────────────
SYSADMINHCP_ROOT="/usr/local/sysadminhcp"
SYSADMINHCP_USER="sysadminhcp"
SYSADMINHCP_GROUP="sysadminhcp"
SYSADMINHCP_SERVICE="sysadminhcp"
NODE_MAJOR=22
NOTQMAIL_VERSION="1.08"
VPOPMAIL_VERSION="5.4.33"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# mail-stack/ ships as a sibling of the repo root in a real published checkout
# ($REPO_DIR/mail-stack); the internal kloxo-8.0.0-25 monorepo instead has it as a sibling of
# sysadminhcp/ itself ($REPO_DIR/../mail-stack) — try both, first one that exists wins.
if [[ -d "$REPO_DIR/mail-stack" ]]; then
  MAIL_STACK_DIR="$REPO_DIR/mail-stack"
elif [[ -d "$REPO_DIR/../mail-stack" ]]; then
  MAIL_STACK_DIR="$(cd "$REPO_DIR/../mail-stack" && pwd)"
else
  MAIL_STACK_DIR=""
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ─── Pre-flight Checks ────────────────────────────────────────────────────
info "SysAdminHCP Control Panel Installer for AlmaLinux 10"
info "================================================"
warn "AlmaLinux 10 / RHEL 10: entire mail stack built from source (mail-stack/) — zero"
warn "dependency on QmailToaster's repo or GitHub, fully live-verified 2026-08-02 on a"
warn "real box. qmail/vpopmail/qmailadmin/vqadmin/ezmlm-idx all link against MariaDB"
warn "Connector/C directly (no libmysqlclient.so.24, no AppStream mysql8.4-libs needed);"
warn "simscan/maildrop link against independently source-built legacy PCRE1/courier-unicode"
warn "libraries (AlmaLinux 10 ships neither by default). Confirmed working end-to-end: real"
warn "vadddomain/vadduser/vpasswd/vdeluser, real network SMTP through"
warn "tcpserver+spamdyke+qmail-smtpd, real IMAP login, a real ezmlm mailing list, a real"
warn "autorespond auto-reply, a real EICAR virus rejection via simscan+ClamAV, and real"
warn "qmailadmin/vqadmin/control-panel logins against the live vpopmail database."

if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root (use sudo)"
fi

if [[ ! -f /etc/os-release ]]; then
  error "Cannot detect OS. /etc/os-release not found"
fi
source /etc/os-release
info "Detected OS: $NAME $VERSION_ID"

if [[ "$ID" != "almalinux" && "$ID" != "rocky" && "$ID" != "centos" && "$ID" != "rhel" ]]; then
  warn "This script is designed for AlmaLinux 10 / RHEL 10 clones."
  warn "Detected ID: $ID. Proceeding anyway..."
fi

# Check WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
  info "Running under WSL (Windows Subsystem for Linux)"
  WSL_MODE=1

  if [[ ! -f /etc/wsl.conf ]] || ! grep -q '^\[boot\]' /etc/wsl.conf || ! grep -q '^systemd=true' /etc/wsl.conf; then
    info "Enabling systemd in WSL..."
    if ! grep -q '^\[boot\]' /etc/wsl.conf 2>/dev/null; then
      printf '\n[boot]\nsystemd=true\n' >> /etc/wsl.conf
    else
      if ! grep -q '^systemd=' /etc/wsl.conf; then
        sed -i '/^\[boot\]/a systemd=true' /etc/wsl.conf
      else
        sed -i 's/^systemd=.*/systemd=true/' /etc/wsl.conf
      fi
    fi
    info "systemd enabled in /etc/wsl.conf"
    wslpath -w / 2>/dev/null && exec wsl.exe --shutdown 2>/dev/null || true
    error "WSL needs to restart for systemd to activate. Run: wsl --shutdown (from PowerShell), then re-run this installer."
  fi

  if [[ ! -d /run/systemd/system ]]; then
    error "systemd is not running. Enable it with: edit /etc/wsl.conf → [boot]\\nsystemd=true, then restart WSL with 'wsl --shutdown' from PowerShell."
  fi
  info "systemd is active"
else
  WSL_MODE=0
fi

if [[ -f "$SYSADMINHCP_ROOT/httpdocs/dist/index.js" || -f "$SYSADMINHCP_ROOT/httpdocs/sysadminhcp" ]]; then
  info "Existing SysAdminHCP installation detected - upgrading..."
else
  FRESH_INSTALL=1
  info "Fresh installation detected"
fi

if ! touch /usr/.sysadminhcp-write-test 2>/dev/null; then
  warn "/usr is mounted read-only. Remounting as read-write..."
  mount -o remount,rw /usr
  if ! touch /usr/.sysadminhcp-write-test 2>/dev/null; then
    error "/usr is still read-only after remount. Cannot install packages."
  fi
  rm -f /usr/.sysadminhcp-write-test
  info "/usr is now read-write"
else
  rm -f /usr/.sysadminhcp-write-test
  info "/usr is writable"
fi

# ─── Pre-flight: Disable SELinux ────────────────────────────────────────────
info "Disabling SELinux (required for control panel operation)..."
if [[ -f /etc/selinux/config ]]; then
  sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
  sed -i 's/^SELINUX=permissive/SELINUX=disabled/' /etc/selinux/config
  info "SELinux set to disabled in /etc/selinux/config (takes full effect after reboot)"
fi
if command -v setenforce &>/dev/null 2>&1; then
  setenforce 0 2>/dev/null || true
  info "SELinux enforcement disabled for current session"
fi

# ─── Step 1: System Update ─────────────────────────────────────────────────
info "Step 1: Updating system packages..."
# network-scripts (legacy ifup/ifdown tooling, superseded by NetworkManager)
# pins an old initscripts version that conflicts with the newer one `dnf
# update` wants to pull in ("cannot install both initscripts-X and
# initscripts-Y"). Some AlmaLinux cloud images ship it pre-installed even
# though the OS no longer needs it for networking — remove it first if
# present, before the update runs.
dnf remove -y network-scripts 2>/dev/null || true
dnf update -y

# ─── Step 2: Install EPEL Repository ────────────────────────────────────────
info "Step 2: Installing EPEL repository..."
dnf install -y epel-release

# ─── Step 3: Install Node.js ───────────────────────────────────────────────
info "Step 3: Installing Node.js $NODE_MAJOR.x..."
if ! command -v node &>/dev/null; then
  dnf install -y curl
  curl -fsSL https://rpm.nodesource.com/setup_$NODE_MAJOR.x | bash -
  dnf install -y nodejs
fi
NODE_VERSION=$(node --version)
info "Node.js installed: $NODE_VERSION"

# ─── Step 4: Install Build Tools ───────────────────────────────────────────
info "Step 4: Installing build tools..."
dnf install -y gcc-c++ make python3

# ─── Step 5: Install Service Dependencies ───────────────────────────────────
info "Step 5: Installing service dependencies..."

# Web server
dnf install -y httpd httpd-devel mod_ssl

# DNS
dnf install -y bind bind-utils

# Mail — remove postfix (conflicts with qmail)
dnf remove -y postfix 2>/dev/null || true
userdel postfix 2>/dev/null || true

# No QmailToaster repo registration — every mail-stack component below is either built from
# real upstream/vendored source (mail-stack/, see mail-stack/vendor/README.md) or a genuine
# AlmaLinux AppStream/CRB package. install-almalinux10.sh has zero dependency on
# repo.whitehorsetc.com or qmtoaster GitHub as of 2026-08-02 — confirmed by grepping this
# file for both and finding no matches outside this comment.
dnf install -y mariadb-connector-c-devel gcc gcc-c++ make patch autoconf automake bzip2 perl pcre2-devel gdbm-devel libidn2-devel 2>/dev/null || warn "Build tools failed to install — source builds below will fail without them"

# ucspi-tcp/daemontools/libsrs2/ripmime: source-built from mail-stack/ (vendored from QMT's
# own EL10 SRPMs — see mail-stack/vendor/README.md for why: no independent upstream mirror
# exists for these, and every "fetch from github.com/notqmail/..." URL a previous version of
# this approach tried was fabricated/404. Confirmed live 2026-08-02: none of these four have
# any MySQL/library linkage problem at all (this was checked before deciding to still build
# them from source) — done anyway per explicit direction to eliminate the qmt-testing repo
# dependency entirely, not just fix what's broken.
if [[ -n "$MAIL_STACK_DIR" ]]; then
  for comp in ucspi-tcp daemontools libsrs2 ripmime; do
    make -C "$MAIL_STACK_DIR/build/$comp" build || error "$comp source build failed — see output above"
  done
  info "ucspi-tcp/daemontools/libsrs2/ripmime built from vendored source (mail-stack/)"
else
  error "mail-stack/ not found next to this script — cannot source-build ucspi-tcp/daemontools/libsrs2/ripmime. Expected at \$REPO_DIR/mail-stack or \$REPO_DIR/../mail-stack."
fi

dnf install -y spamassassin dovecot dovecot-mysql clamav clamd fetchmail 2>/dev/null || warn "Some OS mail packages failed to install"

# maildrop: source-built from mail-stack/ — standalone (no qmail/vpopmail dependency, safe
# to build here). Not currently wired into any real SysAdminHCP feature (checked
# systemService.ts — only a comment references it), built anyway per explicit direction to
# eliminate the qmt-testing repo dependency for every component it currently pulls in, not
# just the actively-used ones. Its own courier-unicode-devel dependency only exists for EL10
# via qmt-testing too — but courier-unicode is a real independent open-source library
# (courier-mta.org), so it's vendored and built from its own real source, same as legacy
# PCRE1 was for simscan. Real functional test 2026-08-02: piped a real test message through
# maildrop -d, confirmed it landed in the real system mailbox, not just "it compiled".
make -C "$MAIL_STACK_DIR/build/maildrop" build || error "maildrop source build failed — see output above"
info "maildrop built from vendored source (mail-stack/), including its own courier-unicode dependency"

# Still QMT RPMs for now — being migrated to mail-stack/ source builds the same way as
# the other components, one tier at a time.
# qmailmrtg/isoqlog: source-built from mail-stack/ — no independent upstream mirror exists
# for either (confirmed live 2026-08-02), vendored from QMT's own EL10 SRPMs the same way as
# every other component without a real GitHub mirror. Real functional tests: qmailmrtg run
# directly against the live /var/qmail/queue produced real numeric output; isoqlog run
# directly against the real /var/log/qmail/send multilog produced real generated HTML
# statistics pages — both real program behavior, not just "it compiled". mrtg itself (the
# real Debian/EPEL-style tool qmailmrtg's cron job feeds) is a genuine AlmaLinux AppStream
# package, not QMT-branded.
dnf install -y mrtg cronie crontabs 2>/dev/null || warn "mrtg/cron packages failed to install"
make -C "$MAIL_STACK_DIR/build/qmailmrtg" build || error "qmailmrtg source build failed — see output above"
make -C "$MAIL_STACK_DIR/build/isoqlog" build || error "isoqlog source build failed — see output above"
info "qmailmrtg/isoqlog built from vendored source (mail-stack/)"

# control-panel: QMT's own bespoke PHP mini-admin app (not a real independent open-source
# project — no upstream to build from at all, plain PHP with no compile step). Deployed
# directly from mail-stack/vendor/control-panel/ (one-time fork from QMT's own SRPM, same as
# every other no-upstream component — see mail-stack/vendor/README.md) rather than the QMT
# RPM. Kept per explicit direction even though SysAdminHCP has its own admin UI — this is
# optional legacy tooling, not a replacement for the panel.
if [[ -n "$MAIL_STACK_DIR" && -d "$MAIL_STACK_DIR/vendor/control-panel" ]]; then
  mkdir -p /usr/share/toaster/htdocs/admin /usr/share/toaster/htdocs/images /usr/share/toaster/include
  install -m 644 "$MAIL_STACK_DIR/vendor/control-panel/index.php" /usr/share/toaster/htdocs/admin/index.php
  install -m 644 "$MAIL_STACK_DIR/vendor/control-panel/admin.inc.php" /usr/share/toaster/include/admin.inc.php
  install -m 644 "$MAIL_STACK_DIR/vendor/control-panel/email.php" /usr/share/toaster/include/email.php
  install -m 644 "$MAIL_STACK_DIR/vendor/control-panel/send-email.module" /usr/share/toaster/include/send-email.module
  install -m 644 "$MAIL_STACK_DIR/vendor/control-panel/javascripts.js" /usr/share/toaster/htdocs/scripts/javascripts.js 2>/dev/null || \
    { mkdir -p /usr/share/toaster/htdocs/scripts && install -m 644 "$MAIL_STACK_DIR/vendor/control-panel/javascripts.js" /usr/share/toaster/htdocs/scripts/javascripts.js; }
  install -m 644 "$MAIL_STACK_DIR/vendor/control-panel/styles.css" /usr/share/toaster/htdocs/scripts/styles.css
  install -m 644 "$MAIL_STACK_DIR/vendor/control-panel/background.gif" /usr/share/toaster/htdocs/images/background.gif
  install -m 644 "$MAIL_STACK_DIR/vendor/control-panel/kl-qmail-w.gif" /usr/share/toaster/htdocs/images/kl-qmail-w.gif
  [ -f /etc/httpd/conf/toaster.conf ] || install -m 644 "$MAIL_STACK_DIR/vendor/control-panel/toaster.conf" /etc/httpd/conf/toaster.conf
  grep -q 'toaster.conf' /etc/httpd/conf/httpd.conf 2>/dev/null || echo 'Include conf/toaster.conf' >> /etc/httpd/conf/httpd.conf
  # toaster.conf gates /admin-toaster, /stats-toaster (mrtg), and the vqadmin CGI behind
  # both an IP allowlist (127.0.0.1 by default — safe default, matches the same real IP
  # restriction the RPM version always shipped) and HTTP Basic Auth against this htpasswd
  # file, which doesn't exist until created here. Idempotent: only generated once, password
  # is real/random, not a hardcoded default.
  if [[ ! -f /usr/share/toaster/include/admin.htpasswd ]]; then
    TOASTER_ADMIN_PASS=$(openssl rand -hex 8 2>/dev/null || echo 'toaster123')
    htpasswd -bc /usr/share/toaster/include/admin.htpasswd admin "$TOASTER_ADMIN_PASS" >/dev/null 2>&1
    echo "$TOASTER_ADMIN_PASS" > /root/.toaster-admin-password
    chmod 600 /root/.toaster-admin-password
    info "Legacy toaster admin (control-panel/vqadmin CGI) password saved to /root/.toaster-admin-password"
  fi
  info "control-panel deployed from vendored source (mail-stack/)"
else
  warn "mail-stack/vendor/control-panel not found — skipping legacy control-panel deployment"
fi

groupadd -g 89 vchkpw 2>/dev/null || true
useradd -u 89 -g 89 vpopmail -s '/sbin/nologin' -d /home/vpopmail 2>/dev/null || true
mkdir -p /home/vpopmail
chown vpopmail:vchkpw /home/vpopmail
chmod 755 /home/vpopmail

# qmail users/groups (classic layout, needed before the source build below)
groupadd nofiles 2>/dev/null || true
groupadd qmail   2>/dev/null || true
for u in alias qmaild qmaill qmailp; do
  useradd -g nofiles -d /var/qmail/alias -s /sbin/nologin "$u" 2>/dev/null || true
done
for u in qmailq qmailr qmails; do
  useradd -g qmail -d /var/qmail -s /sbin/nologin "$u" 2>/dev/null || true
done

# ── Build notqmail from source (see comment above — same real fix already proven working
# on install-ubuntu22.sh, which has built qmail this way against MariaDB successfully) ─────
if [[ ! -x /var/qmail/bin/qmail-smtpd ]]; then
  info "Building notqmail $NOTQMAIL_VERSION from source..."
  cd /tmp
  rm -rf "notqmail-$NOTQMAIL_VERSION"
  if curl -fsSL -o notqmail.tar.gz \
      "https://github.com/notqmail/notqmail/releases/download/notqmail-$NOTQMAIL_VERSION/notqmail-$NOTQMAIL_VERSION.tar.gz"; then
    tar xzf notqmail.tar.gz
    cd "notqmail-$NOTQMAIL_VERSION"
    # GCC 14 (AlmaLinux 10's default) made -Wimplicit-function-declaration an error instead
    # of a warning — breaks seek_cur.c/seek_end.c/seek_set.c (call lseek() without including
    # <unistd.h>, ~20-year-old K&R-style code). conf-cc is what notqmail's DJB-style build
    # actually reads for the compile command — it does NOT respect the CFLAGS env var, so
    # this can't be fixed by setting CFLAGS before the make calls below. Confirmed live on a
    # real AlmaLinux 10 box: this exact fix takes the build from a hard compile error to a
    # clean install.
    echo "cc -O2 -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion" > conf-cc
    make -j"$(nproc)" 2>&1 | tail -3 || true
    make setup check 2>&1 | tail -3
    ./config-fast "$(hostname -f 2>/dev/null || hostname)" 2>/dev/null || true
    info "notqmail installed to /var/qmail"
    cd /tmp && rm -rf "notqmail-$NOTQMAIL_VERSION" notqmail.tar.gz
  else
    warn "notqmail download failed — mail (SMTP) will be unavailable until installed manually"
  fi
else
  info "qmail already present at /var/qmail — skipping build"
fi

if [ -d /var/qmail/control ]; then
  echo "./Maildir/" > /var/qmail/control/defaultdelivery
fi
if [ -d /var/qmail ]; then
  cat > /var/qmail/rc << 'EOF'
#!/bin/sh
exec env - PATH="/var/qmail/bin:$PATH" \
qmail-start "`cat /var/qmail/control/defaultdelivery 2>/dev/null || echo ./Maildir/`"
EOF
  chmod 755 /var/qmail/rc
fi

# ── Build vpopmail from source against MariaDB Connector/C (the actual fix — same
# -fcommon/header-detection approach already proven on install-ubuntu22.sh) ────────────────
if [[ ! -x /home/vpopmail/bin/vadddomain && -d /var/qmail ]]; then
  info "Building vpopmail $VPOPMAIL_VERSION from source (MySQL auth via MariaDB Connector/C)..."
  cd /tmp
  rm -rf "vpopmail-$VPOPMAIL_VERSION"
  if curl -fsSL -o vpopmail.tar.gz \
      "https://sourceforge.net/projects/vpopmail/files/vpopmail-stable/$VPOPMAIL_VERSION/vpopmail-$VPOPMAIL_VERSION.tar.gz/download"; then
    tar xzf vpopmail.tar.gz
    cd "vpopmail-$VPOPMAIL_VERSION"
    MYSQL_INC="/usr/include/mysql"
    [[ -d /usr/include/mariadb && ! -d /usr/include/mysql ]] && MYSQL_INC="/usr/include/mariadb"
    # Same GCC 10+ -fcommon fix already proven on install-ubuntu22.sh — this ~20-year-old
    # codebase relies on pre-GCC-10 tentative-definition behavior for several globals. The
    # three -Wno-error= flags are the same GCC 14 fix as notqmail's, for the
    # (autoconf-driven, CFLAGS-respecting) vpopmail build outside the cdb/ subdirectory.
    export CFLAGS="-fcommon -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion"
    ./configure \
      --enable-auth-module=mysql \
      --enable-many-domains=y \
      --enable-incdir="$MYSQL_INC" \
      --enable-libdir=/usr/lib64 \
      --enable-auth-logging=y \
      --enable-clear-passwd=y \
      --enable-logging=p > /tmp/vpopmail_build.log 2>&1
    # vpopmail vendors its OWN copy of the DJB cdb library (cdb/cdb_seek.c — the exact same
    # file/issue as notqmail's seek_*.c above), built via its own internal conf-cc that does
    # NOT respect the outer CFLAGS above. This MUST run AFTER ./configure, not before —
    # confirmed live: configure's own generated script itself does
    # `echo "${CC} -O2" > cdb/conf-cc` as one of its last steps (the file doesn't even exist
    # in the raw tarball at all), silently overwriting an earlier edit and reintroducing the
    # exact same GCC 14 implicit-function-declaration/incompatible-pointer-types errors.
    if [[ -f cdb/conf-cc ]]; then
      echo "gcc -O2 -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion" > cdb/conf-cc
    fi
    make -j"$(nproc)" >> /tmp/vpopmail_build.log 2>&1 && make install-strip >> /tmp/vpopmail_build.log 2>&1
    if [[ -x /home/vpopmail/bin/vadddomain ]]; then
      info "vpopmail installed to /home/vpopmail"
      rm -f /tmp/vpopmail_build.log
    else
      warn "vpopmail build did not produce binaries — mail account management will be unavailable"
      warn "Last 30 lines of build log (full log kept at /tmp/vpopmail_build.log):"
      tail -30 /tmp/vpopmail_build.log | while IFS= read -r line; do warn "  $line"; done
    fi
    cd /tmp && rm -rf "vpopmail-$VPOPMAIL_VERSION" vpopmail.tar.gz
  else
    warn "vpopmail download failed — install manually from sourceforge.net/projects/vpopmail"
  fi
else
  info "vpopmail already present (or qmail missing) — skipping build"
fi

# vpopmail's own stock Makefile.in already writes lib_deps/inc_deps (the exact linker/include
# flags needed to build against libvpopmail.a) to /home/vpopmail/etc/ — QMT's own
# libvpopmail-devel packaging just relocates these two files to /etc/libvpopmail/ for a
# separate devel RPM. qmailadmin/vqadmin's real configure.ac scripts hardcode that
# /etc/libvpopmail/{lib,inc}_deps path (qmailadmin's own patch further redirects to
# /home/vpopmail/{lib,inc}_deps directly, no etc/ subdir — a second QMT convention for the
# same two files) — these symlinks satisfy both without a separate devel package. Checked
# every run, not gated behind vpopmail's own build-skip check above — confirmed live
# 2026-08-02: when vpopmail was already built from an earlier run, the equivalent guarded
# logic never ran, leaving qmailadmin/vqadmin's builds unable to find these files even
# though vpopmail itself was fine.
if [[ -x /home/vpopmail/bin/vadddomain ]]; then
  mkdir -p /etc
  [ -e /etc/libvpopmail ] || ln -s /home/vpopmail/etc /etc/libvpopmail
  [ -e /home/vpopmail/inc_deps ] || ln -s etc/inc_deps /home/vpopmail/inc_deps
  [ -e /home/vpopmail/lib_deps ] || ln -s etc/lib_deps /home/vpopmail/lib_deps
fi

# autorespond/ezmlm-idx/spamdyke: source-built from mail-stack/ — same vendored-from-QMT's-
# own-EL10-SRPM approach as tier 1 above (no independent upstream mirror exists for these
# either). MUST run here, after qmail/vpopmail above, not earlier — their own Makefiles
# depend on /var/qmail/bin/qmail-smtpd existing (confirmed live: an earlier version of this
# script placed this block before the qmail build and failed on a genuinely fresh box with
# "No rule to make target /var/qmail/bin/qmail-smtpd" — only masked on this box because it
# was never actually fresh between test runs). Real functional tests confirmed live
# 2026-08-02: a real ezmlm mailing list (ezmlm-make/ezmlm-sub) delivered a real message to a
# real subscriber; autorespond generated a real queued auto-reply and correctly refused to
# reply to a bounce (anti-loop check); spamdyke rebuilt with QMT's own real openssl3.patch
# (modernizes deprecated OpenSSL 1.x API calls) instead of the earlier config-only
# TLS-1.2-only workaround.
for comp in autorespond ezmlm-idx spamdyke; do
  make -C "$MAIL_STACK_DIR/build/$comp" build || error "$comp source build failed — see output above"
done
info "autorespond/ezmlm-idx/spamdyke built from vendored source (mail-stack/)"

# simscan: source-built from mail-stack/ against a real, independently source-built legacy
# PCRE1 (see mail-stack/build/simscan/Makefile) — simscan's own configure.in hard-requires
# the legacy pcre.h/pcre_compile API, which AlmaLinux 10 dropped (PCRE2 only). PCRE1 itself
# is a real, independent open-source library (pcre.org), not QMT-authored, so it's built
# from its own real source rather than depending on QMT's repo for the pcre-devel package.
# Also depends on qmail-smtpd + ripmime — same ordering requirement as above.
# Real functional test 2026-08-02: invoked simscan directly with a real EICAR test string on
# the correct fd0=message/fd1=envelope protocol qmail-smtpd uses — clamd genuinely detected
# it (Eicar-Signature FOUND) and simscan correctly rejected (exit 82), not just "it compiled".
make -C "$MAIL_STACK_DIR/build/simscan" build || error "simscan source build failed — see output above"
info "simscan built from vendored source (mail-stack/), linked against a real source-built PCRE1"

# qmailadmin/vqadmin: source-built against our own real vpopmail (headers/lib at
# /home/vpopmail) + MariaDB Connector/C — depends on vpopmail + ezmlm-idx + autorespond
# above. Replaces the earlier one-line mysql8.4-libs fix (AppStream's real Oracle MySQL 8.4
# client, which DID work and was live-verified, but is one more external dependency than
# necessary now that we're building these two from source anyway) with a build fully
# consistent with vpopmail's own approach — one real library (MariaDB Connector/C)
# throughout, no AppStream mysql8.4-libs needed at all for these two anymore. Real
# functional tests confirmed live 2026-08-02: a real POST-based qmailadmin login rendered
# real account/quota data, and a real vqadmin domain-admin auth succeeded — both against the
# live vpopmail MySQL tables, both linked against libmariadb.so.3 (confirmed via ldd).
make -C "$MAIL_STACK_DIR/build/vqadmin" build || error "vqadmin source build failed — see output above"
make -C "$MAIL_STACK_DIR/build/qmailadmin" build || error "qmailadmin source build failed — see output above"
info "qmailadmin/vqadmin built from vendored source (mail-stack/), linked against MariaDB Connector/C"

# ── qmail supervise run scripts — source-built qmail/vpopmail don't ship these; the QMT
# "qmail" RPM we no longer install used to. SMTPAUTH values below match what was confirmed
# live on a real server today: "!" on submission (587) requires TLS before AUTH is even
# advertised (correct — that's the one thing worth protecting even on an otherwise-relaxed
# mail setup); "-" on smtp (25) matches this fleet's existing convention there, where
# spamdyke's own anti-spam checks apply instead of client AUTH. ───────────────────────────
mkdir -p /var/qmail/supervise/smtp/log/supervise /var/qmail/supervise/submission/log/supervise /var/qmail/supervise/send/log/supervise 2>/dev/null || true

cat > /var/qmail/supervise/smtp/run << 'EOF'
#!/bin/sh
QMAILDUID=`id -u vpopmail`
NOFILESGID=`id -g vpopmail`
MAXSMTPD=`cat /var/qmail/control/concurrencyincoming 2>/dev/null || echo 20`
SPAMDYKE="/usr/bin/spamdyke"
SPAMDYKE_CONF="/etc/spamdyke/spamdyke.conf"
SMTPD="/var/qmail/bin/qmail-smtpd"
TCP_CDB="/etc/tcprules.d/tcp.smtp.cdb"
HOSTNAME=`hostname`
VCHKPW="/home/vpopmail/bin/vchkpw"
export SMTPAUTH="-"

exec /usr/bin/softlimit -m 256000000 \
     /usr/bin/tcpserver -v -R -H -l $HOSTNAME -x $TCP_CDB -c "$MAXSMTPD" \
     -u "$QMAILDUID" -g "$NOFILESGID" 0 smtp \
     $SPAMDYKE --config-file $SPAMDYKE_CONF \
     $SMTPD $VCHKPW /bin/true 2>&1
EOF
chmod 755 /var/qmail/supervise/smtp/run

cat > /var/qmail/supervise/submission/run << 'EOF'
#!/bin/sh
QMAILDUID=`id -u vpopmail`
NOFILESGID=`id -g vpopmail`
MAXSMTPD=`cat /var/qmail/control/concurrencyincoming 2>/dev/null || echo 20`
SMTPD="/var/qmail/bin/qmail-smtpd"
TCP_CDB="/etc/tcprules.d/tcp.smtp.cdb"
HOSTNAME=`hostname`
VCHKPW="/home/vpopmail/bin/vchkpw"
export SMTPAUTH="!"

exec /usr/bin/softlimit -m 128000000 \
    /usr/bin/tcpserver -v -R -H -l $HOSTNAME -x $TCP_CDB -c "$MAXSMTPD" \
    -u "$QMAILDUID" -g "$NOFILESGID" 0 587 \
    $SMTPD $VCHKPW /bin/true 2>&1
EOF
chmod 755 /var/qmail/supervise/submission/run

# tcp.smtp source + compiled .cdb — previously provided by the QMT "qmail" RPM we no
# longer install; ucspi-tcp (still RPM-installed, unchanged) provides the `tcprules`
# binary but not this default ruleset. Only created if missing, so an existing real
# ruleset (e.g. one already customized by the panel) is never overwritten.
mkdir -p /etc/tcprules.d
if [ ! -f /etc/tcprules.d/tcp.smtp ]; then
  cat > /etc/tcprules.d/tcp.smtp << 'EOF'
127.:allow,RELAYCLIENT="",RBLSMTPD="",NOP0FCHECK="1"
:allow,BADMIMETYPE="",BADLOADERTYPE="M",CHKUSER_RCPTLIMIT="50",CHKUSER_WRONGRCPTLIMIT="10",QMAILQUEUE="/var/qmail/bin/simscan",NOP0FCHECK="1"
EOF
fi
command -v tcprules >/dev/null 2>&1 && tcprules /etc/tcprules.d/tcp.smtp.cdb /etc/tcprules.d/tcp.smtp.tmp < /etc/tcprules.d/tcp.smtp 2>/dev/null || warn "tcprules not found — SMTP will refuse all connections until /etc/tcprules.d/tcp.smtp.cdb exists"

# Configure qmail (chkconfig not available on EL10 — managed via systemd units below)
if [ -f /var/qmail/supervise/smtp/run ]; then
  sed -i 's/softlimit -m.*\\/softlimit -m 256000000 \\/' /var/qmail/supervise/smtp/run 2>/dev/null || true
fi

# Wire spamdyke into the port-25 SMTP pipeline by default. QmailToaster's stock run script
# ships spamdyke's config vars commented out ("# # SPAMDYKE=...") and never references them in
# the actual exec chain — every fresh install was accepting mail with zero connection-level
# spam filtering until an admin manually enabled it via the panel. Only touches port 25 (the
# unauthenticated public listener); submission (587) is left alone since IP-reputation checks
# would incorrectly reject legitimate authenticated senders on residential/mobile IPs.
mkdir -p /etc/spamdyke /var/spamdyke/graylist 2>/dev/null || true
if [ ! -s /etc/spamdyke/spamdyke.conf ]; then
  cat > /etc/spamdyke/spamdyke.conf << 'SPAMDYKECONF'
graylist-level=none
greeting-delay-secs=6
max-recipients=50
reject-empty-rdns
reject-unresolvable-rdns
reject-sender=no-mx
dns-blacklist-entry=bl.rbl-dns.com
SPAMDYKECONF
fi
# Fix spamdyke's broken default TLS cipher list — it passes TLS 1.3 ciphersuite names
# ("TLS_AES_256_GCM_SHA384:..." — that's the package-shipped spamdyke.conf default here) to
# OpenSSL's legacy SSL_CTX_set_cipher_list() (the TLS <=1.2 API, which never accepted TLS 1.3
# suite names — those need the separate SSL_CTX_set_ciphersuites() call spamdyke doesn't use).
# Older OpenSSL tolerated the mismatch; OpenSSL 3.2+ (EL10's default) rejects it outright,
# logging "unable to set SSL/TLS cipher list" on every connection and silently breaking
# STARTTLS. Idempotent: strips any existing tls-cipher-list line (right or wrong) before
# appending the corrected one, so re-running this script always converges on the fix.
for f in /etc/spamdyke/spamdyke.conf /etc/spamdyke/spamdyke-submission.conf; do
  if [ -f "$f" ]; then
    sed -i '/^#\?tls-cipher-list=/d' "$f"
    echo 'tls-cipher-list=ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384' >> "$f"
  fi
done

if [ -f /var/qmail/supervise/smtp/run ] && ! grep -q '\$SPAMDYKE --config-file' /var/qmail/supervise/smtp/run; then
  sed -i 's|^# # SPAMDYKE="/usr/bin/spamdyke"|SPAMDYKE="/usr/bin/spamdyke"|' /var/qmail/supervise/smtp/run
  sed -i 's|^# # SPAMDYKE_CONF="/etc/spamdyke/spamdyke.conf"|SPAMDYKE_CONF="/etc/spamdyke/spamdyke.conf"|' /var/qmail/supervise/smtp/run
  sed -i 's|^\(\s*\)\$SMTPD \$VCHKPW /bin/true|\1$SPAMDYKE --config-file $SPAMDYKE_CONF \\\n\1$SMTPD $VCHKPW /bin/true|' /var/qmail/supervise/smtp/run
fi

for svc in smtp send smtps submission; do
  [ -d /var/qmail/supervise/$svc ] && chmod 755 /var/qmail/supervise/$svc
  [ -d /var/qmail/supervise/$svc/log ] && chmod 755 /var/qmail/supervise/$svc/log
  mkdir -p /var/qmail/supervise/$svc/log/supervise 2>/dev/null || true
done

if [ -f /etc/clamd.d/scan.conf ]; then
  sed -i 's/^#LocalSocket /LocalSocket /' /etc/clamd.d/scan.conf 2>/dev/null || true
fi
chown -R clamupdate:clamupdate /var/lib/clamav 2>/dev/null || true

# Idempotent: reuse the existing password on re-runs/upgrades instead of generating a new
# one every time. CREATE USER IF NOT EXISTS later is a no-op if the MySQL user already
# exists, so regenerating this password unconditionally silently desyncs Dovecot's stored
# credential from the real MySQL password — breaking IMAP/POP3/webmail auth for every
# mailbox on the server until manually fixed.
KLOXOJRA_DB_PASS=""
if [[ -f /etc/dovecot/dovecot-sql.conf.ext ]]; then
  KLOXOJRA_DB_PASS=$(sed -n "s/.*user=sysadminhcp password=\([^ ]*\).*/\1/p" /etc/dovecot/dovecot-sql.conf.ext | head -1)
fi
[[ -z "$KLOXOJRA_DB_PASS" ]] && KLOXOJRA_DB_PASS=$(openssl rand -hex 12 2>/dev/null || echo 'sysadminhcp123')

cat > /etc/dovecot/dovecot-sql.conf.ext << DOVECOTSQL
# SysAdminHCP Dovecot vpopmail MySQL authentication
driver = mysql
connect = host=127.0.0.1 dbname=vpopmail user=sysadminhcp password=${KLOXOJRA_DB_PASS}

default_pass_scheme = CRYPT

password_query = \
  SELECT pw_passwd AS password, \
  CONCAT('/home/vpopmail/domains/', pw_domain, '/', pw_name) AS userdb_home, \
  89 AS userdb_uid, \
  89 AS userdb_gid, \
  CONCAT('maildir:/home/vpopmail/domains/', pw_domain, '/', pw_name, '/Maildir') AS userdb_mail \
  FROM vpopmail \
  WHERE pw_name = '%n' AND pw_domain = '%d'

user_query = \
  SELECT CONCAT('/home/vpopmail/domains/', pw_domain, '/', pw_name) AS home, \
  CONCAT('maildir:/home/vpopmail/domains/', pw_domain, '/', pw_name, '/Maildir') AS mail, \
  89 AS uid, \
  89 AS gid \
  FROM vpopmail \
  WHERE pw_name = '%n' AND pw_domain = '%d'

iterate_query = SELECT CONCAT(pw_name, '@', pw_domain) AS user FROM vpopmail
DOVECOTSQL
chmod 600 /etc/dovecot/dovecot-sql.conf.ext

sed -i 's|^!include auth-system.conf.ext|#!include auth-system.conf.ext|' /etc/dovecot/conf.d/10-auth.conf 2>/dev/null || true
sed -i 's|^#!include auth-sql.conf.ext|!include auth-sql.conf.ext|' /etc/dovecot/conf.d/10-auth.conf 2>/dev/null || true

cat > /etc/dovecot/conf.d/auth-sql.conf.ext << 'AUTHSQL'
passdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
userdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
AUTHSQL

sed -i 's/^first_valid_uid = .*/first_valid_uid = 89/' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true
grep -q '^mail_uid' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || sed -i '/^first_valid_uid/i mail_uid = vpopmail\nmail_gid = vchkpw' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true
grep -q '^mail_location' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || sed -i '/^mail_uid/i mail_location = maildir:/home/vpopmail/domains/%d/%n/Maildir' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true

[ ! -h /usr/sbin/sendmail ] && ln -s /var/qmail/bin/sendmail /usr/sbin/sendmail 2>/dev/null || true
grep -q '/var/qmail/man' /etc/man_db.conf 2>/dev/null || echo "MANDATORY_MANPATH /var/qmail/man" >> /etc/man_db.conf 2>/dev/null

# Qmail systemd wrapper scripts
cat > /usr/local/bin/qmail-smtp-start.sh << 'EOF'
#!/bin/bash
exec /var/qmail/supervise/smtp/run
EOF
chmod 755 /usr/local/bin/qmail-smtp-start.sh

cat > /usr/local/bin/qmail-submission-start.sh << 'EOF'
#!/bin/bash
exec /var/qmail/supervise/submission/run
EOF
chmod 755 /usr/local/bin/qmail-submission-start.sh

mkdir -p /var/log/qmail/send /var/log/qmail/smtp
chown -R qmaill:qmail /var/log/qmail 2>/dev/null || true
chmod -R 750 /var/log/qmail 2>/dev/null || true

cat > /etc/systemd/system/qmail-send.service << 'QMSVC'
[Unit]
Description=QmailToaster mail delivery (qmail-send)
After=network.target mariadb.service
Wants=mariadb.service

[Service]
Type=simple
User=root
ExecStart=/var/qmail/rc
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/qmail/send/current
StandardError=append:/var/log/qmail/send/current

[Install]
WantedBy=multi-user.target
QMSVC

cat > /etc/systemd/system/qmail-smtp.service << 'QMSVC'
[Unit]
Description=QmailToaster SMTP (port 25)
After=network.target qmail-send.service
Wants=qmail-send.service
StartLimitBurst=5
StartLimitIntervalSec=300

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/qmail-smtp-start.sh
Restart=on-failure
RestartSec=15
StandardOutput=append:/var/log/qmail/smtp/current
StandardError=append:/var/log/qmail/smtp/current

[Install]
WantedBy=multi-user.target
QMSVC

cat > /etc/systemd/system/qmail-submission.service << 'QMSVC'
[Unit]
Description=QmailToaster Submission (port 587)
After=network.target qmail-send.service
Wants=qmail-send.service
StartLimitBurst=5
StartLimitIntervalSec=300

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/qmail-submission-start.sh
Restart=on-failure
RestartSec=15
StandardOutput=append:/var/log/qmail/smtp/current
StandardError=append:/var/log/qmail/smtp/current

[Install]
WantedBy=multi-user.target
QMSVC

systemctl daemon-reload
systemctl enable qmail-send qmail-smtp qmail-submission 2>/dev/null || true

chmod 755 /home/vpopmail 2>/dev/null || true

# FTP
dnf install -y pure-ftpd

# Database
dnf install -y mariadb-server

# PHP-FPM (EL10 AppStream ships PHP 8.3). Some AlmaLinux 10 cloud images ship with PHP 8.4
# pre-installed (php8.4-* from @System) instead - its packages Conflict with the unversioned
# php/php-fpm/etc names below (both provide the same virtual capabilities), which aborts this
# install outright under set -e. --allowerasing lets dnf swap the pre-installed 8.4 packages
# out for 8.3 to complete the transaction - this is the version the rest of this installer
# (and the panel's PHP-FPM pool configs) is actually built and tested against.
dnf install -y --allowerasing php php-fpm php-mysqlnd php-xml php-gd php-mbstring

# Utilities
dnf install -y wget curl rsync sshpass logrotate htop unzip tar openssl

# Security tools
# ipset: needed by the Country Blocking feature's firewalld ipsets (usually already present
# alongside firewalld, but not guaranteed on a minimal install).
dnf install -y fail2ban acl ipset 2>/dev/null || warn "Some security packages failed to install"
dnf install -y clamav-update 2>/dev/null || true

# iptables-nft: nftables compat layer (iptables-legacy removed in RHEL 10)
# firewalld uses nftables natively; this provides /usr/sbin/iptables as a fallback
dnf install -y iptables-nft 2>/dev/null || true

# ─── Step 6: Create sysadminhcp User ─────────────────────────────────────────
info "Step 6: Creating sysadminhcp system user..."
if ! id "$SYSADMINHCP_USER" &>/dev/null; then
  useradd -r -s /sbin/nologin -d "$SYSADMINHCP_ROOT" "$SYSADMINHCP_USER"
  info "User $SYSADMINHCP_USER created"
else
  info "User $SYSADMINHCP_USER already exists"
fi

usermod -a -G systemd-journal "$SYSADMINHCP_USER" 2>/dev/null || true
usermod -a -G named "$SYSADMINHCP_USER" 2>/dev/null || true

setfacl -R -m u:$SYSADMINHCP_USER:rX /var/log/httpd/ 2>/dev/null || true
setfacl -R -m u:$SYSADMINHCP_USER:rX /var/log/mariadb/ 2>/dev/null || true
setfacl -m u:$SYSADMINHCP_USER:r /var/log/messages 2>/dev/null || true

# ─── Step 7: Create Directory Structure ─────────────────────────────────────
info "Step 7: Creating directory structure..."
mkdir -p "$SYSADMINHCP_ROOT"/{httpdocs,data,etc,file/template,backup,log,tmp}
mkdir -p "$SYSADMINHCP_ROOT/httpdocs/web-console"
mkdir -p "$SYSADMINHCP_ROOT/etc"
mkdir -p /var/log/sysadminhcp
mkdir -p /var/tmp/sysadminhcp
mkdir -p /var/run/sysadminhcp
mkdir -p /var/cache/sysadminhcp
mkdir -p /var/lib/sysadminhcp/pma-tokens
mkdir -p /etc/httpd/ssl
chmod 711 /etc/httpd/ssl

# ─── Step 8: Install SysAdminHCP Application ───────────────────────────────
info "Step 8: Installing SysAdminHCP application..."
if [[ -f "$REPO_DIR/sysadminhcp" ]]; then
  chmod 755 "$REPO_DIR/sysadminhcp"  # git on Windows/NTFS can't reliably preserve the +x bit
  # Guard against an unresolved Git LFS pointer file (happens if git-lfs wasn't
  # installed before cloning) - a real binary always starts with the ELF magic bytes.
  if ! head -c 4 "$REPO_DIR/sysadminhcp" | grep -q $'\x7fELF'; then
    error "$REPO_DIR/sysadminhcp is not a valid binary (looks like an unresolved Git LFS pointer file). Run 'git lfs pull' in $REPO_DIR and re-run this installer."
  fi
  # ─── Pkg binary install: no TypeScript source, no dist/ tree shipped ─────
  PKG_MODE=1
  info "Pre-built pkg binary found — installing binary-only (no source, no TypeScript build)"
  info "Deploying to $SYSADMINHCP_ROOT/httpdocs/..."
  # Copy-then-rename (not a direct cp overwrite): on an upgrade, the target file is the
  # currently-running binary, and overwriting it in place fails with "Text file busy".
  # mv within the same filesystem is an atomic rename - it repoints the directory entry
  # without touching the still-running process's open file, so this is safe whether or
  # not the service happens to be running at this point in the script.
  cp "$REPO_DIR/sysadminhcp" "$SYSADMINHCP_ROOT/httpdocs/sysadminhcp.new"
  chmod 755 "$SYSADMINHCP_ROOT/httpdocs/sysadminhcp.new"
  mv -f "$SYSADMINHCP_ROOT/httpdocs/sysadminhcp.new" "$SYSADMINHCP_ROOT/httpdocs/sysadminhcp"
  cp -r "$REPO_DIR/theme" "$SYSADMINHCP_ROOT/httpdocs/"
  mkdir -p "$SYSADMINHCP_ROOT/httpdocs/web-console"

  if [[ -f "$REPO_DIR/package.json" ]]; then
    cp "$REPO_DIR/package.json" "$SYSADMINHCP_ROOT/httpdocs/package.json"
    cp "$REPO_DIR/package-lock.json" "$SYSADMINHCP_ROOT/httpdocs/" 2>/dev/null || true
  fi
  cd "$SYSADMINHCP_ROOT/httpdocs"
  info "Installing node-pty (SSH terminal support - not bundled in the binary)..."
  npm install node-pty --no-audit --no-fund 2>/dev/null \
    && info "node-pty compiled OK" \
    || warn "node-pty compilation failed — SSH terminal will be unavailable"
elif [[ -f "$REPO_DIR/package.json" ]]; then
  # ─── Traditional install: build (or deploy pre-built dist/) from TypeScript source ───
  PKG_MODE=0
  cd "$REPO_DIR"
  if [[ -d "$REPO_DIR/dist" && -f "$REPO_DIR/dist/index.js" ]]; then
    info "Pre-built dist/ found — skipping TypeScript compilation"
  elif [[ -d "$REPO_DIR/src" ]]; then
    info "Installing build dependencies..."
    npm install --no-audit --no-fund
    info "Compiling TypeScript..."
    if ! npm run build; then
      error "TypeScript compilation failed! Check the source code for errors."
    fi
    info "Build successful."
  else
    error "No pre-built dist/ and no src/ to build from."
  fi
  info "Deploying to $SYSADMINHCP_ROOT/httpdocs/..."
  cp -r dist "$SYSADMINHCP_ROOT/httpdocs/"
  cp -r theme "$SYSADMINHCP_ROOT/httpdocs/"
  mkdir -p "$SYSADMINHCP_ROOT/httpdocs/web-console"
  cp package.json "$SYSADMINHCP_ROOT/httpdocs/"
  cp package-lock.json "$SYSADMINHCP_ROOT/httpdocs/" 2>/dev/null || true
  cd "$SYSADMINHCP_ROOT/httpdocs"
  info "Installing production dependencies..."
  npm install --production --no-audit --no-fund
  info "Production dependencies installed"

  info "Building native npm modules (node-pty for SSH terminal)..."
  npm install node-pty --no-audit --no-fund 2>/dev/null \
    && info "node-pty compiled OK" \
    || warn "node-pty compilation failed — SSH terminal will be unavailable"
  npm install ws --no-audit --no-fund 2>/dev/null \
    && info "ws installed OK" \
    || warn "ws installation failed — WebSocket terminal will be unavailable"
else
  error "SysAdminHCP source not found at $REPO_DIR (looking for a pkg binary or package.json)"
fi

mkdir -p "$SYSADMINHCP_ROOT/scripts"
if [[ -f "$REPO_DIR/scripts/install-qmail-toaster.sh" ]]; then
  cp "$REPO_DIR/scripts/install-qmail-toaster.sh" "$SYSADMINHCP_ROOT/scripts/install-qmail-toaster.sh"
  chmod 755 "$SYSADMINHCP_ROOT/scripts/install-qmail-toaster.sh"
  info "Copied install-qmail-toaster.sh script"
else
  warn "install-qmail-toaster.sh not found in source - skipping copy"
fi
if [[ -f "$REPO_DIR/scripts/pkg-build.js" ]]; then
  cp "$REPO_DIR/scripts/pkg-build.js" "$SYSADMINHCP_ROOT/scripts/pkg-build.js"
  info "Copied pkg-build.js script (used by deploy.js --pkg)"
fi

# Copy qmail-ai-filter deploy bundle (required by the AI Spam Filter feature,
# Pro license — Admin Portal checks for this exact path before installing)
if [[ -d "$REPO_DIR/deploy/qmail-ai-filter" ]]; then
  mkdir -p "$SYSADMINHCP_ROOT/deploy"
  rm -rf "$SYSADMINHCP_ROOT/deploy/qmail-ai-filter"
  cp -r "$REPO_DIR/deploy/qmail-ai-filter" "$SYSADMINHCP_ROOT/deploy/qmail-ai-filter"
  info "Copied qmail-ai-filter deploy bundle to $SYSADMINHCP_ROOT/deploy/qmail-ai-filter"
else
  warn "deploy/qmail-ai-filter not found in source - AI Spam Filter feature will be unavailable until deployed manually"
fi

# Copy Calendar & Contacts (CalDAV/CardDAV) plugin source + install script — Pro license,
# opt-in addon like the AI Spam Filter above: files are staged here so the panel's own
# "Install" button (DavService.install() -> RadicaleDriver) can run
# install-sysadminhcp-dav.sh on demand, not run automatically during OS setup. Paths match
# httpdocs/ (not $SYSADMINHCP_ROOT directly) because deploy.js's own ongoing sync for this
# feature already targets httpdocs/deploy/dav-plugin + httpdocs/scripts — keeping fresh
# installs and every later `npm run deploy` in agreement about where these files live.
if [[ -d "$REPO_DIR/deploy/dav-plugin" ]]; then
  mkdir -p "$SYSADMINHCP_ROOT/httpdocs/deploy"
  rm -rf "$SYSADMINHCP_ROOT/httpdocs/deploy/dav-plugin"
  cp -r "$REPO_DIR/deploy/dav-plugin" "$SYSADMINHCP_ROOT/httpdocs/deploy/dav-plugin"
  info "Copied Calendar & Contacts (dav-plugin) deploy bundle to $SYSADMINHCP_ROOT/httpdocs/deploy/dav-plugin"
else
  warn "deploy/dav-plugin not found in source - Calendar & Contacts feature will be unavailable until deployed manually"
fi
if [[ -f "$REPO_DIR/deploy/install-sysadminhcp-dav.sh" ]]; then
  mkdir -p "$SYSADMINHCP_ROOT/httpdocs/scripts"
  cp "$REPO_DIR/deploy/install-sysadminhcp-dav.sh" "$SYSADMINHCP_ROOT/httpdocs/scripts/install-sysadminhcp-dav.sh"
  chmod 755 "$SYSADMINHCP_ROOT/httpdocs/scripts/install-sysadminhcp-dav.sh"
  info "Copied install-sysadminhcp-dav.sh script"
else
  warn "deploy/install-sysadminhcp-dav.sh not found in source - Calendar & Contacts feature will be unavailable until deployed manually"
fi

# ─── Step 8.5: Install qmail-queue rate-limit wrapper ───────────────────────
if [[ -f /var/qmail/bin/qmail-queue && -f "$REPO_DIR/deploy/qmail-queue-check.sh" ]]; then
  info "Step 8.5: Installing qmail-queue rate-limit wrapper..."
  if [[ ! -f /var/qmail/bin/qmail-queue.real ]]; then
    cp -p /var/qmail/bin/qmail-queue /var/qmail/bin/qmail-queue.real
    info "Original qmail-queue backed up to qmail-queue.real"
  fi
  cp "$REPO_DIR/deploy/qmail-queue-check.sh" /var/qmail/bin/qmail-queue
  chmod 755 /var/qmail/bin/qmail-queue
  chown root:root /var/qmail/bin/qmail-queue
  restorecon /var/qmail/bin/qmail-queue 2>/dev/null || true
  mkdir -p /var/lib/sysadminhcp/email-rate
  chown -R vpopmail /var/lib/sysadminhcp/email-rate 2>/dev/null || true
  touch /var/qmail/control/sysadminhcp-ratelimits 2>/dev/null || true
  info "qmail-queue wrapper installed — rate limiting active"
else
  info "Step 8.5: qmail not present or wrapper not found — skipping queue wrapper"
fi

# ─── Step 9: Configure Environment ─────────────────────────────────────────
info "Step 9: Configuring environment..."

# This file gets rewritten on every run of this script, including upgrades (autoinstall.sh
# re-runs it, not just fresh installs) — so secrets generated here MUST be reused from any
# existing env file rather than regenerated every time. Regenerating SESSION_SECRET on an
# upgrade invalidates every logged-in session's JWT immediately; regenerating
# SYSADMINHCP_TOTP_ENC_KEY would make every already-enrolled user's stored 2FA secret
# undecryptable. Only a truly fresh install (no existing env file, or no matching line in it)
# gets a newly generated value.
EXISTING_ENV="$SYSADMINHCP_ROOT/etc/sysadminhcp.env"
reuse_or_generate() {
  local var_name="$1"
  local existing_val=""
  if [ -f "$EXISTING_ENV" ]; then
    existing_val=$(grep "^${var_name}=" "$EXISTING_ENV" 2>/dev/null | head -1 | cut -d= -f2-)
  fi
  if [ -n "$existing_val" ]; then
    echo "$existing_val"
  else
    openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p -c 64 | head -c 64
  fi
}
SESSION_SECRET=$(reuse_or_generate SYSADMINHCP_SESSION_SECRET)
COOKIE_SECRET=$(reuse_or_generate SYSADMINHCP_COOKIE_SECRET)
TOTP_ENC_KEY=$(reuse_or_generate SYSADMINHCP_TOTP_ENC_KEY)
MYSQL_ROOT_PASS=$(reuse_or_generate SYSADMINHCP_MYSQL_ROOT_PASS)

cat > "$SYSADMINHCP_ROOT/etc/sysadminhcp.env" << EOF
# SysAdminHCP Environment Configuration
# Generated by install-almalinux10.sh on $(date -u '+%Y-%m-%d %H:%M:%S UTC')
SYSADMINHCP_ROOT=/usr/local/sysadminhcp
SYSADMINHCP_PORT=7778
SYSADMINHCP_SSL_PORT=7777
SYSADMINHCP_HOST=0.0.0.0
SYSADMINHCP_SSL=true
SYSADMINHCP_DB_TYPE=sqljs
SYSADMINHCP_DB_PATH=/usr/local/sysadminhcp/data/sysadminhcp.db
SYSADMINHCP_DB_SYNC=true
SYSADMINHCP_SESSION_SECRET=${SESSION_SECRET}
SYSADMINHCP_SESSION_MAX_AGE=86400000
SYSADMINHCP_COOKIE_SECRET=${COOKIE_SECRET}
SYSADMINHCP_TOTP_ENC_KEY=${TOTP_ENC_KEY}
SYSADMINHCP_CORS_ORIGIN=*
SYSADMINHCP_DEBUG=false
NODE_ENV=production
SYSADMINHCP_DEFAULT_WEB=apache
SYSADMINHCP_DEFAULT_DNS=bind
SYSADMINHCP_DEFAULT_MAIL=qmail
SYSADMINHCP_DEFAULT_FTP=pure-ftpd
SYSADMINHCP_DEFAULT_DB=mysql
SYSADMINHCP_MYSQL_ROOT_PASS=${MYSQL_ROOT_PASS}
SYSADMINHCP_MYSQL_USER=sysadminhcp
SYSADMINHCP_MYSQL_PASS=${KLOXOJRA_DB_PASS}
SYSADMINHCP_MYSQL_HOST=localhost
EOF

# ─── Step 10: Set Permissions ───────────────────────────────────────────────
info "Step 10: Setting permissions..."

mkdir -p "$SYSADMINHCP_ROOT"/{httpdocs,data,etc,file/template,file/ssl,backup,log,tmp}
mkdir -p "$SYSADMINHCP_ROOT/httpdocs/web-console"
mkdir -p /var/log/sysadminhcp /var/tmp/sysadminhcp /var/run/sysadminhcp /var/cache/sysadminhcp /var/backup/sysadminhcp

chown -R $SYSADMINHCP_USER:$SYSADMINHCP_GROUP "$SYSADMINHCP_ROOT"
chown -R $SYSADMINHCP_USER:$SYSADMINHCP_GROUP /var/log/sysadminhcp
chown -R $SYSADMINHCP_USER:$SYSADMINHCP_GROUP /var/tmp/sysadminhcp
chown -R $SYSADMINHCP_USER:$SYSADMINHCP_GROUP /var/run/sysadminhcp
chown -R $SYSADMINHCP_USER:$SYSADMINHCP_GROUP /var/cache/sysadminhcp
chown -R $SYSADMINHCP_USER:$SYSADMINHCP_GROUP /var/backup
chown -R $SYSADMINHCP_USER:$SYSADMINHCP_GROUP /var/lib/sysadminhcp
chmod 750 "$SYSADMINHCP_ROOT/etc/sysadminhcp.env"

# Configure sudoers
rm -f /etc/sudoers.d/sysadminhcp-logs
cat > /etc/sudoers.d/sysadminhcp << 'SUDOEOF'
sysadminhcp ALL=(root) NOPASSWD: /usr/bin/tail, /usr/bin/cat, /usr/bin/touch, /usr/bin/journalctl, /usr/sbin/tail, /usr/local/sysadminhcp/scripts/install-qmail-toaster.sh, /usr/local/sysadminhcp/httpdocs/scripts/install-sysadminhcp-dav.sh, /usr/bin/cp, /usr/bin/mv, /usr/bin/chmod, /usr/bin/chown, /usr/bin/find, /usr/bin/mkdir, /usr/bin/rm, /usr/bin/systemctl, /usr/bin/tcprules, /usr/sbin/useradd, /usr/sbin/groupadd, /usr/bin/id, /usr/sbin/usermod, /home/vpopmail/bin/vadddomain, /home/vpopmail/bin/vdeldomain, /home/vpopmail/bin/vadduser, /home/vpopmail/bin/vdeluser, /home/vpopmail/bin/vchangepw, /home/vpopmail/bin/vpasswd, /home/vpopmail/bin/vsetuserquota, /home/vpopmail/bin/vmoduser, /home/vpopmail/bin/vmoddomlimits, /home/vpopmail/bin/vdominfo, /home/vpopmail/bin/vuserinfo, /usr/bin/dnf, /usr/bin/rpm, /usr/bin/setfacl, /usr/sbin/restorecon, /usr/bin/firewall-cmd, /usr/sbin/ipset, /usr/sbin/iptables, /sbin/iptables, /usr/bin/freshclam, /usr/bin/fail2ban-client, /bin/bash, /usr/bin/bash, /root/.acme.sh/acme.sh, /usr/bin/openssl
SUDOEOF
chmod 440 /etc/sudoers.d/sysadminhcp
visudo -c && info "sudoers validated OK" || warn "sudoers validation failed — check /etc/sudoers.d/sysadminhcp"

# Install goaccess and create daily stats cron (needs EPEL; /usr may be read-only)
mount -o remount,rw /usr 2>/dev/null || true
GOACCESS_LOG=$(dnf install -y epel-release 2>&1; dnf install -y goaccess 2>&1) || true
mount -o remount,ro /usr 2>/dev/null || true
if command -v goaccess >/dev/null 2>&1; then
  info "GoAccess installed OK"
else
  warn "GoAccess install failed — install it later from the panel (Web Server page > Install GoAccess button). Details:"
  echo "$GOACCESS_LOG" | tail -10
fi
cat > /etc/cron.daily/sysadminhcp-stats << 'CRONEOF'
#!/bin/bash
# Daily web stats for SysAdminHCP domains
for log in /home/*/*/stats/access.log; do
  [ -f "$log" ] || continue
  domaindir=$(dirname "$(dirname "$log")")
  domain=$(basename "$domaindir")
  client=$(basename "$(dirname "$domaindir")")
  outdir="$domaindir/public_html/webstats"
  mkdir -p "$outdir"
  chown "$client":apache "$outdir" 2>/dev/null || true
  chmod 755 "$outdir"
  goaccess "$log" -o "$outdir/index.html" --log-format=COMBINED --no-global-config >/dev/null 2>&1 || true
done
CRONEOF
chmod 755 /etc/cron.daily/sysadminhcp-stats

# Generate self-signed SSL certificate
SSL_DIR="$SYSADMINHCP_ROOT/file/ssl"
if [[ ! -f "$SSL_DIR/cert.pem" || ! -f "$SSL_DIR/key.pem" ]]; then
  info "Generating self-signed SSL certificate (10 years)..."
  openssl req -x509 -newkey rsa:2048 \
    -keyout "$SSL_DIR/key.pem" \
    -out "$SSL_DIR/cert.pem" \
    -days 3650 -nodes \
    -subj "/C=US/ST=Server/L=Server/O=SysAdminHCP/CN=localhost" 2>/dev/null
  chown $SYSADMINHCP_USER:$SYSADMINHCP_GROUP "$SSL_DIR/key.pem" "$SSL_DIR/cert.pem"
  chmod 640 "$SSL_DIR/key.pem" "$SSL_DIR/cert.pem"
  info "SSL certificate created at $SSL_DIR"
else
  info "SSL certificate already exists at $SSL_DIR — skipping generation"
fi

setfacl -m u:$SYSADMINHCP_USER:rw /etc/named.conf 2>/dev/null || true
setfacl -R -m u:$SYSADMINHCP_USER:rwx /var/named/ 2>/dev/null || true

mkdir -p /var/named/slaves
chown named:named /var/named/slaves
chmod 770 /var/named/slaves
info "Created /var/named/slaves/ for DNS cluster slave zones"

info "Setting File Manager ACLs on existing client home directories..."
for homedir in /home/*/; do
  owner=$(stat -c '%U' "$homedir" 2>/dev/null)
  if id "$owner" &>/dev/null && [[ "$owner" != "root" && "$owner" != "$SYSADMINHCP_USER" ]]; then
    setfacl -m u:$SYSADMINHCP_USER:rwx "$homedir" 2>/dev/null || true
    setfacl -d -m u:$SYSADMINHCP_USER:rwX "$homedir" 2>/dev/null || true
    info "  ACL set: $homedir (owner: $owner)"
  fi
done

# ─── Step 11: Install Systemd Service ──────────────────────────────────────
info "Step 11: Installing systemd service..."

if [[ $WSL_MODE -eq 1 ]]; then
  cat > /etc/systemd/system/sysadminhcp.service << 'SVCEOF'
[Unit]
Description=SysAdminHCP Control Panel (Node.js)
After=network.target mariadb.service httpd.service named.service
Wants=mariadb.service

[Service]
Type=simple
User=sysadminhcp
Group=sysadminhcp
WorkingDirectory=/usr/local/sysadminhcp/httpdocs
ExecStart=/usr/bin/node /usr/local/sysadminhcp/httpdocs/dist/index.js
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=sysadminhcp

NoNewPrivileges=false
PrivateTmp=true
ProtectHome=no

Environment=NODE_ENV=production
EnvironmentFile=-/usr/local/sysadminhcp/etc/sysadminhcp.env

LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
SVCEOF
else
  cat > /etc/systemd/system/sysadminhcp.service << 'SVCEOF'
[Unit]
Description=SysAdminHCP Control Panel (Node.js)
After=network.target mariadb.service httpd.service named.service
Wants=mariadb.service

[Service]
Type=simple
User=sysadminhcp
Group=sysadminhcp
WorkingDirectory=/usr/local/sysadminhcp/httpdocs
ExecStart=/usr/bin/node /usr/local/sysadminhcp/httpdocs/dist/index.js
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=sysadminhcp

NoNewPrivileges=false
PrivateTmp=true
# ProtectSystem is off (not 'yes'): every "Install X" panel feature shells out to the
# package manager at runtime (PHP versions, ClamAV, Fail2ban, phpMyAdmin, GoAccess,
# AI Agent/Redis, etc.), which needs to write to /usr. ProtectSystem=yes mounts /usr
# read-only for this unit and ALL its children — sudo does not escape a mount namespace
# restriction, and empirically ReadWritePaths=/usr does NOT override it on this systemd
# version, so ProtectSystem must be disabled outright rather than selectively overridden.
ProtectSystem=no
ProtectHome=no
ReadWritePaths=/usr/local/sysadminhcp/data /usr/local/sysadminhcp/httpdocs /home

RuntimeDirectory=sysadminhcp
CacheDirectory=sysadminhcp
LogsDirectory=sysadminhcp

Environment=NODE_ENV=production
EnvironmentFile=-/usr/local/sysadminhcp/etc/sysadminhcp.env

LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
SVCEOF
fi

# Pkg binary installs run the compiled binary directly instead of
# `node dist/index.js`, and need NODE_PATH so the externally-installed
# node-pty resolves at runtime.
if [[ $PKG_MODE -eq 1 ]]; then
  sed -i \
    -e 's|^ExecStart=.*|ExecStart=/usr/local/sysadminhcp/httpdocs/sysadminhcp|' \
    -e '/^Environment=NODE_ENV=production/a Environment=NODE_PATH=/usr/local/sysadminhcp/httpdocs/node_modules' \
    /etc/systemd/system/sysadminhcp.service
  info "Configured systemd unit to run the pkg binary directly"
fi

systemctl daemon-reload
systemctl enable "$SYSADMINHCP_SERVICE"

cat > /etc/logrotate.d/sysadminhcp-acl << 'LREOF'
/var/log/httpd/error_log {
    postrotate
        setfacl -R -m u:sysadminhcp:rX /var/log/httpd/ 2>/dev/null || true
    endscript
}
/var/log/mariadb/mariadb.log {
    postrotate
        setfacl -R -m u:sysadminhcp:rX /var/log/mariadb/ 2>/dev/null || true
    endscript
}
/var/log/messages {
    postrotate
        setfacl -m u:sysadminhcp:r /var/log/messages 2>/dev/null || true
    endscript
}
LREOF
chmod 644 /etc/logrotate.d/sysadminhcp-acl

# ─── Step 12: Configure Firewall ───────────────────────────────────────────
info "Step 12: Configuring firewall..."
if [[ $WSL_MODE -eq 1 ]]; then
  info "WSL detected: skipping firewall configuration (Windows handles networking)"
elif command -v firewall-cmd &>/dev/null; then
  # firewalld ships installed+enabled on some AlmaLinux 10 cloud images but is never actually
  # started on first boot (confirmed live: `systemctl is-enabled` said enabled, `is-active` said
  # inactive, with no prior start/crash in the journal at all - it just never ran). The old check
  # here only tested is-active and silently skipped the whole firewall setup if it was down,
  # which also meant Intrusion Detection's IP-block feature (firewall-cmd --zone=drop) failed
  # with "FirewallD is not running" for as long as the panel's own reload/`fix-firewall` step
  # never explicitly starts the service either.
  if ! systemctl is-active firewalld &>/dev/null; then
    systemctl enable --now firewalld 2>/dev/null || true
  fi
  if systemctl is-active firewalld &>/dev/null; then
    firewall-cmd --permanent --add-port=7778/tcp
    firewall-cmd --permanent --add-port=7777/tcp
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --permanent --add-service=dns
    firewall-cmd --permanent --add-service=ftp
    firewall-cmd --permanent --add-port=30000-31000/tcp
    firewall-cmd --reload
    info "Firewall rules added for ports 7778, 7777, 80, 443, 21, 30000-31000"
  else
    warn "firewalld could not be started. Skipping firewall configuration."
  fi
else
  warn "firewall-cmd not found. Skipping firewall configuration."
fi

# ─── Step 12.5: Configure Security Tools ────────────────────────────────────
info "Step 12.5: Configuring security tools..."

# ── SSH drop-in config support ─────────────────────────────────────────────
# The panel's SSH Config page writes to /etc/ssh/sshd_config.d/00-sysadminhcp.conf.
# Unlike Debian/Ubuntu's stock sshd_config (which includes sshd_config.d/*.conf by
# default), AlmaLinux/RHEL's stock config has no such Include line — without it,
# anything the panel writes to that drop-in is silently ignored, no matter how
# many times sshd is restarted.
mkdir -p /etc/ssh/sshd_config.d
if ! grep -q '^Include /etc/ssh/sshd_config.d/\*.conf' /etc/ssh/sshd_config; then
  sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
  info "Added sshd_config.d Include directive (required for panel SSH Config changes to take effect)"
fi

if command -v fail2ban-client &>/dev/null; then
  if [[ ! -f /etc/fail2ban/jail.local ]]; then
    cat > /etc/fail2ban/jail.local << 'F2BEOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = auto
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s

[httpd-auth]
enabled  = true
filter   = apache-auth
port     = http,https
logpath  = %(apache_error_log)s

[pure-ftpd]
enabled  = true
port     = ftp,ftp-data,ftps,ftps-data
logpath  = %(pureftpd_log)s
F2BEOF
    info "Fail2ban jail.local created"
  fi
  systemctl enable fail2ban 2>/dev/null || true
fi

if command -v freshclam &>/dev/null; then
  if [[ ! -f /var/lib/clamav/main.cvd ]] && [[ ! -f /var/lib/clamav/main.cld ]]; then
    freshclam 2>/dev/null && info "ClamAV DB updated" || warn "ClamAV DB update failed — run freshclam manually"
  fi
  systemctl enable clamav-freshclam 2>/dev/null || true
fi

# ─── Step 13: Configure SELinux ────────────────────────────────────────────
info "Step 13: Configuring SELinux..."
if command -v getenforce &>/dev/null && [[ "$(getenforce)" != "Disabled" ]]; then
  if [[ $WSL_MODE -ne 1 ]]; then
    setsebool -P httpd_can_network_connect 1
    semanage port -a -t http_port_t -p tcp 7778 2>/dev/null || true
    semanage port -a -t http_port_t -p tcp 7777 2>/dev/null || true
    setsebool -P httpd_enable_homedirs on 2>/dev/null || true
    setsebool -P httpd_read_user_content on 2>/dev/null || true
    info "SELinux policies configured"
  fi
else
  info "SELinux is disabled. Skipping policy configuration."
fi

# ─── Step 14: Start Services ───────────────────────────────────────────────
info "Step 14: Starting services..."

systemctl enable mariadb
systemctl start mariadb

# MariaDB bind-address — detect config file (EL10 may use mariadb-server.cnf)
info "Binding MariaDB to 127.0.0.1 (localhost only)..."
MARIADB_CNF=""
for f in /etc/my.cnf.d/mariadb-server.cnf /etc/my.cnf.d/server.cnf /etc/my.cnf.d/openstack.cnf; do
  [[ -f "$f" ]] && MARIADB_CNF="$f" && break
done
if [[ -n "$MARIADB_CNF" ]]; then
  if ! grep -q '^bind-address' "$MARIADB_CNF"; then
    sed -i '/\[mysqld\]/a bind-address=127.0.0.1' "$MARIADB_CNF"
    systemctl restart mariadb
    info "MariaDB bound to 127.0.0.1 in $MARIADB_CNF"
  else
    info "MariaDB already bound to localhost"
  fi
else
  cat > /etc/my.cnf.d/server.cnf << 'MYSQLEOF'
[mysqld]
bind-address=127.0.0.1
MYSQLEOF
  systemctl restart mariadb
  info "Created /etc/my.cnf.d/server.cnf with bind-address=127.0.0.1"
fi

if [[ $FRESH_INSTALL -eq 1 ]]; then
  for i in $(seq 1 30); do
    if mysqladmin ping -u root 2>/dev/null; then break; fi
    sleep 1
  done

  if mysqladmin ping -u root 2>/dev/null; then
    info "Securing MariaDB installation..."
    mysql -u root << EOSQL 2>/dev/null || warn "MariaDB secure install partially failed"
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${MYSQL_ROOT_PASS}');
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOSQL
    echo -n "${MYSQL_ROOT_PASS}" > /usr/local/sysadminhcp/etc/mysql-root-password
    chown sysadminhcp:sysadminhcp /usr/local/sysadminhcp/etc/mysql-root-password
    chmod 600 /usr/local/sysadminhcp/etc/mysql-root-password
    info "MariaDB root password randomly generated and saved to /usr/local/sysadminhcp/etc/mysql-root-password"
  else
    warn "MariaDB not responding after 30s - skipping secure installation"
  fi
fi

# AlmaLinux 10's stock httpd.service ships with ProtectHome=read-only, which makes /home
# appear read-only to httpd inside its own systemd sandbox regardless of real filesystem
# permissions. SysAdminHCP puts every domain's docroot AND per-vhost error/access logs under
# /home/<client>/<domain>/, so this breaks Apache the moment any vhost's log path is opened -
# confirmed live: httpd started fine at install time (before any per-vhost log had been
# touched), then failed outright on every subsequent restart once a domain's error.log open
# was attempted, with a misleading "(30)Read-only file system" error despite the disk itself
# being writable. ReadWritePaths=/home alone was NOT sufficient to override ProtectHome here -
# only explicitly disabling ProtectHome for this unit worked.
mkdir -p /etc/systemd/system/httpd.service.d
cat > /etc/systemd/system/httpd.service.d/sysadminhcp-readwrite-home.conf << 'HTTPDOVERRIDE'
[Service]
ProtectHome=false
ReadWritePaths=/home
HTTPDOVERRIDE
systemctl daemon-reload

systemctl enable httpd 2>/dev/null || true
systemctl start httpd 2>/dev/null || warn "Apache failed to start"

info "Configuring BIND to listen on public interface..."
if [[ -f /etc/named.conf ]]; then
  sed -i 's/listen-on port 53 { 127\.0\.0\.1; };/listen-on port 53 { any; };/' /etc/named.conf
  sed -i 's/listen-on-v6 port 53 { ::1; };/listen-on-v6 port 53 { any; };/' /etc/named.conf
  sed -i 's/allow-query[[:space:]]*{[[:space:]]*localhost;[[:space:]]*};/allow-query     { any; };/' /etc/named.conf
  named-checkconf && info "named.conf updated (listen-on any, allow-query any)" || warn "named.conf validation failed"
fi
systemctl enable named 2>/dev/null || true
systemctl start named 2>/dev/null || warn "BIND failed to start"

# Point system DNS resolution at our own local recursive BIND instead of the cloud
# provider's shared resolver. Real-world failure mode this avoids (hit live on a fresh
# install): shared provider resolvers get rate-limited by Spamhaus's free public DNSBL
# mirror once enough OTHER customers on that same resolver query it ("excess volume"),
# and once that happens spamdyke's own RBL check misreads Spamhaus's rate-limit response
# as "this connecting IP is blacklisted" — rejecting ALL inbound mail from every sender,
# server-wide, for a reason that has nothing to do with actual sender reputation. Public
# resolvers (1.1.1.1/8.8.8.8) don't fix this either — Spamhaus's free mirror separately
# refuses queries it recognizes as coming from a known public resolver. BIND already does
# full recursion for 127.0.0.1 (the allow-query/listen-on changes above), so this is safe
# as long as named is actually running. 1.1.1.1 is kept as a second nameserver purely so
# DNS still works at all if named ever crashes — it is never queried for anything as long
# as 127.0.0.1 answers, so it never reintroduces the shared/public-resolver problem.
info "Pointing system DNS resolution at local BIND (avoids shared-resolver Spamhaus rate-limiting)..."
if command -v nmcli &>/dev/null && systemctl is-active --quiet NetworkManager; then
  NM_CONN=$(nmcli -t -f NAME con show --active | head -1)
  if [[ -n "$NM_CONN" ]]; then
    nmcli con mod "$NM_CONN" ipv4.dns "127.0.0.1 1.1.1.1" 2>/dev/null
    nmcli con mod "$NM_CONN" ipv4.ignore-auto-dns yes 2>/dev/null
    nmcli con up "$NM_CONN" &>/dev/null && info "DNS resolver set via NetworkManager (persists across reboots)" \
      || warn "NetworkManager reapply failed - DNS resolver change may not have taken effect"
  else
    warn "NetworkManager active but no active connection found - skipping persistent DNS resolver setup"
  fi
else
  cat > /etc/resolv.conf << 'RESOLVCONF'
; Managed by SysAdminHCP installer - local recursive BIND avoids shared-resolver Spamhaus rate-limiting
nameserver 127.0.0.1
nameserver 1.1.1.1
RESOLVCONF
  warn "NetworkManager not active - wrote /etc/resolv.conf directly (may not survive a future cloud-init network reinit)"
fi

# Pure-FTPd
info "Configuring Pure-FTPd MySQL authentication..."
if command -v mysql &>/dev/null && systemctl is-active --quiet mariadb; then
  mysql -u root -p"${MYSQL_ROOT_PASS}" <<FTPEOSQL 2>/dev/null || warn "pureftpd database setup failed"
CREATE DATABASE IF NOT EXISTS pureftpd;
USE pureftpd;
CREATE TABLE IF NOT EXISTS users (
  User varchar(64) NOT NULL,
  Password varchar(128) NOT NULL,
  Uid int NOT NULL DEFAULT 48,
  Gid int NOT NULL DEFAULT 48,
  Dir varchar(255) NOT NULL DEFAULT '/home',
  QuotaSize int NOT NULL DEFAULT 0,
  QuotaFiles int NOT NULL DEFAULT 0,
  PRIMARY KEY (User)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
FLUSH PRIVILEGES;
FTPEOSQL
fi

mkdir -p /etc/pure-ftpd
cat > /etc/pure-ftpd/pureftpd-mysql.conf << FTPMYCNF
MYSQLSocket      /var/lib/mysql/mysql.sock
MYSQLUser        root
MYSQLPassword    ${MYSQL_ROOT_PASS}
MYSQLDatabase    pureftpd
MYSQLCrypt       crypt
MYSQLGetPW       SELECT Password FROM users WHERE User='\L'
MYSQLGetUID      SELECT Uid FROM users WHERE User='\L'
MYSQLGetGID      SELECT Gid FROM users WHERE User='\L'
MYSQLGetDir      SELECT Dir FROM users WHERE User='\L'
FTPMYCNF
chmod 600 /etc/pure-ftpd/pureftpd-mysql.conf

FTPCONF=/etc/pure-ftpd/pure-ftpd.conf
if [[ -f "$FTPCONF" ]]; then
  sed -i '/^[#[:space:]]*PAMAuthentication/d' "$FTPCONF"
  sed -i '/^[#[:space:]]*MySQLConfigFile/d' "$FTPCONF"
  sed -i '/^[#[:space:]]*PassivePortRange/d' "$FTPCONF"
  printf '\nPAMAuthentication no\nMySQLConfigFile /etc/pure-ftpd/pureftpd-mysql.conf\nPassivePortRange 30000 31000\n' >> "$FTPCONF"
else
  cat > "$FTPCONF" << 'MINFTPCONF'
PAMAuthentication no
MySQLConfigFile /etc/pure-ftpd/pureftpd-mysql.conf
PassivePortRange 30000 31000
MINFTPCONF
fi
systemctl enable pure-ftpd 2>/dev/null || true
systemctl start pure-ftpd 2>/dev/null || warn "Pure-FTPd failed to start"

systemctl enable php-fpm 2>/dev/null || true
systemctl start php-fpm 2>/dev/null || warn "PHP-FPM failed to start"

systemctl start qmail-send 2>/dev/null || warn "qmail-send failed to start"
sleep 2
systemctl start qmail-smtp qmail-submission 2>/dev/null || warn "qmail SMTP failed to start"
sleep 2
systemctl enable dovecot 2>/dev/null || true
systemctl start dovecot 2>/dev/null || warn "Dovecot failed to start"
systemctl enable spamassassin 2>/dev/null || true
systemctl start spamassassin 2>/dev/null || warn "SpamAssassin failed to start"
systemctl enable clamd@scan 2>/dev/null || true
systemctl start clamd@scan 2>/dev/null || warn "ClamAV (clamd@scan) failed to start"
systemctl enable clamav-freshclam 2>/dev/null || true
systemctl start clamav-freshclam 2>/dev/null || warn "ClamAV freshclam failed to start"
systemctl enable fail2ban 2>/dev/null || true
systemctl start fail2ban 2>/dev/null || warn "Fail2ban failed to start"

# vpopmail database
if command -v mysql &>/dev/null && systemctl is-active --quiet mariadb; then
  # NOT "rpm -q vpopmail" — vpopmail is source-built now (see the notqmail/vpopmail build
  # block above), not RPM-installed, so that check would never be true and this whole block
  # would silently never run. Confirmed live: this exact bug shipped a "successful" install
  # where vpopmail's binaries existed and linked correctly but had no real database, MySQL
  # user, or vpopmail.mysql config at all — vadduser/vadddomain failed with "no
  # authentication database connection" despite every service reporting healthy.
  if [[ -x /home/vpopmail/bin/vadddomain ]]; then
    info "Setting up vpopmail database in MariaDB..."
    VPOPMAIL_DB_PASS=$(openssl rand -hex 8 2>/dev/null || echo "vpopmail123")
    mysql -u root -p"${MYSQL_ROOT_PASS}" <<EOSQL 2>/dev/null || warn "vpopmail database setup failed"
CREATE DATABASE IF NOT EXISTS vpopmail;
CREATE USER IF NOT EXISTS 'vpopmail'@'localhost' IDENTIFIED BY '${VPOPMAIL_DB_PASS}';
ALTER USER 'vpopmail'@'localhost' IDENTIFIED BY '${VPOPMAIL_DB_PASS}';
GRANT ALL PRIVILEGES ON vpopmail.* TO 'vpopmail'@'localhost';
FLUSH PRIVILEGES;
EOSQL
    mysql -u root -p"${MYSQL_ROOT_PASS}" vpopmail <<VPOPTABLES 2>/dev/null || warn "vpopmail table creation failed"
CREATE TABLE IF NOT EXISTS vpopmail (
  pw_name varchar(32) NOT NULL DEFAULT '',
  pw_domain varchar(96) NOT NULL DEFAULT '',
  pw_passwd varchar(128) NOT NULL DEFAULT '',
  pw_uid smallint(6) NOT NULL DEFAULT 0,
  pw_gid smallint(6) NOT NULL DEFAULT 0,
  pw_gecos varchar(48) NOT NULL DEFAULT '',
  pw_dir varchar(160) NOT NULL DEFAULT '',
  pw_shell varchar(20) NOT NULL DEFAULT 'NOQUOTA',
  pw_quota varchar(20) NOT NULL DEFAULT 'NOQUOTA',
  pw_clear_passwd varchar(16) NOT NULL DEFAULT '',
  PRIMARY KEY (pw_name, pw_domain)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
CREATE TABLE IF NOT EXISTS lastauth (
  user varchar(32) NOT NULL DEFAULT '',
  domain varchar(96) NOT NULL DEFAULT '',
  remote_ip varchar(16) NOT NULL DEFAULT '',
  timestamp int(11) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (user, domain)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
VPOPTABLES
    # ALTER USER alongside CREATE USER IF NOT EXISTS (matching the vpopmail user block above) —
    # without it, a re-run whose extracted $KLOXOJRA_DB_PASS ever drifts from what MySQL actually
    # has on file for this user (e.g. dovecot-sql.conf.ext restored from a snapshot, or any other
    # source of skew) leaves MySQL's real password stuck at whatever it was, silently breaking
    # Dovecot/Pure-FTPd MySQL auth for every mailbox on the server until fixed by hand.
    mysql -u root -p"${MYSQL_ROOT_PASS}" <<EOSQL2 2>/dev/null || warn "sysadminhcp database user setup failed"
CREATE DATABASE IF NOT EXISTS sysadminhcp;
CREATE USER IF NOT EXISTS 'sysadminhcp'@'localhost' IDENTIFIED BY '${KLOXOJRA_DB_PASS}';
ALTER USER 'sysadminhcp'@'localhost' IDENTIFIED BY '${KLOXOJRA_DB_PASS}';
GRANT ALL PRIVILEGES ON sysadminhcp.* TO 'sysadminhcp'@'localhost';
GRANT SELECT ON vpopmail.* TO 'sysadminhcp'@'localhost';
FLUSH PRIVILEGES;
EOSQL2
    mkdir -p /home/vpopmail/etc
    echo "localhost|0|vpopmail|${VPOPMAIL_DB_PASS}|vpopmail" > /home/vpopmail/etc/vpopmail.mysql
    chown vpopmail:vchkpw /home/vpopmail/etc/vpopmail.mysql 2>/dev/null || true
    chmod 640 /home/vpopmail/etc/vpopmail.mysql 2>/dev/null || true
  fi

  cat > "$SYSADMINHCP_ROOT/.my.cnf" << MYCNF
[client]
user=sysadminhcp
password=${KLOXOJRA_DB_PASS}
host=localhost
MYCNF
  chown sysadminhcp:sysadminhcp "$SYSADMINHCP_ROOT/.my.cnf"
  chmod 600 "$SYSADMINHCP_ROOT/.my.cnf"

  if [ ! -f /root/.my.cnf ]; then
    cat > /root/.my.cnf << ROOTMYCNF
[client]
user=root
password=${MYSQL_ROOT_PASS}
ROOTMYCNF
    chmod 600 /root/.my.cnf
  fi
fi

# ─── Step 14.5: Install phpMyAdmin ─────────────────────────────────────────
info "Step 14.5: Setting up phpMyAdmin (optional)..."
dnf install -y php-mysqlnd 2>/dev/null || true
if ! dnf list installed phpmyadmin &>/dev/null 2>&1; then
  dnf install -y phpmyadmin 2>/dev/null || warn "phpMyAdmin installation failed — install manually with: dnf install -y phpmyadmin"
fi

mkdir -p /var/lib/sysadminhcp/pma-tokens
chown sysadminhcp:sysadminhcp /var/lib/sysadminhcp/pma-tokens
chmod 755 /var/lib/sysadminhcp/pma-tokens

# Detect phpMyAdmin install path (EL9: /usr/share/phpMyAdmin, EL10: may be lowercase)
PMA_DIR=""
for d in /usr/share/phpMyAdmin /usr/share/phpmyadmin; do
  [[ -d "$d" ]] && PMA_DIR="$d" && break
done

if [[ -n "$PMA_DIR" ]]; then
  mkdir -p "$PMA_DIR/sysadminhcp-signon"

  if [[ -f "$REPO_DIR/pma-signon/signon.php" ]]; then
    cp "$REPO_DIR/pma-signon/signon.php" "$PMA_DIR/sysadminhcp-signon/signon.php"
    chown -R apache:apache "$PMA_DIR/sysadminhcp-signon"
    info "phpMyAdmin signon script deployed to $PMA_DIR"
  else
    warn "pma-signon/signon.php not found — phpMyAdmin SSO will not work until deployed manually"
  fi

  if [[ -f "$REPO_DIR/pma-signon/config.inc.php" ]]; then
    PMA_CONF_DIR=""
    for d in /etc/phpMyAdmin /etc/phpmyadmin; do
      [[ -d "$d" ]] && PMA_CONF_DIR="$d" && break
    done
    if [[ -n "$PMA_CONF_DIR" ]]; then
      cp "$REPO_DIR/pma-signon/config.inc.php" "$PMA_CONF_DIR/config.inc.php"
      # Give this install its own blowfish_secret rather than the placeholder in source control.
      PMA_BLOWFISH_SECRET=$(openssl rand -hex 16)
      sed -i "s/__PMA_BLOWFISH_SECRET__/${PMA_BLOWFISH_SECRET}/" "$PMA_CONF_DIR/config.inc.php"
      info "phpMyAdmin config deployed (signon auth mode, random blowfish secret)"
    else
      warn "phpMyAdmin config directory not found — copy pma-signon/config.inc.php manually"
    fi
  fi

  cat > /etc/httpd/conf.d/sysadminhcp-pma-signon.conf << APACHEEOF
# SysAdminHCP phpMyAdmin SSO endpoint
Alias /pma-signon ${PMA_DIR}/sysadminhcp-signon

<Directory ${PMA_DIR}/sysadminhcp-signon>
    Require all granted
    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php-fpm/www.sock|fcgi://localhost"
    </FilesMatch>
</Directory>
APACHEEOF

  cat > /etc/httpd/conf.d/000-default.conf << 'APACHEEOF'
<VirtualHost *:80>
    ServerName 127.0.0.1
    DocumentRoot "/var/www/html"
    <Directory "/var/www/html">
        Require all granted
    </Directory>
</VirtualHost>
APACHEEOF

  setsebool -P httpd_can_network_connect_db on 2>/dev/null || true
  systemctl restart httpd 2>/dev/null || true
  info "phpMyAdmin SSO configured"
else
  warn "phpMyAdmin not found — skipping SSO setup"
fi

# ─── Step 14.6: Install RainLoop Webmail ──────────────────────────────────
info "Step 14.6: Installing RainLoop webmail..."

RAINLOOP_DIR="/var/www/rainloop"
if [[ -f "$RAINLOOP_DIR/index.php" ]]; then
  info "RainLoop already installed at $RAINLOOP_DIR ��� skipping"
else
  mkdir -p "$RAINLOOP_DIR/data/_data_/_default_/configs"
  mkdir -p "$RAINLOOP_DIR/data/_data_/_default_/domains"
  mkdir -p "$RAINLOOP_DIR/data/_data_/_default_/storage"

  curl -sL https://www.rainloop.net/repository/webmail/rainloop-latest.zip -o /tmp/rainloop.zip
  if [[ -f /tmp/rainloop.zip ]]; then
    unzip -o /tmp/rainloop.zip -d "$RAINLOOP_DIR" 2>/dev/null || warn "RainLoop unzip failed"
    rm -f /tmp/rainloop.zip
  else
    warn "RainLoop download failed — install manually from https://www.rainloop.net/"
  fi

  chown -R apache:apache "$RAINLOOP_DIR"
  chmod -R 755 "$RAINLOOP_DIR"
  chmod -R 777 "$RAINLOOP_DIR/data"

  cat > "$RAINLOOP_DIR/data/_data_/_default_/configs/application.ini" << 'RLEOF'
; SysAdminHCP RainLoop Webmail Configuration

[webmail]
title = "SysAdminHCP Webmail"
loading_description = "SysAdminHCP"

[defaults]
language = "en"
theme = "Default"

[security]
allow_admin_panel = On
admin_panel_host = ""

[contacts]
enable = On

[logs]
enable = On
filename = "log.txt"

[debug]
enable = Off

[version]
current_version = "1.17.0"
RLEOF

  cat > "$RAINLOOP_DIR/data/_data_/_default_/domains/default.json" << 'DOMEOF'
{
  "imap": { "host": "localhost", "port": 143, "secure": false },
  "smtp": { "host": "localhost", "port": 25, "secure": false },
  "sieve": { "host": "localhost", "port": 4190, "secure": false }
}
DOMEOF

  chown -R apache:apache "$RAINLOOP_DIR/data"
  chcon -R -t httpd_sys_content_t "$RAINLOOP_DIR" 2>/dev/null || true
  chcon -R -t httpd_sys_rw_content_t "$RAINLOOP_DIR/data" 2>/dev/null || true
  info "RainLoop configured"
fi

cat > /etc/httpd/conf.d/webmail.conf << 'WMEOF'
# SysAdminHCP Webmail (RainLoop)
<VirtualHost *:80>
    ServerName webmail
    ServerAlias webmail.*

    DocumentRoot "/var/www/rainloop"
    <Directory "/var/www/rainloop">
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php-fpm/webmail.sock|fcgi://localhost"
    </FilesMatch>

    ErrorLog /var/log/httpd/webmail_error.log
    CustomLog /var/log/httpd/webmail_access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName webmail
    ServerAlias webmail.*

    DocumentRoot "/var/www/rainloop"
    <Directory "/var/www/rainloop">
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    SSLEngine on
    SSLCertificateFile /etc/pki/tls/certs/localhost.crt
    SSLCertificateKeyFile /etc/pki/tls/private/localhost.key

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php-fpm/webmail.sock|fcgi://localhost"
    </FilesMatch>

    ErrorLog /var/log/httpd/webmail_ssl_error.log
    CustomLog /var/log/httpd/webmail_ssl_access.log combined
</VirtualHost>
WMEOF

mkdir -p /var/lib/php/session/webmail
chown -R apache:apache /var/lib/php/session/webmail
chmod 1733 /var/lib/php/session/webmail

cat > /etc/php-fpm.d/webmail.conf << 'FPMEOF'
; SysAdminHCP Webmail PHP-FPM Pool
[webmail]
user = apache
group = apache

listen = /run/php-fpm/webmail.sock
listen.owner = apache
listen.group = apache
listen.mode = 0660

pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 5
pm.max_requests = 500

php_admin_value[error_log] = /var/log/php-fpm/webmail-error.log
php_admin_flag[log_errors] = on

php_value[session.save_handler] = files
php_value[session.save_path] = /var/lib/php/session/webmail

php_admin_value[open_basedir] = /var/www/roundcube:/var/www/roundcube/public_html:/var/www/rainloop:/tmp:/var/log/php-fpm:/var/lib/php/session:/var/log/roundcube
php_admin_value[disable_functions] = exec,passthru,shell_exec,system
FPMEOF

info "Webmail Apache vhost and PHP-FPM pool configured"

# ─── Step 14.7: Install Roundcube Webmail ────────────────────────────────────
info "Step 14.7: Installing Roundcube webmail..."

ROUNDCUBE_DIR="/var/www/roundcube"
ROUNDCUBE_WEBROOT="$ROUNDCUBE_DIR/public_html"
if [[ -f "$ROUNDCUBE_WEBROOT/index.php" ]]; then
  info "Roundcube already installed at $ROUNDCUBE_DIR — skipping"
else
  # Install required PHP extensions (default PHP and php83 via Remi — RC >= 1.6 needs PHP >= 8.1)
  dnf install -y php-intl php-mbstring php-xml php-gd php-zip php-ldap \
    php83-php-mysqlnd php83-php-intl php83-php-xml php83-php-gd php83-php-zip php83-php-ldap php83-php-mbstring 2>/dev/null || true

  RC_VERSION=$(curl -sL --connect-timeout 10 "https://api.github.com/repos/roundcube/roundcubemail/releases/latest" 2>/dev/null \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4)
  [[ -z "$RC_VERSION" ]] && RC_VERSION="1.6.9"
  info "Downloading Roundcube $RC_VERSION..."

  mkdir -p "$ROUNDCUBE_DIR" /etc/roundcube /var/log/roundcube /tmp/roundcube

  RC_URL="https://github.com/roundcube/roundcubemail/releases/download/${RC_VERSION}/roundcubemail-${RC_VERSION}-complete.tar.gz"
  curl -sL --connect-timeout 30 "$RC_URL" -o /tmp/roundcube.tar.gz
  if [[ -f /tmp/roundcube.tar.gz && -s /tmp/roundcube.tar.gz ]]; then
    tar xzf /tmp/roundcube.tar.gz -C "$ROUNDCUBE_DIR" --strip-components=1 2>/dev/null && \
      info "Roundcube $RC_VERSION extracted to $ROUNDCUBE_DIR" || warn "Roundcube extraction failed"
    rm -f /tmp/roundcube.tar.gz
  else
    warn "Roundcube download failed — install manually from the Webmail section"
  fi

  if [[ -f "$ROUNDCUBE_WEBROOT/index.php" ]]; then
    RC_DB_PASS=$(openssl rand -hex 16)
    RC_DES_KEY=$(openssl rand -hex 12)
    MYSQL_ROOT_PASS=""
    [[ -f /usr/local/sysadminhcp/etc/mysql-root-password ]] && MYSQL_ROOT_PASS=$(cat /usr/local/sysadminhcp/etc/mysql-root-password)

    cat > /tmp/rc_db_setup.sql << SQLEOF
CREATE DATABASE IF NOT EXISTS roundcube_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'roundcube_user'@'localhost' IDENTIFIED BY '${RC_DB_PASS}';
GRANT ALL PRIVILEGES ON roundcube_db.* TO 'roundcube_user'@'localhost';
FLUSH PRIVILEGES;
SQLEOF
    if [[ -n "$MYSQL_ROOT_PASS" ]]; then
      mysql -u root -p"$MYSQL_ROOT_PASS" < /tmp/rc_db_setup.sql 2>/dev/null || warn "Roundcube DB setup failed"
      mysql -u root -p"$MYSQL_ROOT_PASS" roundcube_db < "$ROUNDCUBE_DIR/SQL/mysql.initial.sql" 2>/dev/null || warn "Roundcube DB schema init skipped"
    else
      mysql -u root < /tmp/rc_db_setup.sql 2>/dev/null || warn "Roundcube DB setup failed"
      mysql -u root roundcube_db < "$ROUNDCUBE_DIR/SQL/mysql.initial.sql" 2>/dev/null || warn "Roundcube DB schema init skipped"
    fi
    rm -f /tmp/rc_db_setup.sql

    mkdir -p "$ROUNDCUBE_DIR/config"
    # smtp_host uses port 587 (submission) with %u/%p (Roundcube's built-in placeholders
    # for the logged-in user's own IMAP credentials) — qmail-smtpd here has no IP-based
    # relay allowlist, so relaying to external addresses (Gmail etc.) is only granted
    # after a successful SMTP AUTH, which the submission port's spamdyke config always
    # requires. Port 25 + empty smtp_user/smtp_pass (the old values) let mail arrive fine
    # but every outbound send to an external address was rejected with "554 relaying not
    # allowed".
    cat > /etc/roundcube/config.inc.php << RCEOF
<?php
\$config['db_dsnw'] = 'mysql://roundcube_user:${RC_DB_PASS}@localhost/roundcube_db';
\$config['imap_host'] = 'localhost:143';
\$config['smtp_host'] = 'localhost:587';
\$config['smtp_port'] = 587;
\$config['smtp_user'] = '%u';
\$config['smtp_pass'] = '%p';
\$config['des_key'] = '${RC_DES_KEY}';
\$config['plugins'] = ['archive', 'zipdownload'];
\$config['skin'] = 'elastic';
\$config['product_name'] = 'SysAdminHCP Webmail';
\$config['auto_create_user'] = true;
\$config['log_dir'] = '/var/log/roundcube/';
\$config['temp_dir'] = '/tmp/roundcube/';
\$config['enable_installer'] = false;
\$config['max_message_size'] = '50M';
\$config['session_lifetime'] = 30;
RCEOF
    cp /etc/roundcube/config.inc.php "$ROUNDCUBE_DIR/config/config.inc.php"

    mkdir -p "$ROUNDCUBE_DIR/temp" "$ROUNDCUBE_DIR/logs"
    chown -R apache:apache "$ROUNDCUBE_DIR" /var/log/roundcube /tmp/roundcube
    chmod -R 755 "$ROUNDCUBE_DIR"
    chmod -R 777 "$ROUNDCUBE_DIR/temp" "$ROUNDCUBE_DIR/logs" /tmp/roundcube 2>/dev/null || true
    chcon -R -t httpd_sys_content_t "$ROUNDCUBE_DIR" 2>/dev/null || true
    chcon -R -t httpd_sys_rw_content_t "$ROUNDCUBE_DIR/temp" "$ROUNDCUBE_DIR/logs" 2>/dev/null || true

    # Create php83-fpm webmail pool — RC >= 1.6 requires PHP >= 8.1
    PHP83_POOL_DIR="/etc/opt/remi/php83/php-fpm.d"
    if [[ -d "$PHP83_POOL_DIR" ]]; then
      info "Creating php83-fpm webmail pool..."
      cat > "$PHP83_POOL_DIR/webmail.conf" << 'PHP83EOF'
; SysAdminHCP Webmail PHP 8.3 FPM Pool (for Roundcube >= 1.6)
[webmail]
user = apache
group = apache

listen = /var/opt/remi/php83/run/php-fpm/webmail.sock
listen.owner = apache
listen.group = apache
listen.mode = 0660

pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 5
pm.max_requests = 500

php_admin_value[error_log] = /var/log/php-fpm/webmail-php83-error.log
php_admin_flag[log_errors] = on

php_value[session.save_handler] = files
php_value[session.save_path] = /var/lib/php/session/webmail

; Security
php_admin_value[open_basedir] = /var/www/roundcube:/var/www/roundcube/public_html:/tmp:/var/log/roundcube:/var/lib/php/session
php_admin_value[disable_functions] = exec,passthru,shell_exec,system
PHP83EOF
      mkdir -p /var/lib/php/session/webmail
      chown -R apache:apache /var/lib/php/session/webmail
      chmod 1733 /var/lib/php/session/webmail
      systemctl enable php83-php-fpm 2>/dev/null || true
      systemctl restart php83-php-fpm 2>/dev/null || systemctl start php83-php-fpm 2>/dev/null || warn "php83-fpm start failed"
    else
      warn "php83-fpm not found — Roundcube may need manual PHP 8.1+ setup"
    fi

    info "Roundcube $RC_VERSION installed and configured at $ROUNDCUBE_DIR"
  fi
fi

# ─── Step 14.8: Install acme.sh ────────────────────────────────────────────
info "Step 14.8: Installing acme.sh (Let's Encrypt client)..."
if [[ -x /root/.acme.sh/acme.sh ]]; then
  info "acme.sh already installed — skipping"
else
  if curl -sSL https://get.acme.sh | sh 2>&1 | tail -5; then
    [[ -x /root/.acme.sh/acme.sh ]] && info "acme.sh installed successfully" || warn "acme.sh binary not found after install"
  else
    warn "acme.sh installation failed — install manually: curl -sSL https://get.acme.sh | sh"
  fi
fi

# Set Let's Encrypt as default CA (acme.sh v3+ defaults to ZeroSSL which requires EAB credentials)
if [[ -x /root/.acme.sh/acme.sh ]]; then
  info "Setting Let's Encrypt as default acme.sh CA..."
  /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt 2>/dev/null || true
fi

# ─── Step 14.9: Apply client:apache group ownership to all domain web roots ──
info "Step 14.9: Applying client:apache ownership to all domain web roots..."
for homedir in /home/*/; do
  [[ -d "$homedir" ]] || continue
  clientname=$(basename "$homedir")
  case "$clientname" in vpopmail|root|sysadminhcp|named|apache|mysql|qmail|qmaild|qmaill|qmailp|qmailq|qmailr|qmails|alias|nobody) continue ;; esac
  id "$clientname" &>/dev/null || continue

  for domaindir in "$homedir"*/; do
    [[ -d "$domaindir" ]] || continue
    pubhtml="$domaindir/public_html"
    statsdir="$domaindir/stats"
    logsdir="$domaindir/logs"

    if [[ -d "$pubhtml" ]]; then
      chown -R "$clientname":apache "$pubhtml" 2>/dev/null || true
      find "$pubhtml" -type d -exec chmod 750 {} \; 2>/dev/null || true
      find "$pubhtml" -type f -exec chmod 640 {} \; 2>/dev/null || true
      setfacl -d -m g:apache:r-x "$pubhtml" 2>/dev/null || true
      chcon -R -t httpd_sys_content_t "$pubhtml" 2>/dev/null || true
    fi

    for logdir in "$statsdir" "$logsdir"; do
      [[ -d "$logdir" ]] || continue
      chown -R apache:apache "$logdir" 2>/dev/null || true
      chmod 750 "$logdir" 2>/dev/null || true
      find "$logdir" -maxdepth 1 -name '*.log' -user root -exec chown apache:apache {} \; 2>/dev/null || true
      chcon -t httpd_log_t "$logdir" 2>/dev/null || true
    done

    chown "$clientname":"$clientname" "$domaindir" 2>/dev/null || true
    chmod 750 "$domaindir" 2>/dev/null || true
  done

  # Client home dir: the apache GROUP needs x (traverse) to reach public_html.
  # Group-scoped (not user-scoped) so any web server user in the apache group
  # (e.g. nginx, once switched to via Settings > Web Server Backend) can also
  # traverse in -- a user-only ACL entry here would 403 any non-apache server.
  setfacl -m g:apache:x "$homedir" 2>/dev/null || true
done
info "Domain web root ownership fixed (client:apache, 750/640)"

# ─── Step 14.10: Central ACME challenge directory ────────────────────────────
info "Step 14.10: Creating central ACME challenge directory..."
mkdir -p /var/www/acme-challenge/.well-known/acme-challenge
chown -R apache:apache /var/www/acme-challenge
chmod -R 755 /var/www/acme-challenge
chcon -R -t httpd_sys_content_t /var/www/acme-challenge 2>/dev/null || true

cat > /etc/httpd/conf.d/acme-challenge.conf << 'EOF'
# Central ACME / Let's Encrypt HTTP-01 challenge handler
Alias /.well-known/acme-challenge /var/www/acme-challenge/.well-known/acme-challenge

<Directory "/var/www/acme-challenge/.well-known/acme-challenge">
    Options None
    AllowOverride None
    Require all granted
</Directory>
EOF

systemctl reload httpd 2>/dev/null || true
info "Central ACME challenge directory created"

# ─── Write revision.json (drives version number in sidebar + About page) ───
# Without this file, GET /system/revision returns null fields and the panel
# shows no version anywhere in the UI, even though the app itself runs fine.
# Reads version.json, NOT package.json — package.json's own "version" field is a stale,
# separately-maintained value (stuck at 8.0.26 while the real project moved on to 8.0.328+)
# left over from before version.json became the single source of truth (see
# scripts/deploy.js, which already reads version.json correctly). Confirmed live 2026-08-02:
# every install script in this family (almalinux8/9/10, ubuntu22) had this same bug.
PANEL_VERSION=$(grep -m1 '"version"' "$REPO_DIR/version.json" 2>/dev/null | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)
[[ -z "$PANEL_VERSION" ]] && PANEL_VERSION="unknown"
cat > "$SYSADMINHCP_ROOT/etc/revision.json" << REVEOF
{
  "version": "$PANEL_VERSION",
  "deployedAt": "$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')",
  "description": "Installed via install-almalinux10.sh"
}
REVEOF
chown $SYSADMINHCP_USER:$SYSADMINHCP_GROUP "$SYSADMINHCP_ROOT/etc/revision.json"
chmod 644 "$SYSADMINHCP_ROOT/etc/revision.json"
info "revision.json written (version $PANEL_VERSION)"

# Start SysAdminHCP
# restart (not start): on an upgrade the service is already running the OLD binary --
# `start` on an already-active unit is a no-op, so the freshly-deployed code would
# silently never take effect. `restart` starts it if not already running, same as before.
info "Starting/restarting SysAdminHCP service..."
systemctl restart "$SYSADMINHCP_SERVICE"

# ─── Step 15: Verify Installation ───────────────────────────────────────────
info "Step 15: Verifying installation..."

HEALTH_OK=0
for i in $(seq 1 30); do
  if curl -s http://localhost:7778/health 2>/dev/null | grep -q '"ok"'; then
    HEALTH_OK=1; break
  fi
  sleep 1
done

if [[ $HEALTH_OK -eq 1 ]]; then
  info "SysAdminHCP health check passed!"
else
  warn "SysAdminHCP health check did not respond within 30s"
  warn "Check logs: journalctl -u sysadminhcp -n 50"
fi

if [[ -f "$SYSADMINHCP_ROOT/data/sysadminhcp.db" ]]; then
  DB_SIZE=$(stat -c%s "$SYSADMINHCP_ROOT/data/sysadminhcp.db" 2>/dev/null || echo "unknown")
  info "Database file created ($DB_SIZE bytes)"
else
  warn "Database not yet created — seeded on first startup."
fi

# ─── Step 15.5: Verify Core Services & Minimum Requirements ─────────────────
# The health check above only proves the SysAdminHCP Node process itself is
# answering - it says nothing about httpd, MariaDB, or the mail stack, which
# is exactly the gap that let a broken vhost take down Apache server-wide
# (every site on the box, not just the one being changed) while SysAdminHCP's
# own health check kept passing throughout, because the app doesn't depend on
# Apache being up to answer /health. This checks each service explicitly and
# runs a real Apache config test, so a broken install is reported here and
# now instead of discovered later by a confused admin.
info "Step 15.5: Verifying core services..."

SERVICE_CHECK_FAILED=0
check_service() {
  local svc="$1" label="$2"
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    info "  OK: $label ($svc) is running"
  else
    warn "  FAIL: $label ($svc) is NOT running - check: systemctl status $svc"
    SERVICE_CHECK_FAILED=1
  fi
}

check_service httpd "Web server"
check_service mariadb "Database server"
check_service qmail-send "Mail delivery (qmail-send)"
check_service qmail-smtp "SMTP (qmail-smtp)"
check_service dovecot "IMAP/POP3 (Dovecot)"
check_service "$SYSADMINHCP_SERVICE" "SysAdminHCP control panel"

if command -v apachectl &>/dev/null; then
  if ! apachectl configtest &>/dev/null; then
    warn "  FAIL: Apache configuration test failed - run 'apachectl configtest' on the server to see the exact error"
    SERVICE_CHECK_FAILED=1
  fi
elif command -v apache2ctl &>/dev/null; then
  if ! apache2ctl configtest &>/dev/null; then
    warn "  FAIL: Apache configuration test failed - run 'apache2ctl configtest' on the server to see the exact error"
    SERVICE_CHECK_FAILED=1
  fi
fi

if [[ $SERVICE_CHECK_FAILED -eq 1 ]]; then
  warn "One or more core services are not running - hosting features may not work until this is resolved."
else
  info "All core services verified running."
fi

# ─── Done ──────────────────────────────────────────────────────────────────
echo ""
info "================================================"
info "  SysAdminHCP Control Panel Installation Complete!"
info "================================================"
echo ""
info "  Web UI:     https://$(hostname -I | awk '{print $1}'):7777/display"
info "  Admin User: admin / admin"
echo ""
warn "  ⚠️  CHANGE THE DEFAULT PASSWORD IMMEDIATELY!"
warn "  ⚠️  SECURE THE MARIADB ROOT PASSWORD!"
echo ""
info "  AlmaLinux 10 Notes:"
info "    PHP 8.3 installed from AppStream (system default)."
info "    Additional PHP versions via Remi EL10 repo:"
info "    https://rpms.remirepo.net/enterprise/remi-release-10.rpm"
info "    Mail stack (qmail/vpopmail/spamdyke/simscan/etc.) built entirely from source —"
info "    no QmailToaster repo dependency. Legacy toaster admin UI (optional, not the"
info "    main panel): https://<this-server>/admin-toaster/ — password in"
info "    /root/.toaster-admin-password."
info "    iptables-nft compat layer installed (iptables-legacy removed in RHEL 10)."
echo ""
info "  Service commands:"
info "    sudo systemctl {start|stop|restart|status} sysadminhcp"
echo ""
info "  Log files:"
info "    journalctl -u sysadminhcp -f"
echo ""

if [[ $WSL_MODE -eq 1 ]]; then
  info "  WSL Notes:"
  info "    Enable systemd: /etc/wsl.conf → [boot] / systemd=true"
  info "    Restart: wsl --shutdown (from PowerShell)"
  echo ""
fi
