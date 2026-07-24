#!/bin/bash
# ============================================================================
# SysAdminHCP Control Panel - Ubuntu 22.04+ Installation Script
# ============================================================================
# This script installs SysAdminHCP on Ubuntu 22.04 (jammy), 24.04 (noble)
# or newer, running under WSL or bare metal.
#
# Ubuntu builds a RHEL-compatibility layer so the panel behaves exactly as it
# does on AlmaLinux:
#   - 'apache' user/group created; Apache and PHP-FPM run as apache
#   - httpd.service / php-fpm.service systemd aliases
#   - /etc/httpd/conf.d include dir wired into apache2.conf
#   - /etc/httpd/ssl, /var/log/httpd (symlink), /etc/pki/tls certs
#   - /etc/named.conf symlink, /var/named zone dir (+ AppArmor override)
#   - /etc/php-fpm.d symlink to the default PHP version's pool.d
#   - /etc/my.cnf.d include dir wired into MariaDB config
#   - firewalld replaces ufw (Security pages work unchanged)
#   - qmail (notqmail) + vpopmail + spamdyke built from source into the
#     identical /var/qmail and /home/vpopmail layouts
#
# Usage:
#   sudo bash install-ubuntu22.sh
# ============================================================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Track if this is a fresh install or upgrade
FRESH_INSTALL=0

# ─── Configuration ──────────────────────────────────────────────────────────
SYSADMINHCP_ROOT="/usr/local/sysadminhcp"
SYSADMINHCP_USER="sysadminhcp"
SYSADMINHCP_GROUP="sysadminhcp"
SYSADMINHCP_SERVICE="sysadminhcp"
NODE_MAJOR=20
NOTQMAIL_VERSION="1.08"
VPOPMAIL_VERSION="5.4.33"
SPAMDYKE_VERSION="5.0.1"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ─── Pre-flight Checks ────────────────────────────────────────────────────
info "SysAdminHCP Control Panel Installer for Ubuntu 22.04+"
info "======================================================"

# Check root
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root (use sudo)"
fi

# Check OS
if [[ ! -f /etc/os-release ]]; then
  error "Cannot detect OS. /etc/os-release not found"
fi
source /etc/os-release
info "Detected OS: $NAME $VERSION_ID"

if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
  error "This script is designed for Ubuntu 22.04+. Detected ID: $ID. Use install-almalinux9.sh for RHEL-family systems."
fi

UBUNTU_MAJOR="${VERSION_ID%%.*}"
if [[ "$ID" == "ubuntu" && "$UBUNTU_MAJOR" -lt 22 ]]; then
  error "Ubuntu $VERSION_ID is too old. SysAdminHCP requires Ubuntu 22.04 or newer."
fi

# Check WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
  info "Running under WSL (Windows Subsystem for Linux)"
  WSL_MODE=1

  # Ensure systemd is enabled in WSL
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
    error "WSL needs to restart for systemd to activate. Run: wsl --shutdown (from PowerShell), then re-run this installer."
  fi

  if [[ ! -d /run/systemd/system ]]; then
    error "systemd is not running. Enable it with: edit /etc/wsl.conf → [boot]\\nsystemd=true, then restart WSL with 'wsl --shutdown' from PowerShell."
  fi
  info "systemd is active"
else
  WSL_MODE=0
fi

# Check if this is a fresh install (no existing SysAdminHCP data)
if [[ -f "$SYSADMINHCP_ROOT/httpdocs/dist/index.js" || -f "$SYSADMINHCP_ROOT/httpdocs/sysadminhcp" ]]; then
  info "Existing SysAdminHCP installation detected - upgrading..."
else
  FRESH_INSTALL=1
  info "Fresh installation detected"
fi

# ─── Pre-flight: Verify /usr is writable ───────────────────────────────────
if ! touch /usr/.sysadminhcp-write-test 2>/dev/null; then
  warn "/usr is mounted read-only. Remounting as read-write..."
  mount -o remount,rw /usr
  if ! touch /usr/.sysadminhcp-write-test 2>/dev/null; then
    error "/usr is still read-only after remount. Cannot install packages. Run: mount -o remount,rw /usr"
  fi
  rm -f /usr/.sysadminhcp-write-test
  info "/usr is now read-write"
else
  rm -f /usr/.sysadminhcp-write-test
  info "/usr is writable"
fi

# ─── Step 1: System Update ─────────────────────────────────────────────────
info "Step 1: Updating system packages..."
# Third-party PPAs (e.g. ondrej/php) legitimately change their Release "Label"/"Origin"
# metadata over time - apt treats that as a security-relevant change and refuses to
# proceed without explicit consent, which under `set -e` killed this entire installer
# before it ever reached the binary update step. Allowing release-info changes here is
# the standard, safe way to handle routine PPA metadata churn (not a real security bypass
# - it does not disable signature verification, just the "this repo's identity metadata
# changed" prompt).
apt-get update -y -o Acquire::AllowReleaseInfoChange=true
apt-get upgrade -y

# ─── Step 2: Base Utilities ─────────────────────────────────────────────────
info "Step 2: Installing base utilities..."
apt-get install -y curl wget rsync sshpass logrotate htop unzip openssl \
  software-properties-common apt-transport-https ca-certificates gnupg \
  lsb-release acl

# ─── Step 3: Install Node.js ───────────────────────────────────────────────
info "Step 3: Installing Node.js $NODE_MAJOR.x..."
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_$NODE_MAJOR.x | bash -
  apt-get install -y nodejs
fi
NODE_VERSION=$(node --version)
info "Node.js installed: $NODE_VERSION"

# ─── Step 4: Install Build Tools (for native npm modules + source builds) ──
info "Step 4: Installing build tools..."
apt-get install -y build-essential make gcc g++ python3

# ─── Step 5: Install Service Dependencies ───────────────────────────────────
info "Step 5: Installing service dependencies..."

# ── Web server (Apache) ─────────────────────────────────────────────────────
apt-get install -y apache2 apache2-utils libapache2-mod-fcgid ssl-cert

# RHEL-compat: create the 'apache' user/group and run Apache as it.
# All panel code chowns/ACLs use client:apache — this makes them work unchanged.
groupadd -f apache
if ! id apache &>/dev/null; then
  useradd -r -g apache -s /usr/sbin/nologin -d /var/www apache
  info "Created 'apache' system user/group (RHEL compat)"
fi
# Point Apache's run user/group at apache (envvars is the Debian-approved override)
sed -i 's/^export APACHE_RUN_USER=.*/export APACHE_RUN_USER=apache/'  /etc/apache2/envvars
sed -i 's/^export APACHE_RUN_GROUP=.*/export APACHE_RUN_GROUP=apache/' /etc/apache2/envvars
info "Apache configured to run as apache:apache"

# Enable required Apache modules (FPM proxying, SSL, rewrites)
a2enmod ssl proxy proxy_fcgi proxy_http rewrite headers >/dev/null 2>&1 || true

# RHEL-compat: /etc/httpd/conf.d as a real include dir (panel writes vhosts here)
mkdir -p /etc/httpd/conf.d
if ! grep -q 'IncludeOptional /etc/httpd/conf.d/\*.conf' /etc/apache2/apache2.conf; then
  cat >> /etc/apache2/apache2.conf << 'EOF'

