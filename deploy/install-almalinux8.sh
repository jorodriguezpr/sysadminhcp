#!/bin/bash
# ============================================================================
# SysAdminHCP Control Panel - AlmaLinux 8 Installation Script
# ============================================================================
# This script installs SysAdminHCP on AlmaLinux 8 (or compatible RHEL 8 clones)
# running under WSL or bare metal.
#
# Differences from AlmaLinux 9 installer:
#   - Uses yum instead of dnf for some operations
#   - Uses PowerTools repo instead of CRB
#   - Uses EL8 QMT packages instead of EL9
#   - Uses yum-config-manager instead of dnf config-manager
#   - MariaDB 10.3 (default on EL8) instead of 10.6+
#   - PHP 7.2/7.4 from AppStream instead of 8.0
#
# Usage:
#   sudo bash install-almalinux8.sh
# ============================================================================

set -euo pipefail

# Track if this is a fresh install or upgrade
FRESH_INSTALL=0

# ─── Configuration ──────────────────────────────────────────────────────────
SYSADMINHCP_ROOT="/usr/local/sysadminhcp"
SYSADMINHCP_USER="sysadminhcp"
SYSADMINHCP_GROUP="sysadminhcp"
SYSADMINHCP_SERVICE="sysadminhcp"
NODE_MAJOR=20
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
info "SysAdminHCP Control Panel Installer for AlmaLinux 8"
info "================================================"

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

if [[ "$ID" != "almalinux" && "$ID" != "rocky" && "$ID" != "centos" && "$ID" != "rhel" ]]; then
  warn "This script is designed for AlmaLinux 8 / RHEL 8 clones."
  warn "Detected ID: $ID. Proceeding anyway..."
fi

# Check major version
MAJOR_VER=$(echo "$VERSION_ID" | cut -d. -f1)
if [[ "$MAJOR_VER" != "8" ]]; then
  warn "This script is designed for EL8 (AlmaLinux 8, Rocky 8, etc.)."
  warn "Detected major version: $MAJOR_VER. For EL9, use install-almalinux9.sh."
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# Check WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
  info "Running under WSL (Windows Subsystem for Linux)"
  WSL_MODE=1
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

# ─── Pre-flight: Disable SELinux ────────────────────────────────────────────
# SELinux enforcing mode blocks Apache from writing log/stat files inside /home/
# (home_root_t context inheritance) and conflicts with qmail/vpopmail operations.
# cPanel/Plesk and all major control panels require SELinux disabled.
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
# pins an old initscripts version that conflicts with the newer one `yum
# update` wants to pull in ("cannot install both initscripts-X and
# initscripts-Y"). Some AlmaLinux cloud images ship it pre-installed even
# though the OS no longer needs it for networking — remove it first if
# present, before the update runs.
yum remove -y network-scripts 2>/dev/null || true
yum update -y

# ─── Step 2: Install EPEL and Remi Repositories ─────────────────────────────
info "Step 2: Installing EPEL and Remi repositories..."
yum install -y epel-release

# Remi repo: required for PHP 8.x packages on EL8 (php80, php81, php82, php83, etc.)
# Also needed for oniguruma5php (libonig.so.105) which PHP 8.1+ depends on.
if ! rpm -q remi-release &>/dev/null; then
  info "Installing Remi repository (needed for PHP 8.x on EL8)..."
  yum install -y https://rpms.remirepo.net/enterprise/remi-release-8.rpm 2>/dev/null || \
    warn "Remi repo install failed — PHP 8.x multi-version support will not work; install manually: yum install -y https://rpms.remirepo.net/enterprise/remi-release-8.rpm"
fi

# ─── Step 3: Install Node.js ───────────────────────────────────────────────
info "Step 3: Installing Node.js $NODE_MAJOR.x..."
if ! command -v node &>/dev/null; then
  yum install -y curl
  curl -fsSL https://rpm.nodesource.com/setup_$NODE_MAJOR.x | bash -
  yum install -y nodejs
fi
NODE_VERSION=$(node --version)
info "Node.js installed: $NODE_VERSION"

# ─── Step 4: Install Build Tools (for native npm modules) ──────────────────
info "Step 4: Installing build tools..."
yum install -y gcc-c++ make python3

# ─── Step 5: Install Service Dependencies ───────────────────────────────────
info "Step 5: Installing service dependencies..."

# Enable PowerTools repo (EL8 equivalent to CRB on EL9)
info "Enabling PowerTools repository..."
yum config-manager --set-enabled powertools 2>/dev/null || yum-config-manager --enable powertools 2>/dev/null || true

# EL8-specific runtime libs required by PHP 8.1+:
#   oniguruma5php: libonig.so.105 (from remi-safe repo — newer than system oniguruma)
#   libsodium:     libsodium.so.23 (from EPEL)
#   capstone:      libcapstone.so.4 (from EPEL — required by PHP 8.2+)
# These must be installed before any PHP 8.1+ package install attempt.
info "Installing EL8 PHP 8.1+ runtime dependencies (oniguruma5php, libsodium, capstone)..."
yum install -y oniguruma5php libsodium capstone 2>/dev/null || \
  warn "Some EL8 PHP 8.1+ runtime libs could not be installed — PHP 8.3 may fail to install later; run manually: yum install -y oniguruma5php libsodium capstone"

# Web server (Apache by default)
yum install -y httpd httpd-devel mod_ssl

# DNS (BIND by default)
yum install -y bind bind-utils

# Mail (QmailToaster from official QMT repo - EL8 packages)
# Note: postfix is removed as it conflicts with qmail
yum remove -y postfix 2>/dev/null || true
userdel postfix 2>/dev/null || true

# Install QMT repo for EL8
# Note: EL8 QMT has no qmt-release RPM. The repo structure is different from EL9:
#   EL8: http://repo.whitehorsetc.com/8/testing/mariadb/x86_64/  (packages split by DB backend)
#   EL9: http://repo.whitehorsetc.com/9/testing/noarch/          (has qmt-release RPM)
# We create the repo config file manually pointing to the mariadb backend.
QMT_BASEURL="http://repo.whitehorsetc.com/8/testing/mariadb/x86_64"
cat > /etc/yum.repos.d/qat-testing.repo << QMTEOF
[qat-testing]
name=QmailToaster Testing (EL8 MariaDB)
baseurl=${QMT_BASEURL}
enabled=1
gpgcheck=0
sslverify=0
QMTEOF
info "QMT repo configured: $QMT_BASEURL"
yum clean all 2>/dev/null || true

# Install mysql-libs (needed by vpopmail alongside MariaDB)
yum install -y mysql-libs 2>/dev/null || true

# Install QMT packages that don't conflict with MariaDB
# These can be installed directly from the QMT repo
yum install -y --skip-broken \
  daemontools spamassassin ucspi-tcp libsrs2 spamdyke \
  autorespond control-panel qmailmrtg maildrop isoqlog ripmime \
  clamav clamd fetchmail 2>/dev/null || warn "Some QMT packages failed to install"