# SysAdminHCP RHEL-compat include dir — panel-managed vhosts live here
IncludeOptional /etc/httpd/conf.d/*.conf
EOF
  info "Wired /etc/httpd/conf.d/*.conf into apache2.conf"
fi

# Silence the FQDN warning
if ! grep -q '^ServerName' /etc/apache2/apache2.conf; then
  echo "ServerName localhost" >> /etc/apache2/apache2.conf
fi

# RHEL-compat: Apache SSL certificate storage
mkdir -p /etc/httpd/ssl
chmod 711 /etc/httpd/ssl

# RHEL-compat: /var/log/httpd -> /var/log/apache2
if [[ ! -e /var/log/httpd ]]; then
  ln -s /var/log/apache2 /var/log/httpd
  info "Symlinked /var/log/httpd -> /var/log/apache2"
fi

# RHEL-compat: httpd.service alias
if [[ ! -e /etc/systemd/system/httpd.service ]]; then
  ln -s /lib/systemd/system/apache2.service /etc/systemd/system/httpd.service
  info "Created httpd.service alias -> apache2.service"
fi

# RHEL-compat: /etc/pki/tls certs (webmail vhost + panel SSL fallbacks reference these)
mkdir -p /etc/pki/tls/certs /etc/pki/tls/private
if [[ ! -f /etc/pki/tls/certs/localhost.crt ]]; then
  openssl req -x509 -newkey rsa:2048 \
    -keyout /etc/pki/tls/private/localhost.key \
    -out /etc/pki/tls/certs/localhost.crt \
    -days 3650 -nodes \
    -subj "/C=US/ST=Server/L=Server/O=SysAdminHCP/CN=localhost" 2>/dev/null
  chmod 600 /etc/pki/tls/private/localhost.key
  info "Generated /etc/pki/tls localhost certificate (RHEL compat)"
fi

# ── DNS (BIND9) ─────────────────────────────────────────────────────────────
apt-get install -y bind9 bind9utils bind9-dnsutils

# RHEL-compat: /etc/named.conf -> /etc/bind/named.conf
if [[ ! -e /etc/named.conf ]]; then
  ln -s /etc/bind/named.conf /etc/named.conf
  info "Symlinked /etc/named.conf -> /etc/bind/named.conf"
fi

# RHEL-compat: /var/named zone dir, owned by bind
mkdir -p /var/named/slaves
chown -R bind:bind /var/named
chmod 770 /var/named/slaves
chmod 755 /var/named

# AppArmor: allow named to read/write /var/named (Debian confines to /var/cache/bind)
mkdir -p /etc/apparmor.d/local
if ! grep -q '/var/named/' /etc/apparmor.d/local/usr.sbin.named 2>/dev/null; then
  cat >> /etc/apparmor.d/local/usr.sbin.named << 'EOF'
# SysAdminHCP: BIND zone files live in /var/named (RHEL-compat layout)
/var/named/ rw,
/var/named/** rw,
EOF
  apparmor_parser -r /etc/apparmor.d/usr.sbin.named 2>/dev/null || true
  info "AppArmor override added for /var/named"
fi

# Configure BIND to listen on all interfaces and answer public queries
# (a hosting panel nameserver must be reachable from the internet)
if [[ -f /etc/bind/named.conf.options ]]; then
  if ! grep -q 'allow-query' /etc/bind/named.conf.options; then
    sed -i 's/^\(\s*\)directory /\1allow-query { any; };\n\1directory /' /etc/bind/named.conf.options
  fi
  # Every zone this panel manages uses a relative "file" path (e.g. "example.com.db"),
  # resolved against this directory option — but Ubuntu's stock named.conf.options
  # still points it at /var/cache/bind, while the panel actually writes zone files to
  # /var/named (the AppArmor override above was already scoped for that path). Left
  # unfixed, EVERY master zone fails to load ("file not found") even though the file
  # genuinely exists — BIND is just looking in the wrong directory for it.
  if ! grep -q 'directory "/var/named"' /etc/bind/named.conf.options; then
    sed -i 's#^\(\s*\)directory\s*"[^"]*"\s*;#\1directory "/var/named";#' /etc/bind/named.conf.options
    info "Fixed named.conf.options directory -> /var/named (was /var/cache/bind)"
  fi
  # Ubuntu default has no listen-on restriction (listens on all) — nothing to change
  named-checkconf && info "named.conf validated (allow-query any, directory /var/named)" \
    || warn "named.conf validation failed — check /etc/bind/named.conf.options manually"
fi

# ── Database (MariaDB) ──────────────────────────────────────────────────────
apt-get install -y mariadb-server mariadb-client

# RHEL-compat: /etc/my.cnf.d include dir (panel drops MariaDB config here)
mkdir -p /etc/my.cnf.d
if ! grep -q '/etc/my.cnf.d' /etc/mysql/my.cnf 2>/dev/null; then
  echo '!includedir /etc/my.cnf.d/' >> /etc/mysql/my.cnf
  info "Wired /etc/my.cnf.d/ into MariaDB config"
fi

# ── PHP-FPM (default distro version: 8.1 on 22.04, 8.3 on 24.04) ───────────
apt-get install -y php php-fpm php-cli php-common php-mysql php-xml php-gd php-mbstring php-intl php-zip php-curl

PHPV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
info "Default PHP version: $PHPV"

# RHEL-compat: /etc/php-fpm.d -> default version pool dir
if [[ ! -e /etc/php-fpm.d ]]; then
  ln -s "/etc/php/$PHPV/fpm/pool.d" /etc/php-fpm.d
  info "Symlinked /etc/php-fpm.d -> /etc/php/$PHPV/fpm/pool.d"
fi

# RHEL-compat: php-fpm.service alias
if [[ ! -e /etc/systemd/system/php-fpm.service ]]; then
  ln -s "/lib/systemd/system/php$PHPV-fpm.service" /etc/systemd/system/php-fpm.service
  info "Created php-fpm.service alias -> php$PHPV-fpm.service"
fi

# RHEL-compat: /run/php-fpm socket dir (created at boot via tmpfiles.d)
cat > /etc/tmpfiles.d/sysadminhcp-php-fpm.conf << 'EOF'
# SysAdminHCP: RHEL-compat PHP-FPM socket directory
d /run/php-fpm 0755 root root -
EOF
mkdir -p /run/php-fpm

# RHEL-compat: log + session dirs referenced by pool templates
mkdir -p /var/log/php-fpm /var/lib/php/session
chmod 1733 /var/lib/php/session

# Reconfigure the default www pool to match the RHEL layout:
# run as apache, listen on /run/php-fpm/www.sock (pma-signon + panel proxy expect this)
WWWPOOL="/etc/php/$PHPV/fpm/pool.d/www.conf"
if [[ -f "$WWWPOOL" ]]; then
  sed -i 's|^user = .*|user = apache|'   "$WWWPOOL"
  sed -i 's|^group = .*|group = apache|' "$WWWPOOL"
  sed -i 's|^listen = .*|listen = /run/php-fpm/www.sock|' "$WWWPOOL"
  sed -i 's|^;\?listen.owner = .*|listen.owner = apache|' "$WWWPOOL"
  sed -i 's|^;\?listen.group = .*|listen.group = apache|' "$WWWPOOL"
  info "Default PHP-FPM pool: user apache, socket /run/php-fpm/www.sock"
fi

# Any OTHER installed PHP-FPM version's own www.conf pool must NOT also claim this same
# socket — whichever one's fpm service starts first wins the bind and the other crash-loops
# forever ("Another FPM instance seems to already listen on ...") since $PHPV is recomputed
# fresh on every install/upgrade run and this block never un-claims a PREVIOUS default's pool.
# Real incident: php8.3 and php8.4 both ended up pointed at /run/php-fpm/www.sock on an
# Ubuntu 24.04 box after two install runs resolved a different $PHPV each time (2026-07-17).
for otherpool in /etc/php/*/fpm/pool.d/www.conf; do
  [[ "$otherpool" == "$WWWPOOL" ]] && continue
  [[ -f "$otherpool" ]] || continue
  otherver=$(echo "$otherpool" | sed -n 's|.*/php/\([0-9.]*\)/fpm/.*|\1|p')
  [[ -z "$otherver" ]] && continue
  if grep -q '^listen = /run/php-fpm/www\.sock$' "$otherpool" 2>/dev/null; then
    sed -i "s|^listen = /run/php-fpm/www\.sock|listen = /run/php-fpm/php${otherver}-www.sock|" "$otherpool"
    info "Repointed php${otherver}'s www pool off the shared default socket (was colliding with php$PHPV)"
    systemctl restart "php${otherver}-fpm" 2>/dev/null || true
  fi
done

# ── FTP (Pure-FTPd with MySQL auth) ─────────────────────────────────────────
apt-get install -y pure-ftpd-mysql || apt-get install -y pure-ftpd

# ── Security tools ──────────────────────────────────────────────────────────
apt-get install -y fail2ban clamav clamav-daemon clamav-freshclam || warn "Some security packages failed to install"

# ── firewalld (replaces ufw so the panel Security pages work unchanged) ─────
if ! command -v firewall-cmd &>/dev/null; then
  apt-get install -y firewalld
fi
systemctl disable --now ufw 2>/dev/null || true

# ─── Step 5.5: Mail Stack (notqmail + vpopmail + spamdyke + dovecot) ───────
info "Step 5.5: Installing mail stack (qmail/vpopmail from source)..."

# Remove conflicting MTAs
systemctl stop postfix 2>/dev/null || true
apt-get remove -y --purge postfix exim4 exim4-base 2>/dev/null || true