# Install QMT dovecot (replaces system dovecot - QMT version has vpopmail support)
# Remove system dovecot first to avoid conflicts
yum remove -y dovecot dovecot-mysql 2>/dev/null || true
yum install -y --skip-broken dovecot dovecot-mysql 2>/dev/null || warn "QMT dovecot install failed - will use system dovecot"

# Install QMT clamav (may conflict with EPEL clamav - try QMT first, fall back to EPEL)
yum install -y --skip-broken clamav clamd 2>/dev/null || warn "QMT clamav install failed - EPEL version already installed"

# Download and install vpopmail/qmail/ezmlm/simscan/qmailadmin/vqadmin with --nodeps
# (they need mysql-server which conflicts with MariaDB, but work fine with MariaDB)
# Download directly from QMT repo since yum download may not resolve deps correctly
cd /tmp
QMT_DL_URL="http://repo.whitehorsetc.com/8/testing/mariadb/x86_64"

# Download latest version of each package (use highest version number)
for pkg in vpopmail qmail ezmlm simscan qmailadmin vqadmin; do
  # Get the latest RPM filename from the repo directory listing
  latest=$(curl -sL "$QMT_DL_URL/" 2>/dev/null | grep -oP "${pkg}-[^\"]+\\.qt\\.el8\\.[^\"]+\\.rpm" | sort -V | tail -1 | sed 's/^"//;s/"$//')
  if [[ -n "$latest" ]]; then
    info "Downloading $latest..."
    curl -L -o "/tmp/$latest" "$QMT_DL_URL/$latest" 2>/dev/null || warn "Failed to download $latest"
  else
    # Fallback: try yum download
    yum download --enablerepo=qat-testing "$pkg" 2>/dev/null || warn "Failed to download $pkg"
  fi
done

# Install all downloaded QMT RPMs with --nodeps (they depend on mysql-server which conflicts with MariaDB)
rpm -ivh --nodeps /tmp/vpopmail-*.qt.el8.*.rpm 2>/dev/null || true
rpm -ivh --nodeps /tmp/qmail-*.qt.el8.*.rpm 2>/dev/null || true
rpm -ivh --nodeps /tmp/ezmlm-*.qt.el8.*.rpm 2>/dev/null || true
rpm -ivh --nodeps /tmp/simscan-*.qt.el8.*.rpm 2>/dev/null || true
rpm -ivh --nodeps /tmp/qmailadmin-*.qt.el8.*.rpm 2>/dev/null || true
rpm -ivh --nodeps /tmp/vqadmin-*.qt.el8.*.rpm 2>/dev/null || true

# Verify critical packages installed
if rpm -q vpopmail &>/dev/null && rpm -q qmail &>/dev/null; then
  info "Qmail and vpopmail installed successfully"
else
  warn "Qmail/vpopmail installation may have failed - check manually"
fi

# Clean up downloaded RPMs
rm -f /tmp/vpopmail-*.rpm /tmp/qmail-*.rpm /tmp/ezmlm-*.rpm /tmp/simscan-*.rpm /tmp/qmailadmin-*.rpm /tmp/vqadmin-*.rpm

# Create vpopmail user/group if not present
groupadd -g 89 vchkpw 2>/dev/null || true
useradd -u 89 -g 89 vpopmail -s '/sbin/nologin' 2>/dev/null || true

# Configure qmail
chkconfig qmail on 2>/dev/null || true
if [ -f /var/qmail/supervise/smtp/run ]; then
  sed -i 's/softlimit -m.*/softlimit -m 256000000 \\/' /var/qmail/supervise/smtp/run 2>/dev/null || true
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
# ("TLS_AES_256_GCM_SHA384:..." — the package-shipped spamdyke.conf default) to OpenSSL's
# legacy SSL_CTX_set_cipher_list() (the TLS <=1.2 API, which never accepted TLS 1.3 suite
# names — those need the separate SSL_CTX_set_ciphersuites() call spamdyke doesn't use).
# Older OpenSSL tolerated the mismatch; OpenSSL 3.2+ rejects it outright, logging "unable to
# set SSL/TLS cipher list" on every connection and silently breaking STARTTLS. Idempotent:
# strips any existing tls-cipher-list line (right or wrong) before appending the corrected one.
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

# Fix supervise directory permissions (must be 755 so supervise/svscan can access them)
for svc in smtp send smtps submission; do
  [ -d /var/qmail/supervise/$svc ] && chmod 755 /var/qmail/supervise/$svc
  [ -d /var/qmail/supervise/$svc/log ] && chmod 755 /var/qmail/supervise/$svc/log
  mkdir -p /var/qmail/supervise/$svc/log/supervise 2>/dev/null || true
done

# Configure clamav
if [ -f /etc/clamd.d/scan.conf ]; then
  sed -i 's/^#LocalSocket /LocalSocket /' /etc/clamd.d/scan.conf 2>/dev/null || true
fi
chown -R clamupdate:clamupdate /var/lib/clamav 2>/dev/null || true

# Download dovecot config from QMT
wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot.conf 2>/dev/null || true
wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot-sql.conf.ext 2>/dev/null || true

# Generate MySQL credentials (needed for Dovecot SQL auth).
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

# Override Dovecot SQL auth for SysAdminHCP (uses sysadminhcp MySQL user + PLAIN passwords)
cat > /etc/dovecot/dovecot-sql.conf.ext << DOVECOTSQL
# SysAdminHCP Dovecot vpopmail MySQL authentication
driver = mysql
connect = host=127.0.0.1 dbname=vpopmail user=sysadminhcp password=${KLOXOJRA_DB_PASS}

# Use PLAIN password scheme since vpopmail stores plaintext in pw_clear_passwd
default_pass_scheme = PLAIN

# Password lookup
password_query = \
  SELECT pw_clear_passwd AS password, \
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

# Ensure auth-sql.conf.ext uses our SQL config
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
sed -i 's/^first_valid_uid = .*/first_valid_uid = 89/' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true
grep -q '^mail_uid' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || sed -i '/^first_valid_uid/i mail_uid = vpopmail\nmail_gid = vchkpw' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true
grep -q '^mail_location' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || sed -i '/^mail_uid/i mail_location = maildir:/home/vpopmail/domains/%d/%n/Maildir' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true

# Symlink sendmail
[ ! -h /usr/sbin/sendmail ] && ln -s /var/qmail/bin/sendmail /usr/sbin/sendmail 2>/dev/null || true

# Enable man pages for QMT
grep -q '/var/qmail/man' /etc/man_db.conf 2>/dev/null || echo "MANDATORY_MANPATH /var/qmail/man" >> /etc/man_db.conf 2>/dev/null