# Dovecot + supporting packages from apt.
# NOTE: installed in separate calls, not one combined apt-get line — apt-get
# treats a multi-package install atomically, so a single unavailable/renamed
# package (e.g. 'maildrop', dropped from Debian/Ubuntu repos since bookworm)
# silently fails the ENTIRE line under '|| warn', including the MariaDB dev
# headers vpopmail needs below. Splitting means one bad name can't take out
# the rest.
apt-get install -y dovecot-core dovecot-imapd dovecot-pop3d dovecot-mysql \
  || warn "Dovecot install failed — mail (IMAP/POP3) will be unavailable until installed manually"
apt-get install -y libmariadb-dev libmariadb-dev-compat libssl-dev \
  || warn "MariaDB dev headers failed to install — vpopmail build below will fail without them"
apt-get install -y spamassassin ucspi-tcp fetchmail ripmime \
  || warn "Some optional mail utilities failed to install"

# vpopmail user/group (same IDs as QmailToaster on RHEL)
groupadd -g 89 vchkpw 2>/dev/null || true
useradd -u 89 -g 89 vpopmail -s /usr/sbin/nologin -d /home/vpopmail 2>/dev/null || true
mkdir -p /home/vpopmail
chown vpopmail:vchkpw /home/vpopmail
chmod 755 /home/vpopmail

# qmail users/groups (classic layout)
if [[ ! -d /var/qmail ]]; then
  QMAIL_FRESH=1
else
  QMAIL_FRESH=0
fi
groupadd nofiles 2>/dev/null || true
groupadd qmail   2>/dev/null || true
for u in alias qmaild qmaill qmailp; do
  useradd -g nofiles -d /var/qmail/alias -s /usr/sbin/nologin "$u" 2>/dev/null || true
done
for u in qmailq qmailr qmails; do
  useradd -g qmail -d /var/qmail -s /usr/sbin/nologin "$u" 2>/dev/null || true
done

# ── Build notqmail (maintained qmail fork; same /var/qmail layout) ─────────
if [[ ! -x /var/qmail/bin/qmail-smtpd ]]; then
  info "Building notqmail $NOTQMAIL_VERSION from source..."
  cd /tmp
  rm -rf "notqmail-$NOTQMAIL_VERSION"
  if curl -fsSL -o notqmail.tar.gz \
      "https://github.com/notqmail/notqmail/releases/download/notqmail-$NOTQMAIL_VERSION/notqmail-$NOTQMAIL_VERSION.tar.gz"; then
    tar xzf notqmail.tar.gz
    cd "notqmail-$NOTQMAIL_VERSION"
    make -j"$(nproc)" 2>&1 | tail -3 || true
    make setup check 2>&1 | tail -3
    # Basic config from hostname
    ./config-fast "$(hostname -f 2>/dev/null || hostname)" 2>/dev/null || true
    info "notqmail installed to /var/qmail"
    cd /tmp && rm -rf "notqmail-$NOTQMAIL_VERSION" notqmail.tar.gz
  else
    warn "notqmail download failed — mail (SMTP) will be unavailable until installed manually"
  fi
else
  info "qmail already present at /var/qmail — skipping build"
fi

# Default delivery: Maildir
if [[ -d /var/qmail/control ]]; then
  echo "./Maildir/" > /var/qmail/control/defaultdelivery
fi

# qmail rc script (Maildir delivery)
if [[ -d /var/qmail ]]; then
  cat > /var/qmail/rc << 'EOF'
#!/bin/sh
exec env - PATH="/var/qmail/bin:$PATH" \
qmail-start "`cat /var/qmail/control/defaultdelivery 2>/dev/null || echo ./Maildir/`"
EOF
  chmod 755 /var/qmail/rc
fi

# ── Build vpopmail (same binaries the panel drives: vadddomain/vadduser/…) ──
if [[ ! -x /home/vpopmail/bin/vadddomain && -d /var/qmail ]]; then
  info "Building vpopmail $VPOPMAIL_VERSION from source (MySQL auth)..."
  cd /tmp
  rm -rf "vpopmail-$VPOPMAIL_VERSION"
  if curl -fsSL -o vpopmail.tar.gz \
      "https://sourceforge.net/projects/vpopmail/files/vpopmail-stable/$VPOPMAIL_VERSION/vpopmail-$VPOPMAIL_VERSION.tar.gz/download"; then
    tar xzf vpopmail.tar.gz
    cd "vpopmail-$VPOPMAIL_VERSION"
    # MariaDB headers/libs (libmariadb-dev-compat provides mysql.h shims)
    MYSQL_INC="/usr/include/mysql"
    [[ -d /usr/include/mariadb && ! -d /usr/include/mysql ]] && MYSQL_INC="/usr/include/mariadb"
    # GCC 10+ (Ubuntu 22.04/24.04 both ship it) defaults to -fno-common, which
    # breaks this ~20-year-old codebase: several globals (MYSQL_READ_SERVER etc.)
    # are declared in a shared header without 'extern' and get linked from
    # multiple .o files, causing "multiple definition of ..." errors at the
    # final link step (vconvert and others fail, so NO binaries get installed
    # even though most of the build otherwise succeeds). -fcommon restores the
    # pre-GCC-10 behavior these old tentative-definition globals rely on.
    export CFLAGS="-fcommon"
    ./configure \
      --enable-auth-module=mysql \
      --enable-many-domains=y \
      --enable-incdir="$MYSQL_INC" \
      --enable-libdir=/usr/lib/x86_64-linux-gnu \
      --enable-auth-logging=y \
      --enable-clear-passwd=y \
      --enable-logging=p > /tmp/vpopmail_build.log 2>&1
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

# ── Build spamdyke (provides SMTP AUTH + TLS in front of qmail-smtpd) ───────
if [[ ! -x /usr/local/bin/spamdyke ]]; then
  info "Building spamdyke $SPAMDYKE_VERSION from source..."
  cd /tmp
  rm -rf "spamdyke-$SPAMDYKE_VERSION"
  SPAMDYKE_OK=0
  if curl -fsSL -o spamdyke.tgz "https://www.spamdyke.org/releases/spamdyke-$SPAMDYKE_VERSION.tgz" 2>/dev/null; then
    SPAMDYKE_OK=1
  elif curl -fsSL -o spamdyke.tgz "https://github.com/spamdyke/spamdyke/archive/refs/tags/RELEASE_5_0_1.tar.gz" 2>/dev/null; then
    SPAMDYKE_OK=1
  fi
  if [[ $SPAMDYKE_OK -eq 1 ]]; then
    mkdir -p /tmp/spamdyke-src && tar xzf spamdyke.tgz -C /tmp/spamdyke-src --strip-components=1
    ( cd /tmp/spamdyke-src/spamdyke && ./configure --with-tls 2>&1 | tail -2 && make -j"$(nproc)" 2>&1 | tail -2 && cp spamdyke /usr/local/bin/spamdyke ) \
      && info "spamdyke installed at /usr/local/bin/spamdyke" \
      || warn "spamdyke build failed — SMTP AUTH/TLS will be unavailable"
    rm -rf /tmp/spamdyke-src spamdyke.tgz
  else
    warn "spamdyke download failed — SMTP AUTH/TLS will be unavailable"
  fi
fi

# spamdyke config — two separate files: full anti-spam rules for port 25 (the unauthenticated
# public listener), and a lighter TLS/AUTH-only config for port 587 submission. IP-reputation
# checks (RBL, rdns) must NOT apply to authenticated submission — a legitimate user on a
# residential/mobile IP would get incorrectly rejected; the SMTP AUTH itself is the real gate there.
# tls-cipher-list is written explicitly in both configs below — spamdyke passes this string to
# OpenSSL's legacy SSL_CTX_set_cipher_list() (the TLS <=1.2 API, which never accepted TLS 1.3
# ciphersuite names — those need the separate SSL_CTX_set_ciphersuites() call spamdyke doesn't
# use). Leaving the directive out entirely is NOT a safe default here: this build's own
# compiled-in default is "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:..." (the same
# broken TLS 1.3-named value every qmail-toaster RPM ships as its spamdyke.conf default) —
# confirmed live on Ubuntu with no tls-cipher-list line present at all. Older OpenSSL tolerated
# the mismatch; OpenSSL 3.0+ (Ubuntu 22.04+) rejects it outright, logging "unable to set
# SSL/TLS cipher list" on every connection and silently breaking STARTTLS.
SPAMDYKE_CIPHER_LIST="ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384"

mkdir -p /etc/spamdyke
if [[ ! -f /etc/spamdyke/spamdyke.conf ]]; then
  cat > /etc/spamdyke/spamdyke.conf << EOF
log-level=info
tls-certificate-file=/etc/pki/tls/certs/localhost.crt
tls-privatekey-file=/etc/pki/tls/private/localhost.key
tls-cipher-list=$SPAMDYKE_CIPHER_LIST
smtp-auth-command=/home/vpopmail/bin/vchkpw /bin/true
smtp-auth-level=ondemand
idle-timeout-secs=300
greeting-delay-secs=6
max-recipients=50
reject-empty-rdns
reject-unresolvable-rdns
reject-sender=no-mx
dns-blacklist-entry=bl.rbl-dns.com
EOF
  info "spamdyke.conf created"
fi
if [[ ! -f /etc/spamdyke/spamdyke-submission.conf ]]; then
  cat > /etc/spamdyke/spamdyke-submission.conf << EOF
log-level=info
tls-certificate-file=/etc/pki/tls/certs/localhost.crt
tls-privatekey-file=/etc/pki/tls/private/localhost.key
tls-cipher-list=$SPAMDYKE_CIPHER_LIST
smtp-auth-command=/home/vpopmail/bin/vchkpw /bin/true
smtp-auth-level=always
idle-timeout-secs=300
greeting-delay-secs=0
EOF
  info "spamdyke-submission.conf created"
fi

# Idempotent fix for existing installs re-running this script: correct the line even if the
# config files already existed and were skipped by the [[ ! -f ]] guards above.
for f in /etc/spamdyke/spamdyke.conf /etc/spamdyke/spamdyke-submission.conf; do
  if [[ -f "$f" ]]; then
    sed -i '/^#\?tls-cipher-list=/d' "$f"
    echo "tls-cipher-list=$SPAMDYKE_CIPHER_LIST" >> "$f"
  fi
done

# ── qmail supervise-style run scripts + systemd units (same as AlmaLinux) ──
if [[ -d /var/qmail ]]; then
  mkdir -p /var/qmail/supervise/smtp /var/qmail/supervise/submission /var/qmail/supervise/send

  cat > /var/qmail/supervise/smtp/run << 'EOF'
#!/bin/bash
# QmailToaster-compatible SMTP service (port 25) via spamdyke + qmail-smtpd
exec 2>&1
HOSTNAME=$(hostname -f 2>/dev/null || hostname)
SPAMDYKE=""
[ -x /usr/local/bin/spamdyke ] && SPAMDYKE="/usr/local/bin/spamdyke --config-file /etc/spamdyke/spamdyke.conf"
exec /usr/bin/tcpserver -v -R -H -l "$HOSTNAME" -c 100 0 25 \
  $SPAMDYKE /var/qmail/bin/qmail-smtpd \
  /home/vpopmail/bin/vchkpw /bin/true 2>&1
EOF
  chmod 755 /var/qmail/supervise/smtp/run

  cat > /var/qmail/supervise/submission/run << 'EOF'
#!/bin/bash
# QmailToaster-compatible Submission service (port 587) via spamdyke + qmail-smtpd
exec 2>&1
HOSTNAME=$(hostname -f 2>/dev/null || hostname)
SPAMDYKE=""
[ -x /usr/local/bin/spamdyke ] && SPAMDYKE="/usr/local/bin/spamdyke --config-file /etc/spamdyke/spamdyke-submission.conf"
exec /usr/bin/tcpserver -v -R -H -l "$HOSTNAME" -c 50 0 587 \
  $SPAMDYKE /var/qmail/bin/qmail-smtpd \
  /home/vpopmail/bin/vchkpw /bin/true 2>&1
EOF
  chmod 755 /var/qmail/supervise/submission/run

  # Wrapper scripts (systemd needs readable shebang targets)
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
Description=Qmail mail delivery (qmail-send)
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
Description=Qmail SMTP (port 25)
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
Description=Qmail Submission (port 587)
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

  # sendmail symlink (panel + PHP mail() use it)
  [ ! -e /usr/sbin/sendmail ] && ln -s /var/qmail/bin/sendmail /usr/sbin/sendmail 2>/dev/null || true
fi

# ── Dovecot: vpopmail MySQL authentication (same config as AlmaLinux) ──────
# Idempotent: reuse the existing password on re-runs/upgrades instead of generating a new
# one every time. CREATE USER IF NOT EXISTS later is a no-op if the MySQL user already
# exists, so regenerating this password unconditionally silently desyncs Dovecot's stored
# credential from the real MySQL password — breaking IMAP/POP3/webmail auth for every
# mailbox on the server until manually fixed. autoinstall.sh re-runs this script on every
# update, guaranteeing this hits on the very next upgrade after first install.
KLOXOJRA_DB_PASS=""
if [[ -f /etc/dovecot/dovecot-sql.conf.ext ]]; then
  KLOXOJRA_DB_PASS=$(sed -n "s/.*user=sysadminhcp password=\([^ ]*\).*/\1/p" /etc/dovecot/dovecot-sql.conf.ext | head -1)
fi
[[ -z "$KLOXOJRA_DB_PASS" ]] && KLOXOJRA_DB_PASS=$(openssl rand -hex 12 2>/dev/null || echo 'sysadminhcp123')

cat > /etc/dovecot/dovecot-sql.conf.ext << DOVECOTSQL
# SysAdminHCP Dovecot vpopmail MySQL authentication
driver = mysql
connect = host=127.0.0.1 dbname=vpopmail user=sysadminhcp password=${KLOXOJRA_DB_PASS}

# Use CRYPT scheme against pw_passwd (handles MD5/SHA256/SHA512-crypt; avoids varchar(16) truncation of pw_clear_passwd)
default_pass_scheme = CRYPT

# Password lookup
password_query = \
  SELECT pw_passwd AS password, \
  CONCAT('/home/vpopmail/domains/', pw_domain, '/', pw_name) AS userdb_home, \
  89 AS userdb_uid, \
  89 AS userdb_gid, \
  CONCAT('maildir:/home/vpopmail/domains/', pw_domain, '/', pw_name, '/Maildir') AS userdb_mail \
  FROM vpopmail \
  WHERE pw_name = '%n' AND pw_domain = '%d'

# User lookup
user_query = \
  SELECT CONCAT('/home/vpopmail/domains/', pw_domain, '/', pw_name) AS home, \
  CONCAT('maildir:/home/vpopmail/domains/', pw_domain, '/', pw_name, '/Maildir') AS mail, \
  89 AS uid, \
  89 AS gid \
  FROM vpopmail \
  WHERE pw_name = '%n' AND pw_domain = '%d'

# Iterate query for user listing
iterate_query = SELECT CONCAT(pw_name, '@', pw_domain) AS user FROM vpopmail
DOVECOTSQL
chmod 600 /etc/dovecot/dovecot-sql.conf.ext

# Configure Dovecot auth to use SQL instead of PAM
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

# Fix Dovecot mail config for vpopmail
sed -i 's/^#\?first_valid_uid = .*/first_valid_uid = 89/' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true
grep -q '^mail_uid' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || sed -i '/^first_valid_uid/i mail_uid = vpopmail\nmail_gid = vchkpw' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true
grep -q '^mail_location' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || sed -i '/^mail_uid/i mail_location = maildir:/home/vpopmail/domains/%d/%n/Maildir' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true

# ─── Step 6: Create SysAdminHCP User ────────────────────────────────────────
info "Step 6: Creating sysadminhcp system user..."
if ! id "$SYSADMINHCP_USER" &>/dev/null; then
  useradd -r -s /usr/sbin/nologin -d "$SYSADMINHCP_ROOT" "$SYSADMINHCP_USER"
  info "User $SYSADMINHCP_USER created"
else
  info "User $SYSADMINHCP_USER already exists"
fi

# journalctl access
usermod -a -G systemd-journal "$SYSADMINHCP_USER" 2>/dev/null || true
# BIND DNS access (Ubuntu group is 'bind')
usermod -a -G bind "$SYSADMINHCP_USER" 2>/dev/null || true
# apache group read access (File Manager reads client web files via group perms)
usermod -a -G apache "$SYSADMINHCP_USER" 2>/dev/null || true

# ACLs so sysadminhcp can read system log files
setfacl -R -m u:$SYSADMINHCP_USER:rX /var/log/apache2/ 2>/dev/null || true
setfacl -R -m u:$SYSADMINHCP_USER:rX /var/log/mysql/ 2>/dev/null || true
setfacl -m u:$SYSADMINHCP_USER:r /var/log/syslog 2>/dev/null || true