# Install qmail systemd services (direct units — more reliable than svscan on systemd hosts)
# Wrapper scripts needed because run scripts have --x (no read) for others; systemd needs to read shebang
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

# Fix vpopmail home directory permissions
chmod 755 /home/vpopmail 2>/dev/null || true

# FTP
yum install -y pure-ftpd

# Database (MariaDB)
yum install -y mariadb-server

# PHP-FPM (for hosting PHP sites)
yum install -y php php-fpm php-mysqlnd php-json php-xml php-gd php-mbstring

# Other utilities
yum install -y wget curl rsync sshpass logrotate htop unzip tar openssl

# Security tools
yum install -y fail2ban acl 2>/dev/null || warn "Some security packages failed to install"
# clamav-update provides freshclam (may already be installed via QMT clamav)
yum install -y clamav-update 2>/dev/null || true

# ─── Step 6: Create SysAdminHCP User ─────────────────────────────────────
info "Step 6: Creating sysadminhcp system user..."
if ! id "$SYSADMINHCP_USER" &>/dev/null; then
  useradd -r -s /sbin/nologin -d "$SYSADMINHCP_ROOT" "$SYSADMINHCP_USER"
  info "User $SYSADMINHCP_USER created"
else
  info "User $SYSADMINHCP_USER already exists"
fi

# Add sysadminhcp user to systemd-journal group for journalctl access
usermod -a -G systemd-journal "$SYSADMINHCP_USER" 2>/dev/null || true

# Add sysadminhcp user to named group for BIND DNS access (/etc/named.conf, /var/named)
usermod -a -G named "$SYSADMINHCP_USER" 2>/dev/null || true

# Set ACLs so sysadminhcp user can read system log files
setfacl -R -m u:$SYSADMINHCP_USER:rX /var/log/httpd/ 2>/dev/null || true
setfacl -R -m u:$SYSADMINHCP_USER:rX /var/log/mariadb/ 2>/dev/null || true
setfacl -m u:$SYSADMINHCP_USER:r /var/log/messages 2>/dev/null || true

# ─── Step 7: Create Directory Structure ─────────────────────────────────────
info "Step 7: Creating directory structure..."
mkdir -p "$SYSADMINHCP_ROOT"/{httpdocs,data,etc,file/template,backup,log,tmp}
mkdir -p "$SYSADMINHCP_ROOT/httpdocs/web-console"
mkdir -p "$SYSADMINHCP_ROOT/etc"  # Ensure etc dir exists for mysql-root-password
mkdir -p /var/log/sysadminhcp
mkdir -p /var/tmp/sysadminhcp
mkdir -p /var/run/sysadminhcp
mkdir -p /var/cache/sysadminhcp
mkdir -p /var/lib/sysadminhcp/pma-tokens
# Apache SSL certificate storage (used by letsEncryptService.installCertToApache)
mkdir -p /etc/httpd/ssl
chmod 711 /etc/httpd/ssl

# ─── Step 8: Install SysAdminHCP Application ───────────────────────────────────
info "Step 8: Installing SysAdminHCP application..."
# REPO_DIR is already the sysadminhcp project root (one level up from deploy/)
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

  # node-pty's native .node binding can't be embedded in the pkg snapshot -
  # it's excluded at build time and must be installed standalone here,
  # against the same package.json every server installs it against.
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
  # Check if pre-built dist/ exists (deployment package) or if we need to build from source
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
  # Copy built application
  cp -r dist "$SYSADMINHCP_ROOT/httpdocs/"
  cp -r theme "$SYSADMINHCP_ROOT/httpdocs/"
  # Create web-console directory if it doesn't exist
  mkdir -p "$SYSADMINHCP_ROOT/httpdocs/web-console"
  cp package.json "$SYSADMINHCP_ROOT/httpdocs/"
  cp package-lock.json "$SYSADMINHCP_ROOT/httpdocs/" 2>/dev/null || true
  # Install production dependencies at target location
  cd "$SYSADMINHCP_ROOT/httpdocs"
  info "Installing production dependencies..."
  npm install --production --no-audit --no-fund
  info "Production dependencies installed"

  # Install native npm modules that require compilation on the target platform
  # node-pty: PTY support for SSH terminal (needs gcc/g++/make from Step 4)
  info "Building native npm modules (node-pty for SSH terminal)..."
  npm install node-pty --no-audit --no-fund 2>/dev/null \
    && info "node-pty compiled OK" \
    || warn "node-pty compilation failed — SSH terminal will be unavailable"
  # ws: WebSocket server for terminal
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

# ─── Step 8.5: Install qmail-queue rate-limit wrapper ───────────────────────
if [[ -f /var/qmail/bin/qmail-queue && -f "$REPO_DIR/deploy/qmail-queue-check.sh" ]]; then
  info "Step 8.5: Installing qmail-queue rate-limit wrapper..."
  if [[ ! -f /var/qmail/bin/qmail-queue.real ]]; then
    # cp -p preserves permissions including the setuid bit (4711 qmailq:qmail)
    cp -p /var/qmail/bin/qmail-queue /var/qmail/bin/qmail-queue.real
    info "Original qmail-queue backed up to qmail-queue.real"
  fi
  cp "$REPO_DIR/deploy/qmail-queue-check.sh" /var/qmail/bin/qmail-queue
  chmod 755 /var/qmail/bin/qmail-queue
  chown root:root /var/qmail/bin/qmail-queue
  restorecon /var/qmail/bin/qmail-queue 2>/dev/null || true
  mkdir -p /var/lib/sysadminhcp/email-rate
  chown -R vpopmail /var/lib/sysadminhcp/email-rate 2>/dev/null || true
  mkdir -p /var/log/sysadminhcp
  touch /var/qmail/control/sysadminhcp-ratelimits 2>/dev/null || true
  info "qmail-queue wrapper installed — rate limiting active"
else
  info "Step 8.5: qmail not present or wrapper not found — skipping queue wrapper"
fi

# ─── Step 9: Configure Environment ─────────────────────────────────────────
info "Step 9: Configuring environment..."

# Generate random secrets for production
SESSION_SECRET=$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p -c 64 | head -c 64)
COOKIE_SECRET=$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p -c 64 | head -c 64)

# MySQL root password (KLOXOJRA_DB_PASS already generated in Step 5 for Dovecot config — reused here)
MYSQL_ROOT_PASS='kloxoroot'

cat > "$SYSADMINHCP_ROOT/etc/sysadminhcp.env" << EOF
# SysAdminHCP Environment Configuration
# Generated by install-almalinux8.sh on $(date -u '+%Y-%m-%d %H:%M:%S UTC')
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

# Ensure all required directories exist (systemd namespace setup requires this)
mkdir -p "$SYSADMINHCP_ROOT"/{httpdocs,data,etc,file/template,file/ssl,backup,log,tmp}
mkdir -p "$SYSADMINHCP_ROOT/httpdocs/web-console"
mkdir -p /var/log/sysadminhcp
mkdir -p /var/tmp/sysadminhcp
mkdir -p /var/run/sysadminhcp
mkdir -p /var/cache/sysadminhcp
mkdir -p /var/backup/sysadminhcp