# ─── Step 7: Create Directory Structure ─────────────────────────────────────
info "Step 7: Creating directory structure..."
mkdir -p "$SYSADMINHCP_ROOT"/{httpdocs,data,etc,file/template,file/ssl,backup,log,tmp}
mkdir -p "$SYSADMINHCP_ROOT/httpdocs/web-console"
mkdir -p /var/log/sysadminhcp
mkdir -p /var/tmp/sysadminhcp
mkdir -p /var/run/sysadminhcp
mkdir -p /var/cache/sysadminhcp
mkdir -p /var/lib/sysadminhcp/pma-tokens

# ─── Step 8: Install SysAdminHCP Application ────────────────────────────────
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
    error "No pre-built dist/ and no src/ to build from. Copy dist/ or src/ to the installer directory."
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

# Copy helper scripts
mkdir -p "$SYSADMINHCP_ROOT/scripts"
if [[ -f "$REPO_DIR/scripts/install-qmail-toaster.sh" ]]; then
  cp "$REPO_DIR/scripts/install-qmail-toaster.sh" "$SYSADMINHCP_ROOT/scripts/install-qmail-toaster.sh"
  chmod 755 "$SYSADMINHCP_ROOT/scripts/install-qmail-toaster.sh"
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

# ─── Step 8.5: Install qmail-queue rate-limit + DKIM-signing wrapper ───────
# python3-dkim (dkimpy) provides the `dkim` module dkim-sign-message.py imports — this
# build's spamdyke has no DKIM support at all, so Ubuntu signs outbound mail via the
# qmail-queue wrapper instead (see enableDkimUbuntu() in mailService.ts).
apt-get install -y python3-dkim 2>/dev/null || warn "python3-dkim install failed — DKIM signing will be unavailable until installed manually"

if [[ -f /var/qmail/bin/qmail-queue && -f "$REPO_DIR/deploy/qmail-queue-check.sh" ]]; then
  info "Step 8.5: Installing qmail-queue rate-limit + DKIM wrapper..."
  if [[ ! -f /var/qmail/bin/qmail-queue.real ]]; then
    cp -p /var/qmail/bin/qmail-queue /var/qmail/bin/qmail-queue.real
    info "Original qmail-queue backed up to qmail-queue.real"
  fi
  cp "$REPO_DIR/deploy/qmail-queue-check.sh" /var/qmail/bin/qmail-queue
  chmod 755 /var/qmail/bin/qmail-queue
  chown root:root /var/qmail/bin/qmail-queue
  if [[ -f "$REPO_DIR/deploy/dkim-sign-message.py" ]]; then
    cp "$REPO_DIR/deploy/dkim-sign-message.py" /var/qmail/bin/dkim-sign-message.py
    chmod 755 /var/qmail/bin/dkim-sign-message.py
    chown root:root /var/qmail/bin/dkim-sign-message.py
  fi
  mkdir -p /var/lib/sysadminhcp/email-rate
  chown -R vpopmail /var/lib/sysadminhcp/email-rate 2>/dev/null || true
  mkdir -p /var/log/sysadminhcp
  touch /var/qmail/control/sysadminhcp-ratelimits 2>/dev/null || true
  info "qmail-queue wrapper installed — rate limiting + DKIM signing active"
else
  info "Step 8.5: qmail not present or wrapper not found — skipping queue wrapper"
fi

# ─── Step 9: Configure Environment ─────────────────────────────────────────
info "Step 9: Configuring environment..."

SESSION_SECRET=$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p -c 64 | head -c 64)
COOKIE_SECRET=$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p -c 64 | head -c 64)
MYSQL_ROOT_PASS='kloxoroot'

cat > "$SYSADMINHCP_ROOT/etc/sysadminhcp.env" << EOF
# SysAdminHCP Environment Configuration
# Generated by install-ubuntu22.sh on $(date -u '+%Y-%m-%d %H:%M:%S UTC')
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
SYSADMINHCP_CORS_ORIGIN=*
SYSADMINHCP_DEBUG=false
NODE_ENV=production
SYSADMINHCP_DEFAULT_WEB=apache
SYSADMINHCP_DEFAULT_DNS=bind
SYSADMINHCP_DEFAULT_MAIL=qmail
SYSADMINHCP_DEFAULT_FTP=pure-ftpd
SYSADMINHCP_DEFAULT_DB=mysql
# MySQL credentials (used by SysAdminHCP for database management)
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

# Sudoers for the panel user (Ubuntu paths; apt-get instead of dnf)
rm -f /etc/sudoers.d/sysadminhcp-logs
cat > /etc/sudoers.d/sysadminhcp << 'SUDOEOF'
Defaults:sysadminhcp env_keep += "DEBIAN_FRONTEND"
sysadminhcp ALL=(root) NOPASSWD: /usr/bin/tail, /usr/bin/cat, /usr/bin/touch, /usr/bin/journalctl, /usr/local/sysadminhcp/scripts/install-qmail-toaster.sh, /usr/bin/cp, /usr/bin/mv, /usr/bin/chmod, /usr/bin/chown, /usr/bin/find, /usr/bin/mkdir, /usr/bin/rm, /usr/bin/systemctl, /bin/systemctl, /usr/bin/tcprules, /usr/sbin/useradd, /usr/sbin/groupadd, /usr/bin/id, /usr/sbin/usermod, /home/vpopmail/bin/vadddomain, /home/vpopmail/bin/vdeldomain, /home/vpopmail/bin/vadduser, /home/vpopmail/bin/vdeluser, /home/vpopmail/bin/vchangepw, /home/vpopmail/bin/vpasswd, /home/vpopmail/bin/vsetuserquota, /home/vpopmail/bin/vmoduser, /home/vpopmail/bin/vmoddomlimits, /home/vpopmail/bin/vdominfo, /home/vpopmail/bin/vuserinfo, /usr/bin/apt-get, /usr/bin/apt, /usr/bin/dpkg, /usr/bin/add-apt-repository, /usr/bin/setfacl, /usr/bin/firewall-cmd, /usr/sbin/iptables, /sbin/iptables, /usr/bin/freshclam, /usr/bin/fail2ban-client, /bin/bash, /usr/bin/bash, /root/.acme.sh/acme.sh, /usr/bin/openssl
SUDOEOF
chmod 440 /etc/sudoers.d/sysadminhcp
visudo -c && info "sudoers validated OK" || warn "sudoers validation failed — check /etc/sudoers.d/sysadminhcp"

# GoAccess + daily stats cron
apt-get update -y 2>/dev/null || true
GOACCESS_LOG=$(apt-get install -y goaccess 2>&1) || true
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

# Self-signed panel SSL certificate
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
fi

# ACLs for BIND DNS access (WSL does not honor supplementary group permissions)
setfacl -m u:$SYSADMINHCP_USER:rw /etc/bind/named.conf 2>/dev/null || true
setfacl -R -m u:$SYSADMINHCP_USER:rwx /etc/bind/ 2>/dev/null || true
setfacl -R -m u:$SYSADMINHCP_USER:rwx /var/named/ 2>/dev/null || true
setfacl -d -m u:$SYSADMINHCP_USER:rwX /var/named/ 2>/dev/null || true

# File Manager ACLs on existing client home dirs
info "Setting File Manager ACLs on existing client home directories..."
for homedir in /home/*/; do
  owner=$(stat -c '%U' "$homedir" 2>/dev/null)
  if id "$owner" &>/dev/null && [[ "$owner" != "root" && "$owner" != "$SYSADMINHCP_USER" && "$owner" != "vpopmail" ]]; then
    setfacl -m u:$SYSADMINHCP_USER:rwx "$homedir" 2>/dev/null || true
    setfacl -d -m u:$SYSADMINHCP_USER:rwX "$homedir" 2>/dev/null || true
    info "  ACL set: $homedir (owner: $owner)"
  fi
done

# ─── Step 11: Install Systemd Service ──────────────────────────────────────
info "Step 11: Installing systemd service..."

if [[ $WSL_MODE -eq 1 ]]; then
  info "WSL detected: using WSL-compatible service configuration (no ProtectSystem)"
  cat > /etc/systemd/system/sysadminhcp.service << 'SVCEOF'
[Unit]
Description=SysAdminHCP Control Panel (Node.js)
After=network.target mariadb.service apache2.service named.service
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

# Security hardening (WSL-compatible - no namespace restrictions)
NoNewPrivileges=false
PrivateTmp=true
ProtectHome=no

# Environment
Environment=NODE_ENV=production
EnvironmentFile=-/usr/local/sysadminhcp/etc/sysadminhcp.env

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
SVCEOF
else
  info "Bare metal detected: using hardened service configuration"
  cat > /etc/systemd/system/sysadminhcp.service << 'SVCEOF'
[Unit]
Description=SysAdminHCP Control Panel (Node.js)
After=network.target mariadb.service apache2.service named.service
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

# Security hardening
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

# Environment
Environment=NODE_ENV=production
EnvironmentFile=-/usr/local/sysadminhcp/etc/sysadminhcp.env

# Resource limits
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

# logrotate: persist log ACLs across rotation
cat > /etc/logrotate.d/sysadminhcp-acl << 'LREOF'
/var/log/apache2/error.log {
    postrotate
        setfacl -R -m u:sysadminhcp:rX /var/log/apache2/ 2>/dev/null || true
    endscript
}
/var/log/mysql/error.log {
    postrotate
        setfacl -R -m u:sysadminhcp:rX /var/log/mysql/ 2>/dev/null || true
    endscript
}
/var/log/syslog {
    postrotate
        setfacl -m u:sysadminhcp:r /var/log/syslog 2>/dev/null || true
    endscript
}
LREOF
chmod 644 /etc/logrotate.d/sysadminhcp-acl

# ─── Step 12: Configure Firewall (firewalld) ────────────────────────────────
info "Step 12: Configuring firewall..."
systemctl enable --now firewalld 2>/dev/null || true
if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
  firewall-cmd --permanent --add-port=7778/tcp    # Panel HTTP
  firewall-cmd --permanent --add-port=7777/tcp    # Panel HTTPS
  firewall-cmd --permanent --add-service=http
  firewall-cmd --permanent --add-service=https
  firewall-cmd --permanent --add-service=dns
  firewall-cmd --permanent --add-service=ftp
  firewall-cmd --permanent --add-service=smtp 2>/dev/null || firewall-cmd --permanent --add-port=25/tcp
  firewall-cmd --permanent --add-port=587/tcp
  firewall-cmd --permanent --add-port=143/tcp --add-port=993/tcp --add-port=110/tcp --add-port=995/tcp
  firewall-cmd --permanent --add-port=30000-31000/tcp  # FTP passive
  firewall-cmd --reload
  info "Firewall rules added (7778, 7777, 80, 443, 53, 21, 25, 587, IMAP/POP, 30000-31000)"
elif [[ $WSL_MODE -eq 1 ]]; then
  info "WSL detected: skipping firewall configuration (Windows handles networking)"
else
  warn "firewalld not running. Skipping firewall configuration."
fi

# ─── Step 12.5: Configure Security Tools ────────────────────────────────────
info "Step 12.5: Configuring security tools..."

if command -v fail2ban-client &>/dev/null; then
  if [[ ! -f /etc/fail2ban/jail.local ]]; then
    info "Creating Fail2ban jail.local configuration..."
    cat > /etc/fail2ban/jail.local << 'F2BEOF'
[DEFAULT]
# Ban for 1 hour, check 10 minute windows, max 5 retries
bantime  = 3600
findtime = 600
maxretry = 5
backend  = auto
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s

[apache-auth]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s

[pure-ftpd]
enabled  = true
port     = ftp,ftp-data,ftps,ftps-data
logpath  = %(syslog_ftp)s
backend  = %(syslog_backend)s
F2BEOF
    info "Fail2ban jail.local created (SSH, Apache auth, FTP jails enabled)"
  fi
  systemctl enable fail2ban 2>/dev/null || true
fi

# ClamAV initial database update
if command -v freshclam &>/dev/null; then
  if [[ ! -f /var/lib/clamav/main.cvd ]] && [[ ! -f /var/lib/clamav/main.cld ]]; then
    info "Running initial ClamAV database update (this may take a moment)..."
    systemctl stop clamav-freshclam 2>/dev/null || true
    freshclam 2>/dev/null && info "ClamAV DB updated" || warn "ClamAV DB update failed — run freshclam manually after install"
  fi
  systemctl enable --now clamav-freshclam 2>/dev/null || true
fi

# ─── Step 13: AppArmor notes (Ubuntu's SELinux counterpart) ─────────────────
info "Step 13: AppArmor configured (named override for /var/named). No SELinux on Ubuntu."

# ─── Step 14: Start Services ───────────────────────────────────────────────
info "Step 14: Starting services..."

# MariaDB
info "Starting MariaDB..."
systemctl enable mariadb
systemctl start mariadb

# Bind MariaDB to localhost only (Ubuntu default is already 127.0.0.1, enforce anyway)
if [[ -f /etc/mysql/mariadb.conf.d/50-server.cnf ]]; then
  if grep -qE '^\s*bind-address\s*=' /etc/mysql/mariadb.conf.d/50-server.cnf; then
    sed -i 's/^\s*bind-address\s*=.*/bind-address = 127.0.0.1/' /etc/mysql/mariadb.conf.d/50-server.cnf
  else
    sed -i '/^\[mysqld\]/a bind-address = 127.0.0.1' /etc/mysql/mariadb.conf.d/50-server.cnf
  fi
  systemctl restart mariadb
  info "MariaDB bound to 127.0.0.1"
fi

# Secure MariaDB on fresh install
if [[ $FRESH_INSTALL -eq 1 ]]; then
  for i in $(seq 1 30); do
    if mysqladmin ping -u root 2>/dev/null; then break; fi
    sleep 1
  done

  if mysqladmin ping -u root 2>/dev/null; then
    info "Securing MariaDB installation..."
    mysql -u root << EOSQL 2>/dev/null || warn "MariaDB secure install partially failed (may already be secured)"
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
    info "MySQL root password file created at /usr/local/sysadminhcp/etc/mysql-root-password"
    warn "MariaDB root password set to 'kloxoroot' - CHANGE THIS IMMEDIATELY!"
  else
    warn "MariaDB not responding after 30s - skipping secure installation"
  fi
else
  info "Existing installation - skipping MariaDB secure installation"
fi

# Apache
systemctl enable apache2 2>/dev/null || true
systemctl restart apache2 2>/dev/null || warn "Apache failed to start - may need manual configuration"

# BIND
systemctl enable named 2>/dev/null || systemctl enable bind9 2>/dev/null || true
systemctl restart named 2>/dev/null || systemctl restart bind9 2>/dev/null || warn "BIND (named) failed to start"

# ── Pure-FTPd MySQL Authentication ──────────────────────────────────────────
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
  info "pureftpd MySQL database and users table ready"
fi

# Debian pure-ftpd reads /etc/pure-ftpd/db/mysql.conf
mkdir -p /etc/pure-ftpd/db /etc/pure-ftpd/conf
cat > /etc/pure-ftpd/db/mysql.conf << FTPMYCNF
MYSQLSocket      /run/mysqld/mysqld.sock
MYSQLUser        root
MYSQLPassword    ${MYSQL_ROOT_PASS}
MYSQLDatabase    pureftpd
MYSQLCrypt       crypt
MYSQLGetPW       SELECT Password FROM users WHERE User='\L'
MYSQLGetUID      SELECT Uid FROM users WHERE User='\L'
MYSQLGetGID      SELECT Gid FROM users WHERE User='\L'
MYSQLGetDir      SELECT Dir FROM users WHERE User='\L'
FTPMYCNF
chmod 600 /etc/pure-ftpd/db/mysql.conf
# RHEL-compat path for anything referencing pureftpd-mysql.conf
ln -sf /etc/pure-ftpd/db/mysql.conf /etc/pure-ftpd/pureftpd-mysql.conf

# Debian one-file-per-setting config style
echo no                > /etc/pure-ftpd/conf/PAMAuthentication
echo "30000 31000"     > /etc/pure-ftpd/conf/PassivePortRange
echo yes               > /etc/pure-ftpd/conf/CreateHomeDir 2>/dev/null || true
info "Pure-FTPd: PAM off, MySQL auth on, passive ports 30000-31000"

systemctl enable pure-ftpd-mysql 2>/dev/null || systemctl enable pure-ftpd 2>/dev/null || true
systemctl restart pure-ftpd-mysql 2>/dev/null || systemctl restart pure-ftpd 2>/dev/null || warn "Pure-FTPd failed to start"

# PHP-FPM
systemctl enable "php$PHPV-fpm" 2>/dev/null || true
systemctl restart "php$PHPV-fpm" 2>/dev/null || warn "PHP-FPM failed to start"