chown -R $SYSADMINHCP_USER:$SYSADMINHCP_GROUP "$SYSADMINHCP_ROOT"
chown -R $SYSADMINHCP_USER:$SYSADMINHCP_GROUP /var/log/sysadminhcp
chown -R $SYSADMINHCP_USER:$SYSADMINHCP_GROUP /var/tmp/sysadminhcp
chown -R $SYSADMINHCP_USER:$SYSADMINHCP_GROUP /var/run/sysadminhcp
chown -R $SYSADMINHCP_USER:$SYSADMINHCP_GROUP /var/cache/sysadminhcp
chown -R $SYSADMINHCP_USER:$SYSADMINHCP_GROUP /var/backup
chown -R $SYSADMINHCP_USER:$SYSADMINHCP_GROUP /var/lib/sysadminhcp
chmod 750 "$SYSADMINHCP_ROOT/etc/sysadminhcp.env"

# Configure sudoers for sysadminhcp user
# Remove legacy sysadminhcp-logs file if present from older installs
rm -f /etc/sudoers.d/sysadminhcp-logs
cat > /etc/sudoers.d/sysadminhcp << 'SUDOEOF'
sysadminhcp ALL=(root) NOPASSWD: /usr/bin/tail, /usr/bin/cat, /usr/bin/journalctl, /usr/sbin/tail, /usr/local/sysadminhcp/scripts/install-qmail-toaster.sh, /usr/bin/cp, /usr/bin/mv, /usr/bin/chmod, /usr/bin/chown, /usr/bin/find, /usr/bin/mkdir, /usr/bin/rm, /usr/bin/systemctl, /usr/bin/tcprules, /usr/sbin/useradd, /usr/sbin/groupadd, /usr/bin/id, /usr/sbin/usermod, /home/vpopmail/bin/vadddomain, /home/vpopmail/bin/vdeldomain, /home/vpopmail/bin/vadduser, /home/vpopmail/bin/vdeluser, /home/vpopmail/bin/vchangepw, /home/vpopmail/bin/vpasswd, /home/vpopmail/bin/vsetuserquota, /home/vpopmail/bin/vmoduser, /home/vpopmail/bin/vmoddomlimits, /home/vpopmail/bin/vdominfo, /home/vpopmail/bin/vuserinfo, /usr/bin/yum, /usr/bin/rpm, /usr/bin/setfacl, /usr/bin/firewall-cmd, /usr/sbin/iptables, /sbin/iptables, /usr/bin/freshclam, /usr/bin/fail2ban-client, /bin/bash, /usr/bin/bash, /root/.acme.sh/acme.sh, /usr/bin/openssl
SUDOEOF
chmod 440 /etc/sudoers.d/sysadminhcp
visudo -c && info "sudoers validated OK" || warn "sudoers validation failed — check /etc/sudoers.d/sysadminhcp"

# Install goaccess and create daily stats cron (needs EPEL; /usr may be read-only)
mount -o remount,rw /usr 2>/dev/null || true
GOACCESS_LOG=$(yum install -y epel-release 2>&1; yum install -y goaccess 2>&1) || true
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

# Generate self-signed SSL certificate if not already present
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

# Set ACLs for BIND DNS access (WSL does not honor supplementary group permissions)
setfacl -m u:$SYSADMINHCP_USER:rw /etc/named.conf 2>/dev/null || true
setfacl -R -m u:$SYSADMINHCP_USER:rwx /var/named/ 2>/dev/null || true

# Create /var/named/slaves/ for DNS cluster slave zones (BIND writes AXFR zone files here)
mkdir -p /var/named/slaves
chown named:named /var/named/slaves
chmod 770 /var/named/slaves
info "Created /var/named/slaves/ for DNS cluster slave zones"