# Qmail services
systemctl start qmail-send 2>/dev/null || warn "qmail-send failed to start - check: journalctl -u qmail-send"
sleep 2
systemctl start qmail-smtp qmail-submission 2>/dev/null || warn "qmail SMTP failed to start - check: journalctl -u qmail-smtp"
sleep 2
if systemctl is-active --quiet qmail-send && systemctl is-active --quiet qmail-smtp; then
  info "Qmail is running (send + SMTP on ports 25 and 587)"
else
  warn "One or more qmail services not running - check: systemctl status qmail-send qmail-smtp qmail-submission"
fi

systemctl enable dovecot 2>/dev/null || true
systemctl restart dovecot 2>/dev/null || warn "Dovecot failed to start"
systemctl enable spamassassin 2>/dev/null || systemctl enable spamd 2>/dev/null || true
systemctl start spamassassin 2>/dev/null || systemctl start spamd 2>/dev/null || warn "SpamAssassin failed to start"
systemctl enable clamav-daemon 2>/dev/null || true
systemctl start clamav-daemon 2>/dev/null || warn "ClamAV daemon failed to start (DB may still be downloading)"

systemctl enable fail2ban 2>/dev/null || true
systemctl start fail2ban 2>/dev/null || warn "Fail2ban failed to start"

# ── vpopmail + sysadminhcp MySQL setup ──────────────────────────────────────
if command -v mysql &>/dev/null && systemctl is-active --quiet mariadb; then
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
    info "vpopmail MySQL tables created"
    # ALTER USER alongside CREATE USER IF NOT EXISTS (matching the vpopmail user block above) —
    # without it, a re-run whose extracted $KLOXOJRA_DB_PASS ever drifts from what MySQL actually
    # has on file for this user leaves MySQL's real password stuck at whatever it was, silently
    # breaking Dovecot/Pure-FTPd MySQL auth for every mailbox on the server until fixed by hand.
    mysql -u root -p"${MYSQL_ROOT_PASS}" <<EOSQL2 2>/dev/null || warn "sysadminhcp database user setup failed"
CREATE DATABASE IF NOT EXISTS sysadminhcp;
CREATE USER IF NOT EXISTS 'sysadminhcp'@'localhost' IDENTIFIED BY '${KLOXOJRA_DB_PASS}';
ALTER USER 'sysadminhcp'@'localhost' IDENTIFIED BY '${KLOXOJRA_DB_PASS}';
GRANT ALL PRIVILEGES ON sysadminhcp.* TO 'sysadminhcp'@'localhost';
GRANT SELECT ON vpopmail.* TO 'sysadminhcp'@'localhost';
FLUSH PRIVILEGES;
EOSQL2
    info "sysadminhcp database user created"
    mkdir -p /home/vpopmail/etc
    echo "localhost|0|vpopmail|${VPOPMAIL_DB_PASS}|vpopmail" > /home/vpopmail/etc/vpopmail.mysql
    chown vpopmail:vchkpw /home/vpopmail/etc/vpopmail.mysql 2>/dev/null || true
    chmod 640 /home/vpopmail/etc/vpopmail.mysql 2>/dev/null || true
    info "vpopmail database configured"
  fi

  # .my.cnf for panel MySQL access
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

# ─── Step 14.5: Install phpMyAdmin ──────────────────────────────────────────
info "Step 14.5: Setting up phpMyAdmin..."
if [[ ! -d /usr/share/phpmyadmin ]]; then
  # Preseed debconf so no interactive prompts (we configure Apache ourselves)
  echo 'phpmyadmin phpmyadmin/dbconfig-install boolean false' | debconf-set-selections
  echo 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect' | debconf-set-selections
  apt-get install -y phpmyadmin 2>/dev/null || warn "phpMyAdmin installation failed — install manually with: apt-get install -y phpmyadmin"
fi

# RHEL-compat: capitalized paths the panel + signon config reference
[[ -d /usr/share/phpmyadmin && ! -e /usr/share/phpMyAdmin ]] && ln -s /usr/share/phpmyadmin /usr/share/phpMyAdmin
[[ -d /etc/phpmyadmin && ! -e /etc/phpMyAdmin ]] && ln -s /etc/phpmyadmin /etc/phpMyAdmin

mkdir -p /var/lib/sysadminhcp/pma-tokens
chown sysadminhcp:sysadminhcp /var/lib/sysadminhcp/pma-tokens
chmod 755 /var/lib/sysadminhcp/pma-tokens

if [[ -d /usr/share/phpmyadmin ]]; then
  mkdir -p /usr/share/phpmyadmin/sysadminhcp-signon

  if [[ -f "$REPO_DIR/pma-signon/signon.php" ]]; then
    cp "$REPO_DIR/pma-signon/signon.php" /usr/share/phpmyadmin/sysadminhcp-signon/signon.php
    chown -R apache:apache /usr/share/phpmyadmin/sysadminhcp-signon
    info "phpMyAdmin signon script deployed"
  else
    warn "pma-signon/signon.php not found in source — phpMyAdmin SSO will not work until deployed manually"
  fi

  if [[ -f "$REPO_DIR/pma-signon/config.inc.php" ]]; then
    cp "$REPO_DIR/pma-signon/config.inc.php" /etc/phpmyadmin/config.inc.php
    # Give this install its own blowfish_secret rather than the placeholder in source control.
    PMA_BLOWFISH_SECRET=$(openssl rand -hex 16)
    sed -i "s/__PMA_BLOWFISH_SECRET__/${PMA_BLOWFISH_SECRET}/" /etc/phpmyadmin/config.inc.php
    info "phpMyAdmin config deployed (signon auth mode, random blowfish secret)"
  fi

  # Apache config: PMA aliases + SSO endpoint (through the compat conf.d dir)
  cat > /etc/httpd/conf.d/sysadminhcp-pma.conf << 'APACHEEOF'
# SysAdminHCP phpMyAdmin + SSO endpoint
Alias /phpMyAdmin /usr/share/phpmyadmin
Alias /phpmyadmin /usr/share/phpmyadmin
Alias /pma-signon /usr/share/phpmyadmin/sysadminhcp-signon

<Directory /usr/share/phpmyadmin>
    Require all granted
    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php-fpm/www.sock|fcgi://localhost"
    </FilesMatch>
</Directory>

<Directory /usr/share/phpmyadmin/sysadminhcp-signon>
    Require all granted
    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php-fpm/www.sock|fcgi://localhost"
    </FilesMatch>
</Directory>
APACHEEOF
  info "Apache phpMyAdmin config deployed"

  systemctl restart apache2 2>/dev/null || true
fi

# ─── Step 14.6: Install RainLoop Webmail ────────────────────────────────────
info "Step 14.6: Installing RainLoop webmail..."

RAINLOOP_DIR="/var/www/rainloop"
if [[ -f "$RAINLOOP_DIR/index.php" ]]; then
  info "RainLoop already installed at $RAINLOOP_DIR — skipping"
else
  mkdir -p "$RAINLOOP_DIR"
  mkdir -p "$RAINLOOP_DIR/data/_data_/_default_/configs"
  mkdir -p "$RAINLOOP_DIR/data/_data_/_default_/domains"
  mkdir -p "$RAINLOOP_DIR/data/_data_/_default_/storage"

  info "Downloading RainLoop..."
  curl -sL https://www.rainloop.net/repository/webmail/rainloop-latest.zip -o /tmp/rainloop.zip
  if [[ -f /tmp/rainloop.zip && -s /tmp/rainloop.zip ]]; then
    unzip -o /tmp/rainloop.zip -d "$RAINLOOP_DIR" 2>/dev/null || warn "RainLoop unzip failed"
    rm -f /tmp/rainloop.zip
    info "RainLoop downloaded and extracted"
  else
    warn "RainLoop download failed — install manually from the Webmail section"
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
  info "RainLoop configured"
fi

# Webmail Apache vhost (same file the panel manages on RHEL)
cat > /etc/httpd/conf.d/webmail.conf << 'WMEOF'
# SysAdminHCP Webmail (RainLoop)
# Auto-generated by installer — serves webmail.* for all domains

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

    ErrorLog /var/log/apache2/webmail_error.log
    CustomLog /var/log/apache2/webmail_access.log combined
</VirtualHost>
WMEOF

# PHP-FPM pool for webmail (lands in the default version's pool.d via symlink)
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

; Security
php_admin_value[open_basedir] = /var/www/roundcube:/var/www/roundcube/public_html:/var/www/rainloop:/tmp:/var/log/php-fpm:/var/lib/php/session:/var/log/roundcube
php_admin_value[disable_functions] = exec,passthru,shell_exec,system
FPMEOF