# Grant sysadminhcp read/write access to all existing client home dirs for File Manager
# New clients get these ACLs automatically via ClientService.provisionHomeDir()
info "Setting File Manager ACLs on existing client home directories..."
for homedir in /home/*/; do
  owner=$(stat -c '%U' "$homedir" 2>/dev/null)
  # Skip system accounts (vpopmail, root, sysadminhcp, named, apache, mysql, etc.)
  if id "$owner" &>/dev/null && [[ "$owner" != "root" && "$owner" != "$SYSADMINHCP_USER" ]]; then
    setfacl -m u:$SYSADMINHCP_USER:rwx "$homedir" 2>/dev/null || true
    setfacl -d -m u:$SYSADMINHCP_USER:rwX "$homedir" 2>/dev/null || true
    info "  ACL set: $homedir (owner: $owner)"
  fi
done

# ─── Step 11: Install Systemd Service ──────────────────────────────────────
info "Step 11: Installing systemd service..."

# Generate service file with WSL-aware settings
if [[ $WSL_MODE -eq 1 ]]; then
  info "WSL detected: using WSL-compatible service configuration (no ProtectSystem)"
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

# Security hardening (WSL-compatible - no namespace restrictions)
# Note: ProtectHome must be 'no' because SysAdminHCP creates/manages domain directories under /home
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
# Note: ProtectHome must be 'no' because SysAdminHCP creates/manages domain directories under /home
ProtectHome=no
ReadWritePaths=/usr/local/sysadminhcp/data /usr/local/sysadminhcp/httpdocs /home

# Let systemd create/manage runtime, cache, and log directories
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

# Install logrotate config to persist ACLs across log rotation
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
if command -v firewall-cmd &>/dev/null; then
  firewall-cmd --permanent --add-port=7778/tcp  # HTTP
  firewall-cmd --permanent --add-port=7777/tcp  # HTTPS
  firewall-cmd --permanent --add-service=http
  firewall-cmd --permanent --add-service=https
  firewall-cmd --permanent --add-service=dns        # DNS (port 53 UDP+TCP)
  firewall-cmd --permanent --add-service=ftp        # FTP control (21)
  firewall-cmd --permanent --add-port=30000-31000/tcp  # FTP passive
  firewall-cmd --reload
  info "Firewall rules added for ports 7778, 7777, 80, 443, 53, 21, 30000-31000"
else
  warn "firewalld not found. Skipping firewall configuration."
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

# ── Fail2ban ──────────────────────────────────────────────────────────────
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

[httpd-auth]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s

[pure-ftpd]
enabled  = true
port     = ftp,ftp-data,ftps,ftps-data
logpath  = %(pureftpd_log)s
F2BEOF
    info "Fail2ban jail.local created (SSH, HTTP auth, FTP jails enabled)"
  else
    info "Fail2ban jail.local already exists — skipping creation"
  fi
  systemctl enable fail2ban 2>/dev/null || true
else
  warn "Fail2ban not available — skipping configuration"
fi

# ── ClamAV freshclam initial update ────────────────────────────────────────
if command -v freshclam &>/dev/null; then
  if [[ ! -f /var/lib/clamav/main.cvd ]] && [[ ! -f /var/lib/clamav/main.cld ]]; then
    info "Running initial ClamAV database update (this may take a moment)..."
    freshclam 2>/dev/null && info "ClamAV DB updated" || warn "ClamAV DB update failed — run freshclam manually after install"
  else
    info "ClamAV database already present — skipping initial update"
  fi
  systemctl enable clamav-freshclam 2>/dev/null || true
fi

# ─── Step 13: Configure SELinux ────────────────────────────────────────────
info "Step 13: Configuring SELinux..."
if command -v getenforce &>/dev/null && [[ "$(getenforce)" != "Disabled" ]]; then
  if [[ $WSL_MODE -eq 1 ]]; then
    warn "SELinux may not be fully functional under WSL."
    warn "If you encounter issues, set SELinux to permissive:"
    warn "  sudo setenforce 0"
  else
    # Allow sysadminhcp to bind to its ports
    setsebool -P httpd_can_network_connect 1
    semanage port -a -t http_port_t -p tcp 7778 2>/dev/null || true
    semanage port -a -t http_port_t -p tcp 7777 2>/dev/null || true
    # Allow Apache to serve files from /home/* (domain doc roots)
    setsebool -P httpd_enable_homedirs on 2>/dev/null || true
    setsebool -P httpd_read_user_content on 2>/dev/null || true
    info "SELinux policies configured"
  fi
else
  info "SELinux is disabled. Skipping policy configuration."
fi

# ─── Step 14: Start Services ───────────────────────────────────────────────
info "Step 14: Starting services..."

# Start MariaDB
info "Starting MariaDB..."
systemctl enable mariadb
systemctl start mariadb

# Bind MariaDB to localhost only (security: prevent external access)
info "Binding MariaDB to 127.0.0.1 (localhost only)..."
if [[ -f /etc/my.cnf.d/server.cnf ]]; then
  if ! grep -q '^bind-address' /etc/my.cnf.d/server.cnf; then
    sed -i '/\[mysqld\]/a bind-address=127.0.0.1' /etc/my.cnf.d/server.cnf
    systemctl restart mariadb
    info "MariaDB bound to 127.0.0.1 in /etc/my.cnf.d/server.cnf"
  else
    info "MariaDB already bound to localhost"
  fi
elif [[ -f /etc/my.cnf.d/openstack.cnf ]]; then
  if ! grep -q '^bind-address' /etc/my.cnf.d/openstack.cnf; then
    sed -i '/\[mysqld\]/a bind-address=127.0.0.1' /etc/my.cnf.d/openstack.cnf
    systemctl restart mariadb
    info "MariaDB bound to 127.0.0.1 in /etc/my.cnf.d/openstack.cnf"
  fi
else
  # Create server.cnf with bind-address if no config exists
  cat > /etc/my.cnf.d/server.cnf << 'MYSQLEOF'
[mysqld]
bind-address=127.0.0.1
MYSQLEOF
  systemctl restart mariadb
  info "Created /etc/my.cnf.d/server.cnf with bind-address=127.0.0.1"
fi

# Secure MariaDB if not already done (only on fresh install)
if [[ $FRESH_INSTALL -eq 1 ]]; then
  # Wait for MariaDB to be ready
  for i in $(seq 1 30); do
    if mysqladmin ping -u root 2>/dev/null; then
      break
    fi
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
    # Store MySQL root password for SysAdminHCP (backup restore, phpMyAdmin SSO)
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

# Start Apache
systemctl enable httpd 2>/dev/null || true
systemctl start httpd 2>/dev/null || warn "Apache (httpd) failed to start - may need manual configuration"

# Configure BIND to listen on all interfaces (default AlmaLinux named.conf is localhost-only)
# A hosting panel nameserver must answer queries from the public internet.
info "Configuring BIND to listen on public interface..."
if [[ -f /etc/named.conf ]]; then
  # listen-on: accept queries on all interfaces (not just 127.0.0.1)
  sed -i 's/listen-on port 53 { 127\.0\.0\.1; };/listen-on port 53 { any; };/' /etc/named.conf
  sed -i 's/listen-on-v6 port 53 { ::1; };/listen-on-v6 port 53 { any; };/' /etc/named.conf
  # allow-query: answer queries from anywhere (authoritative server for hosted zones)
  sed -i 's/allow-query[[:space:]]*{[[:space:]]*localhost;[[:space:]]*};/allow-query     { any; };/' /etc/named.conf
  named-checkconf && info "named.conf updated and validated (listen-on any, allow-query any)" \
    || warn "named.conf validation failed — check /etc/named.conf manually"
else
  warn "/etc/named.conf not found — BIND may not be installed correctly"
fi

# Start BIND
systemctl enable named 2>/dev/null || true
systemctl start named 2>/dev/null || warn "BIND (named) failed to start - may need manual configuration"

# ─── Configure Pure-FTPd MySQL Authentication ──────────────────────────────
info "Configuring Pure-FTPd MySQL authentication..."

# Create pureftpd MySQL database and users table (requires MariaDB to be running)
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
else
  warn "MariaDB not available — pureftpd database not created; run manually after MariaDB starts"
fi

# Write pureftpd-mysql.conf with root credentials
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
info "pureftpd-mysql.conf written"

# Configure pure-ftpd.conf: disable PAM auth, enable MySQL, set passive port range
FTPCONF=/etc/pure-ftpd/pure-ftpd.conf
if [[ -f "$FTPCONF" ]]; then
  # Remove any existing conflicting directives (commented or active)
  sed -i '/^[#[:space:]]*PAMAuthentication/d' "$FTPCONF"
  sed -i '/^[#[:space:]]*MySQLConfigFile/d' "$FTPCONF"
  sed -i '/^[#[:space:]]*PassivePortRange/d' "$FTPCONF"
  # Append the correct settings
  printf '\nPAMAuthentication no\nMySQLConfigFile /etc/pure-ftpd/pureftpd-mysql.conf\nPassivePortRange 30000 31000\n' >> "$FTPCONF"
  info "Pure-FTPd: PAMAuthentication disabled, MySQL auth enabled, passive ports 30000-31000"
else
  warn "$FTPCONF not found — creating minimal config"
  cat > "$FTPCONF" << 'MINFTPCONF'
PAMAuthentication no
MySQLConfigFile /etc/pure-ftpd/pureftpd-mysql.conf
PassivePortRange 30000 31000
MINFTPCONF
  info "Pure-FTPd minimal config created at $FTPCONF"
fi

# Start Pure-FTPd
systemctl enable pure-ftpd 2>/dev/null || true
systemctl start pure-ftpd 2>/dev/null || warn "Pure-FTPd failed to start - may need manual configuration"

# Start PHP-FPM
systemctl enable php-fpm 2>/dev/null || true
systemctl start php-fpm 2>/dev/null || warn "PHP-FPM failed to start - may need manual configuration"

# Start QmailToaster mail services
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
systemctl start dovecot 2>/dev/null || warn "Dovecot failed to start - may need manual configuration"
systemctl enable spamassassin 2>/dev/null || true
systemctl start spamassassin 2>/dev/null || warn "SpamAssassin failed to start - may need manual configuration"
systemctl enable clamd@scan 2>/dev/null || true
systemctl start clamd@scan 2>/dev/null || warn "ClamAV (clamd@scan) failed to start - may need manual configuration"
systemctl enable clamav-freshclam 2>/dev/null || true
systemctl start clamav-freshclam 2>/dev/null || warn "ClamAV freshclam failed to start - may need manual configuration"

# Start Fail2ban
systemctl enable fail2ban 2>/dev/null || true
systemctl start fail2ban 2>/dev/null || warn "Fail2ban failed to start - may need manual configuration"

# Set up vpopmail database in MariaDB (if MariaDB is running and vpopmail is installed)
if command -v mysql &>/dev/null && systemctl is-active --quiet mariadb; then
  if rpm -q vpopmail &>/dev/null; then
    info "Setting up vpopmail database in MariaDB..."
    VPOPMAIL_DB_PASS=$(openssl rand -hex 8 2>/dev/null || echo "vpopmail123")
    mysql -u root -p"${MYSQL_ROOT_PASS}" <<EOSQL 2>/dev/null || warn "vpopmail database setup failed (may need manual configuration)"
CREATE DATABASE IF NOT EXISTS vpopmail;
CREATE USER IF NOT EXISTS 'vpopmail'@'localhost' IDENTIFIED BY '${VPOPMAIL_DB_PASS}';
ALTER USER 'vpopmail'@'localhost' IDENTIFIED BY '${VPOPMAIL_DB_PASS}';
GRANT ALL PRIVILEGES ON vpopmail.* TO 'vpopmail'@'localhost';
FLUSH PRIVILEGES;
EOSQL
    # Create vpopmail MySQL tables (rpm does not create them; lastauth uses int not TIMESTAMP for MariaDB strict mode)
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
    # Also create the sysadminhcp database user for SysAdminHCP
    mysql -u root -p"${MYSQL_ROOT_PASS}" <<EOSQL2 2>/dev/null || warn "sysadminhcp database user setup failed"
CREATE DATABASE IF NOT EXISTS sysadminhcp;
CREATE USER IF NOT EXISTS 'sysadminhcp'@'localhost' IDENTIFIED BY '${KLOXOJRA_DB_PASS}';
GRANT ALL PRIVILEGES ON sysadminhcp.* TO 'sysadminhcp'@'localhost';
GRANT SELECT ON vpopmail.* TO 'sysadminhcp'@'localhost';
FLUSH PRIVILEGES;
EOSQL2
    info "sysadminhcp database user created (password: ${KLOXOJRA_DB_PASS})"
    # Overwrite vpopmail.mysql config with correct credentials (do not rely on sed pattern matching)
    mkdir -p /home/vpopmail/etc
    echo "localhost|0|vpopmail|${VPOPMAIL_DB_PASS}|vpopmail" > /home/vpopmail/etc/vpopmail.mysql
    chown vpopmail:vchkpw /home/vpopmail/etc/vpopmail.mysql 2>/dev/null || true
    chmod 640 /home/vpopmail/etc/vpopmail.mysql 2>/dev/null || true
    info "vpopmail database configured (password: ${VPOPMAIL_DB_PASS})"
  fi

  # Create .my.cnf for sysadminhcp user so SysAdminHCP can read MySQL credentials
  cat > "$SYSADMINHCP_ROOT/.my.cnf" << MYCNF
[client]
user=sysadminhcp
password=${KLOXOJRA_DB_PASS}
host=localhost
MYCNF
  chown sysadminhcp:sysadminhcp "$SYSADMINHCP_ROOT/.my.cnf"
  chmod 600 "$SYSADMINHCP_ROOT/.my.cnf"
  info "Created $SYSADMINHCP_ROOT/.my.cnf for SysAdminHCP MySQL access"

  # Create /root/.my.cnf for root MySQL access
  if [ ! -f /root/.my.cnf ]; then
    cat > /root/.my.cnf << ROOTMYCNF
[client]
user=root
password=${MYSQL_ROOT_PASS}
ROOTMYCNF
    chmod 600 /root/.my.cnf
    info "Created /root/.my.cnf for root MySQL access"
  fi
fi

# ─── Step 14.5: Install phpMyAdmin (optional) ─────────────────────────────
info "Step 14.5: Setting up phpMyAdmin (optional)..."
# Ensure mysqli extension (php-mysqlnd) is present — required by phpMyAdmin
yum install -y php-mysqlnd 2>/dev/null || true
if yum list installed phpmyadmin &>/dev/null 2>&1; then
  info "phpMyAdmin already installed — configuring SSO..."
else
  info "Installing phpMyAdmin..."
  yum install -y phpmyadmin 2>/dev/null || warn "phpMyAdmin installation failed — install manually with: yum install -y phpmyadmin"
fi

# Create PMA SSO token directory
mkdir -p /var/lib/sysadminhcp/pma-tokens
chown sysadminhcp:sysadminhcp /var/lib/sysadminhcp/pma-tokens
chmod 755 /var/lib/sysadminhcp/pma-tokens

# Deploy SysAdminHCP phpMyAdmin signon script and config
if [[ -d /usr/share/phpMyAdmin ]]; then
  # Create signon directory
  mkdir -p /usr/share/phpMyAdmin/sysadminhcp-signon

  # Deploy signon.php
  if [[ -f "$REPO_DIR/pma-signon/signon.php" ]]; then
    cp "$REPO_DIR/pma-signon/signon.php" /usr/share/phpMyAdmin/sysadminhcp-signon/signon.php
    chown -R apache:apache /usr/share/phpMyAdmin/sysadminhcp-signon
    info "phpMyAdmin signon script deployed"
  else
    warn "pma-signon/signon.php not found in source — phpMyAdmin SSO will not work until deployed manually"
  fi

  # Deploy phpMyAdmin config with signon auth
  if [[ -f "$REPO_DIR/pma-signon/config.inc.php" ]]; then
    cp "$REPO_DIR/pma-signon/config.inc.php" /etc/phpMyAdmin/config.inc.php
    # Give this install its own blowfish_secret rather than the placeholder in source control.
    PMA_BLOWFISH_SECRET=$(openssl rand -hex 16)
    sed -i "s/__PMA_BLOWFISH_SECRET__/${PMA_BLOWFISH_SECRET}/" /etc/phpMyAdmin/config.inc.php
    info "phpMyAdmin config deployed (signon auth mode, random blowfish secret)"
  else
    warn "pma-signon/config.inc.php not found in source — phpMyAdmin will use default cookie auth"
  fi

  # Create Apache config for PMA signon endpoint
  cat > /etc/httpd/conf.d/sysadminhcp-pma-signon.conf << 'APACHEEOF'
# SysAdminHCP phpMyAdmin SSO endpoint
Alias /pma-signon /usr/share/phpMyAdmin/sysadminhcp-signon

<Directory /usr/share/phpMyAdmin/sysadminhcp-signon>
    Require all granted
    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php-fpm/www.sock|fcgi://localhost"
    </FilesMatch>
</Directory>
APACHEEOF
  info "Apache phpMyAdmin SSO config deployed"

  # Create default VirtualHost for localhost (must be first — 000 prefix)
  cat > /etc/httpd/conf.d/000-default.conf << 'APACHEEOF'
<VirtualHost *:80>
    ServerName 127.0.0.1
    DocumentRoot "/var/www/html"
    <Directory "/var/www/html">
        Require all granted
    </Directory>
</VirtualHost>
APACHEEOF
  info "Default VirtualHost (000-default.conf) deployed for localhost access"

  # Enable SELinux boolean to allow PHP-FPM to connect to MySQL (required for phpMyAdmin)
  setsebool -P httpd_can_network_connect_db on 2>/dev/null || true

  # Restart Apache to pick up new config
  systemctl restart httpd 2>/dev/null || true
else
  warn "phpMyAdmin not found at /usr/share/phpMyAdmin — skipping SSO setup"
fi

# ─── Step 14.6: Install RainLoop Webmail ──────────────────────────────────
info "Step 14.6: Installing RainLoop webmail..."

RAINLOOP_DIR="/var/www/rainloop"
if [[ -f "$RAINLOOP_DIR/index.php" ]]; then
  info "RainLoop already installed at $RAINLOOP_DIR — skipping"
else
  # Create directory structure
  mkdir -p "$RAINLOOP_DIR"
  mkdir -p "$RAINLOOP_DIR/data/_data_/_default_/configs"
  mkdir -p "$RAINLOOP_DIR/data/_data_/_default_/domains"
  mkdir -p "$RAINLOOP_DIR/data/_data_/_default_/storage"

  # Download RainLoop
  info "Downloading RainLoop..."
  curl -sL https://www.rainloop.net/repository/webmail/rainloop-latest.zip -o /tmp/rainloop.zip
  if [[ -f /tmp/rainloop.zip ]]; then
    unzip -o /tmp/rainloop.zip -d "$RAINLOOP_DIR" 2>/dev/null || warn "RainLoop unzip failed"
    rm -f /tmp/rainloop.zip
    info "RainLoop downloaded and extracted"
  else
    warn "RainLoop download failed — install manually from https://www.rainloop.net/"
  fi

  # Set permissions
  chown -R apache:apache "$RAINLOOP_DIR"
  chmod -R 755 "$RAINLOOP_DIR"
  chmod -R 777 "$RAINLOOP_DIR/data"

  # Configure RainLoop
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

  # Create default domain config for local IMAP/SMTP (qmail/dovecot)
  cat > "$RAINLOOP_DIR/data/_data_/_default_/domains/default.json" << 'DOMEOF'
{
  "imap": { "host": "localhost", "port": 143, "secure": false },
  "smtp": { "host": "localhost", "port": 25, "secure": false },
  "sieve": { "host": "localhost", "port": 4190, "secure": false }
}
DOMEOF

  chown -R apache:apache "$RAINLOOP_DIR/data"
  # SELinux: app files read-only, data dir read-write so PHP-FPM can write
  chcon -R -t httpd_sys_content_t "$RAINLOOP_DIR" 2>/dev/null || true
  chcon -R -t httpd_sys_rw_content_t "$RAINLOOP_DIR/data" 2>/dev/null || true
  info "RainLoop configured"
fi

# Create Apache vhost for webmail (catch-all webmail.* and webmail.domain.*)
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

# Create PHP-FPM pool for webmail
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
    php83-php-mysqlnd php83-php-intl php83-php-xml php83-php-gd php83-php-zip php83-php-ldap php83-php-mbstring 2>/dev/null || \
    yum install -y php-intl php-mbstring php-xml php-gd php-zip php-ldap 2>/dev/null || true

  # Get latest stable Roundcube version from GitHub
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
    # Generate DB credentials and encryption key
    RC_DB_PASS=$(openssl rand -hex 16)
    RC_DES_KEY=$(openssl rand -hex 12)
    MYSQL_ROOT_PASS=""
    [[ -f /usr/local/sysadminhcp/etc/mysql-root-password ]] && MYSQL_ROOT_PASS=$(cat /usr/local/sysadminhcp/etc/mysql-root-password)

    # Create database and user
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

    # Write configuration
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

    # Set permissions and SELinux context
    mkdir -p "$ROUNDCUBE_DIR/temp" "$ROUNDCUBE_DIR/logs"
    chown -R apache:apache "$ROUNDCUBE_DIR" /var/log/roundcube /tmp/roundcube
    chmod -R 755 "$ROUNDCUBE_DIR"
    chmod -R 777 "$ROUNDCUBE_DIR/temp" "$ROUNDCUBE_DIR/logs" /tmp/roundcube 2>/dev/null || true
    chcon -R -t httpd_sys_content_t "$ROUNDCUBE_DIR" 2>/dev/null || true
    chcon -R -t httpd_sys_rw_content_t "$ROUNDCUBE_DIR/temp" "$ROUNDCUBE_DIR/logs" 2>/dev/null || true

    # Create php83-fpm webmail pool — RC >= 1.6 requires PHP >= 8.1
    PHP83_POOL_DIR="/etc/opt/remi/php83/php-fpm.d"
    PHP83_SOCK_DIR="/var/opt/remi/php83/run/php-fpm"
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

# ─── Step 14.8: Install acme.sh (Let's Encrypt client) ────────────────────
info "Step 14.8: Installing acme.sh (Let's Encrypt client)..."
if [[ -x /root/.acme.sh/acme.sh ]]; then
  info "acme.sh already installed at /root/.acme.sh/acme.sh — skipping"
else
  info "Downloading and installing acme.sh..."
  if curl -sSL https://get.acme.sh | sh 2>&1 | tail -5; then
    if [[ -x /root/.acme.sh/acme.sh ]]; then
      info "acme.sh installed successfully at /root/.acme.sh/acme.sh"
    else
      warn "acme.sh download succeeded but binary not found — check /root/.acme.sh/"
    fi
  else
    warn "acme.sh installation failed — Let's Encrypt SSL issuance will not work"
    warn "Install manually after setup: curl -sSL https://get.acme.sh | sh"
  fi
fi

# Set Let's Encrypt as default CA (acme.sh v3+ defaults to ZeroSSL which requires EAB credentials)
if [[ -x /root/.acme.sh/acme.sh ]]; then
  info "Setting Let's Encrypt as default acme.sh CA..."
  /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt 2>/dev/null || true
fi

# ─── Step 14.9: Apply client:apache group ownership to all domain web roots ──
# Standard web hosting pattern: client user owns files, group apache so Apache
# can read via group permissions without per-file ACL maintenance.
# Dirs: 750 (client rwx, apache r-x), Files: 640 (client rw, apache r)
# stats/logs: apache:apache 750 (Apache writes access/error logs there)
info "Step 14.9: Applying client:apache ownership to all domain web roots..."
for homedir in /home/*/; do
  [[ -d "$homedir" ]] || continue
  clientname=$(basename "$homedir")
  # Skip system accounts
  case "$clientname" in vpopmail|root|sysadminhcp|named|apache|mysql|qmail|qmaild|qmaill|qmailp|qmailq|qmailr|qmails|alias|nobody) continue ;; esac
  id "$clientname" &>/dev/null || continue

  for domaindir in "$homedir"*/; do
    [[ -d "$domaindir" ]] || continue
    pubhtml="$domaindir/public_html"
    statsdir="$domaindir/stats"
    logsdir="$domaindir/logs"

    # public_html: client owns, group apache
    if [[ -d "$pubhtml" ]]; then
      chown -R "$clientname":apache "$pubhtml" 2>/dev/null || true
      find "$pubhtml" -type d -exec chmod 750 {} \; 2>/dev/null || true
      find "$pubhtml" -type f -exec chmod 640 {} \; 2>/dev/null || true
      # Default ACL so future files inherit apache group read
      setfacl -d -m g:apache:r-x "$pubhtml" 2>/dev/null || true
      # SELinux: content context for httpd
      chcon -R -t httpd_sys_content_t "$pubhtml" 2>/dev/null || true
    fi

    # stats/logs: apache owns (writes error/access logs here)
    for logdir in "$statsdir" "$logsdir"; do
      [[ -d "$logdir" ]] || continue
      chown -R apache:apache "$logdir" 2>/dev/null || true
      chmod 750 "$logdir" 2>/dev/null || true
      # Fix any root-owned log files from emergency runs
      find "$logdir" -maxdepth 1 -name '*.log' -user root -exec chown apache:apache {} \; 2>/dev/null || true
      chcon -t httpd_log_t "$logdir" 2>/dev/null || true
    done

    # Home dir: client:client, apache gets x-only via ACL for traversal
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
  "description": "Installed via install-almalinux8.sh"
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

# Wait for SysAdminHCP to start (up to 30 seconds)
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

# Verify database was seeded (admin user should exist)
if [[ -f "$SYSADMINHCP_ROOT/data/sysadminhcp.db" ]]; then
  info "Database file created: $SYSADMINHCP_ROOT/data/sysadminhcp.db"
  DB_SIZE=$(stat -f%z "$SYSADMINHCP_ROOT/data/sysadminhcp.db" 2>/dev/null || stat -c%s "$SYSADMINHCP_ROOT/data/sysadminhcp.db" 2>/dev/null || echo "unknown")
  info "Database size: $DB_SIZE bytes"
else
  warn "Database file not found at $SYSADMINHCP_ROOT/data/sysadminhcp.db"
  warn "The database is seeded automatically on first startup."
  warn "If the service is running, check the logs for errors."
fi

# ─── Done ──────────────────────────────────────────────────────────────────
echo ""
info "================================================"
info "  SysAdminHCP Control Panel Installation Complete!"
info "================================================"
echo ""
info "  Web UI:     https://$(hostname -I | awk '{print $1}'):7777/display"
info "  (HTTP port 7778 redirects to HTTPS automatically)"
info "  Admin User: admin"
info "  Admin Pass: admin"
echo ""
warn "  ⚠️  CHANGE THE DEFAULT PASSWORD IMMEDIATELY!"
warn "  ⚠️  SECURE THE MARIADB ROOT PASSWORD!"
echo ""
info "  Let's Encrypt SSL:"
info "    Issue certificates via Admin Portal → Domains → SSL → Let's Encrypt"
info "    acme.sh is installed at /root/.acme.sh/acme.sh"
info "    Certificates are stored in /etc/httpd/ssl/<domain>/ after issuance"
info "    Auto-renewal cron is installed by acme.sh for 90-day certificates"
echo ""
info "  phpMyAdmin:"
info "    If installed, access via Admin Portal → Hosting → phpMyAdmin"
info "    SSO auto-login is configured for admin (root) and client users"
info "    MySQL root password stored in: $SYSADMINHCP_ROOT/etc/mysql-root-password"
echo ""
info "  Webmail (RainLoop):"
info "    Access at: https://$(hostname -I | awk '{print $1}'):7777/webmail or https://webmail.yourdomain.com"
info "    Admin panel: https://$(hostname -I | awk '{print $1}'):7777/webmail/?admin (default password: admin)"
info "    ⚠️  Change the RainLoop admin password immediately after first login!"
echo ""
info "  Service commands:"
info "    sudo systemctl start sysadminhcp"
info "    sudo systemctl stop sysadminhcp"
info "    sudo systemctl restart sysadminhcp"
info "    sudo systemctl status sysadminhcp"
echo ""
info "  Mail services (QmailToaster):"
info "    sudo systemctl start qmail"
info "    sudo systemctl start dovecot"
info "    sudo systemctl start spamassassin"
info "    sudo systemctl start clamd@scan"
info "    sudo qmailctl stat    # Check qmail status"
echo ""
info "  PHP version management (via Admin Portal → Server → PHP Modules):"
info "    PHP 7.2/7.4 is available from AppStream (system default)."
info "    To install PHP 8.0+, first install the Remi repository using the"
info "    'Install Remi Repo' button on the PHP Modules page, then install"
info "    the desired version from the same page."
info "    Remi repo: https://rpms.remirepo.net/enterprise/remi-release-8.rpm"
echo ""
info "  Security (via Admin Portal → Security):"
info "    SSH Config      — edit /etc/ssh/sshd_config settings (port, auth, users)"
info "    Terminal        — browser-based root shell (JWT-authenticated admin only)"
info "    ClamAV          — antivirus scan, DB updates, status"
info "    Blocked IPs     — firewalld drop zone (permanently block IPs/CIDRs)"
info "    Whitelist IPs   — firewalld trusted zone (always-allow IPs/CIDRs)"
info "    Fail2ban        — intrusion detection; jail status + IP unban"
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
  info "    - systemd may need to be enabled: edit /etc/wsl.conf"
  info "    - Add: [boot]\n  systemd=true"
  info "    - Then restart WSL: wsl.exe --shutdown"
  echo ""
fi