systemctl restart "php$PHPV-fpm" 2>/dev/null || true
info "Webmail Apache vhost and PHP-FPM pool configured"

# ─── Step 14.7: Install Roundcube Webmail ───────────────────────────────────
info "Step 14.7: Installing Roundcube webmail..."

ROUNDCUBE_DIR="/var/www/roundcube"
ROUNDCUBE_WEBROOT="$ROUNDCUBE_DIR/public_html"
if [[ -f "$ROUNDCUBE_WEBROOT/index.php" ]]; then
  info "Roundcube already installed at $ROUNDCUBE_DIR — skipping"
else
  # Ubuntu 22.04 ships PHP 8.1, 24.04 ships 8.3 — both satisfy RC >= 1.6 (needs >= 8.1)
  apt-get install -y php-intl php-mbstring php-xml php-gd php-zip php-ldap 2>/dev/null || true

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

    info "Roundcube $RC_VERSION installed and configured at $ROUNDCUBE_DIR"
    info "(default PHP $PHPV >= 8.1 — no separate php83 pool needed on Ubuntu)"
  fi
fi

# ─── Step 14.8: Install acme.sh (Let's Encrypt client) ──────────────────────
info "Step 14.8: Installing acme.sh (Let's Encrypt client)..."
if [[ -x /root/.acme.sh/acme.sh ]]; then
  info "acme.sh already installed — skipping"
else
  if curl -sSL https://get.acme.sh | sh 2>&1 | tail -5; then
    [[ -x /root/.acme.sh/acme.sh ]] && info "acme.sh installed successfully" || warn "acme.sh binary not found after install"
  else
    warn "acme.sh installation failed — Let's Encrypt SSL issuance will not work"
  fi
fi
if [[ -x /root/.acme.sh/acme.sh ]]; then
  /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt 2>/dev/null || true
fi

# ─── Step 14.9: Apply client:apache group ownership to all domain web roots ─
info "Step 14.9: Applying client:apache ownership to all domain web roots..."
for homedir in /home/*/; do
  [[ -d "$homedir" ]] || continue
  clientname=$(basename "$homedir")
  case "$clientname" in vpopmail|root|sysadminhcp|named|bind|apache|www-data|mysql|qmail|qmaild|qmaill|qmailp|qmailq|qmailr|qmails|alias|nobody) continue ;; esac
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
    fi

    for logdir in "$statsdir" "$logsdir"; do
      [[ -d "$logdir" ]] || continue
      chown -R apache:apache "$logdir" 2>/dev/null || true
      chmod 750 "$logdir" 2>/dev/null || true
      find "$logdir" -maxdepth 1 -name '*.log' -user root -exec chown apache:apache {} \; 2>/dev/null || true
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

# ─── Step 14.10: Central ACME challenge directory for Let's Encrypt ─────────
info "Step 14.10: Creating central ACME challenge directory..."
mkdir -p /var/www/acme-challenge/.well-known/acme-challenge
chown -R apache:apache /var/www/acme-challenge
chmod -R 755 /var/www/acme-challenge

cat > /etc/httpd/conf.d/acme-challenge.conf << 'EOF'
# Central ACME / Let's Encrypt HTTP-01 challenge handler
# This alias applies globally to all virtual hosts on port 80.
Alias /.well-known/acme-challenge /var/www/acme-challenge/.well-known/acme-challenge

<Directory "/var/www/acme-challenge/.well-known/acme-challenge">
    Options None
    AllowOverride None
    Require all granted
</Directory>
EOF

systemctl reload apache2 2>/dev/null || true
info "Central ACME challenge directory created at /var/www/acme-challenge"

# ─── Write revision.json (drives version number in sidebar + About page) ───
# Without this file, GET /system/revision returns null fields and the panel
# shows no version anywhere in the UI, even though the app itself runs fine.
PANEL_VERSION=$(grep -m1 '"version"' "$REPO_DIR/package.json" | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)
[[ -z "$PANEL_VERSION" ]] && PANEL_VERSION="unknown"
cat > "$SYSADMINHCP_ROOT/etc/revision.json" << REVEOF
{
  "version": "$PANEL_VERSION",
  "deployedAt": "$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')",
  "description": "Installed via install-ubuntu22.sh"
}
REVEOF
chown $SYSADMINHCP_USER:$SYSADMINHCP_GROUP "$SYSADMINHCP_ROOT/etc/revision.json"
chmod 644 "$SYSADMINHCP_ROOT/etc/revision.json"
info "revision.json written (version $PANEL_VERSION)"

# ─── Start SysAdminHCP ──────────────────────────────────────────────────────
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
    HEALTH_OK=1
    break
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
  info "Database file created: $SYSADMINHCP_ROOT/data/sysadminhcp.db"
else
  warn "Database file not found — it is seeded automatically on first startup."
fi

# ─── Done ──────────────────────────────────────────────────────────────────
echo ""
info "======================================================"
info "  SysAdminHCP Control Panel Installation Complete!"
info "  (Ubuntu $VERSION_ID with RHEL-compat layer)"
info "======================================================"
echo ""
info "  Web UI:     https://$(hostname -I | awk '{print $1}'):7777/display"
info "  (HTTP port 7778 redirects to HTTPS automatically)"
info "  Admin User: admin"
info "  Admin Pass: admin"
echo ""
warn "  ⚠️  CHANGE THE DEFAULT PASSWORD IMMEDIATELY!"
warn "  ⚠️  SECURE THE MARIADB ROOT PASSWORD!"
echo ""
info "  RHEL-compat layer active:"
info "    systemctl restart httpd     → apache2"
info "    systemctl restart php-fpm   → php$PHPV-fpm"
info "    systemctl restart named     → bind9"
info "    /etc/httpd/conf.d/          → included by apache2.conf"
info "    /var/named/                 → BIND zone files (AppArmor override applied)"
info "    apache user/group           → Apache + PHP-FPM run user"
echo ""
info "  Let's Encrypt SSL:"
info "    Issue certificates via Admin Portal → Domains → SSL → Let's Encrypt"
info "    Certificates are stored in /etc/httpd/ssl/<domain>/ after issuance"
echo ""
info "  phpMyAdmin:"
info "    Access via Admin Portal → Hosting → phpMyAdmin (SSO auto-login)"
info "    MySQL root password stored in: $SYSADMINHCP_ROOT/etc/mysql-root-password"
echo ""
info "  Webmail:"
info "    RainLoop:  https://webmail.yourdomain.com  (admin panel: /?admin)"
info "    Roundcube: switchable via Admin Portal → Webmail"
echo ""
info "  Mail stack (source-built, QmailToaster-compatible layout):"
info "    qmail (notqmail $NOTQMAIL_VERSION) at /var/qmail"
info "    vpopmail $VPOPMAIL_VERSION at /home/vpopmail (MySQL auth)"
info "    spamdyke provides SMTP AUTH + TLS on ports 25/587"
info "    Dovecot IMAP/POP3 with vpopmail MySQL auth"
info "    systemctl status qmail-send qmail-smtp qmail-submission"
echo ""
info "  PHP version management (via Admin Portal → Server → PHP Modules):"
info "    PHP $PHPV is installed (Ubuntu default)."
info "    Additional versions (7.4–8.4) come from the ondrej/php PPA —"
info "    use the 'Install Remi Repo' button (installs the PPA on Ubuntu),"
info "    then install the desired version from the same page."
echo ""
info "  Security (via Admin Portal → Security):"
info "    firewalld is active (ufw disabled) — Blocked/Whitelist IPs work as on RHEL"
info "    Fail2ban jails: sshd, apache-auth, pure-ftpd"
echo ""
warn "  ⚠️  SECURITY CHECKLIST:"
warn "    1. Change the default admin password (Admin Portal → Settings)"
warn "    2. Disable SSH password auth if using keys (Security → SSH Config)"
warn "    3. Review Fail2ban jails active: fail2ban-client status"
warn "    4. Run an initial ClamAV scan: Security → ClamAV → Run Scan"
echo ""
info "  Log files:"
info "    /var/log/sysadminhcp/"
info "    journalctl -u sysadminhcp -f"
echo ""

if [[ $WSL_MODE -eq 1 ]]; then
  info "  WSL Notes:"
  info "    - systemd must remain enabled in /etc/wsl.conf ([boot] systemd=true)"
  info "    - Restart WSL after changes: wsl.exe --shutdown"
  echo ""
fi
