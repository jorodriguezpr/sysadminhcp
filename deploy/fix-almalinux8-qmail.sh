#!/bin/bash
# ============================================================================
# Fix Qmail and phpMyAdmin on AlmaLinux 8
# Run on the server: bash fix-almalinux8-qmail.sh
# ============================================================================
# This script fixes common issues with QmailToaster and phpMyAdmin on
# AlmaLinux 8 (EL8) after the main SysAdminHCP installation.
#
# Issues fixed:
#   1. QMT repo configuration (EL8 uses different repo structure than EL9)
#   2. Qmail/vpopmail package installation (nodeps workaround for MariaDB conflict)
#   3. Dovecot SQL auth for vpopmail
#   4. phpMyAdmin SSO configuration
#   5. Qmail service startup issues
#   6. ClamAV configuration
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

SYSADMINHCP_ROOT="/usr/local/sysadminhcp"

# Check root
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root (use sudo)"
fi

# Check OS
if [[ ! -f /etc/os-release ]]; then
  error "Cannot detect OS. /etc/os-release not found"
fi
source /etc/os-release
MAJOR_VER=$(echo "$VERSION_ID" | cut -d. -f1)

if [[ "$MAJOR_VER" != "8" ]]; then
  warn "This script is designed for EL8 (AlmaLinux 8, Rocky 8, etc.)."
  warn "Detected major version: $MAJOR_VER."
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

info "Fixing Qmail and phpMyAdmin on AlmaLinux 8..."
info "================================================"

# ─── Fix 1: QMT Repository Configuration ──────────────────────────────────
info "Fix 1: Configuring QMT repository for EL8..."

# Remove any wrong EL9 repo config
rm -f /etc/yum.repos.d/qat-testing.repo 2>/dev/null || true
rm -f /etc/yum.repos.d/qmt-testing.repo 2>/dev/null || true

# Remove wrong EL9 qmt-release RPM if installed
rpm -e qmt-release 2>/dev/null || true

# Create correct QMT repo config for EL8 (mariadb backend)
# Note: EL8 QMT has no qmt-release RPM. The repo structure is different from EL9:
#   EL8: http://repo.whitehorsetc.com/8/testing/mariadb/x86_64/  (packages split by DB backend)
#   EL9: http://repo.whitehorsetc.com/9/testing/noarch/          (has qmt-release RPM)
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

# ─── Fix 2: Install QMT Packages ──────────────────────────────────────────
info "Fix 2: Installing QMT packages (with --nodeps for MariaDB compatibility)..."

# Remove postfix (conflicts with qmail)
yum remove -y postfix 2>/dev/null || true
userdel postfix 2>/dev/null || true

# Install mysql-libs (needed by vpopmail alongside MariaDB)
yum install -y mysql-libs 2>/dev/null || true

# Install QMT packages that don't conflict with MariaDB
yum install -y --skip-broken \
  daemontools spamassassin ucspi-tcp libsrs2 spamdyke \
  autorespond control-panel qmailmrtg maildrop isoqlog ripmime \
  clamav clamd fetchmail 2>/dev/null || warn "Some QMT packages failed to install"

# Install QMT dovecot (replaces system dovecot - QMT version has vpopmail support)
yum remove -y dovecot dovecot-mysql 2>/dev/null || true
yum install -y --skip-broken dovecot dovecot-mysql 2>/dev/null || warn "QMT dovecot install failed - will use system dovecot"

# Download and install vpopmail/qmail/ezmlm/simscan/qmailadmin/vqadmin with --nodeps
# (they need mysql-server which conflicts with MariaDB, but work fine with MariaDB)
cd /tmp
QMT_DL_URL="http://repo.whitehorsetc.com/8/testing/mariadb/x86_64"

# Clean up any old QMT RPMs from previous attempts
rm -f /tmp/vpopmail-*.rpm /tmp/qmail-*.rpm /tmp/ezmlm-*.rpm /tmp/simscan-*.rpm /tmp/qmailadmin-*.rpm /tmp/vqadmin-*.rpm

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

# Install all downloaded QMT RPMs with --nodeps
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

# ─── Fix 3: Configure vpopmail User/Group ────────────────────────────────
info "Fix 3: Configuring vpopmail user/group..."
groupadd -r 89 vchkpw 2>/dev/null || true
useradd -u 89 -g 89 vpopmail -s '/sbin/nologin' 2>/dev/null || true

# Fix vpopmail home directory permissions
chmod 755 /home/vpopmail 2>/dev/null || true

# ─── Fix 4: Configure Qmail ───────────────────────────────────────────────
info "Fix 4: Configuring Qmail..."

# Enable qmail service
chkconfig qmail on 2>/dev/null || true

# Increase softlimit for SMTP
if [ -f /var/qmail/supervise/smtp/run ]; then
  sed -i 's/softlimit -m.*/softlimit -m 256000000 \\/' /var/qmail/supervise/smtp/run 2>/dev/null || true
  info "Increased SMTP softlimit to 256MB"
fi

# Wire spamdyke into the port-25 SMTP pipeline if it isn't already. QmailToaster's stock run
# script ships spamdyke's config vars commented out and never references them in the actual
# exec chain — existing installs may have been accepting mail with zero connection-level spam
# filtering. Only touches port 25; submission (587) is left alone since IP-reputation checks
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
  info "spamdyke.conf created"
fi
if [ -f /var/qmail/supervise/smtp/run ] && ! grep -q '\$SPAMDYKE --config-file' /var/qmail/supervise/smtp/run; then
  sed -i 's|^# # SPAMDYKE="/usr/bin/spamdyke"|SPAMDYKE="/usr/bin/spamdyke"|' /var/qmail/supervise/smtp/run
  sed -i 's|^# # SPAMDYKE_CONF="/etc/spamdyke/spamdyke.conf"|SPAMDYKE_CONF="/etc/spamdyke/spamdyke.conf"|' /var/qmail/supervise/smtp/run
  sed -i 's|^\(\s*\)\$SMTPD \$VCHKPW /bin/true|\1$SPAMDYKE --config-file $SPAMDYKE_CONF \\\n\1$SMTPD $VCHKPW /bin/true|' /var/qmail/supervise/smtp/run
  systemctl restart qmail-smtp 2>/dev/null || true
  info "Spamdyke wired into port-25 SMTP pipeline"
fi

# Symlink sendmail
if [ ! -h /usr/sbin/sendmail ]; then
  ln -s /var/qmail/bin/sendmail /usr/sbin/sendmail 2>/dev/null || true
  info "Created sendmail symlink"
fi

# Enable man pages for QMT
grep -q '/var/qmail/man' /etc/man_db.conf 2>/dev/null || echo "MANDATORY_MANPATH /var/qmail/man" >> /etc/man_db.conf 2>/dev/null

# Install qmail systemd service
cat > /etc/systemd/system/qmail.service << 'QMSVC'
[Unit]
Description=QmailToaster MTA (svscan)
After=network.target mariadb.service
Wants=mariadb.service

[Service]
Type=forking
User=root
Group=root
ExecStart=/usr/bin/qmailctl start
ExecStop=/usr/bin/qmailctl stop
ExecReload=/usr/bin/qmailctl restart
PIDFile=/var/run/qmail-svscan.pid
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
QMSVC
systemctl daemon-reload
systemctl enable qmail 2>/dev/null || true
info "Qmail systemd service installed"

# ─── Fix 5: Configure Dovecot for vpopmail ────────────────────────────────
info "Fix 5: Configuring Dovecot for vpopmail MySQL auth..."

# Get MySQL credentials from SysAdminHCP env file
if [[ -f "$SYSADMINHCP_ROOT/etc/sysadminhcp.env" ]]; then
  KLOXOJRA_DB_PASS=$(grep '^SYSADMINHCP_MYSQL_PASS=' "$SYSADMINHCP_ROOT/etc/sysadminhcp.env" | cut -d= -f2)
else
  warn "SysAdminHCP env file not found at $SYSADMINHCP_ROOT/etc/sysadminhcp.env"
  warn "Using default password - please update manually"
  KLOXOJRA_DB_PASS='sysadminhcp123'
fi

# Download dovecot config from QMT
wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot.conf 2>/dev/null || true
wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot-sql.conf.ext 2>/dev/null || true

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
info "Dovecot SQL auth configured"

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
info "Dovecot auth configured for SQL"

# Fix Dovecot mail config for vpopmail
sed -i 's/^first_valid_uid = .*/first_valid_uid = 89/' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true
grep -q '^mail_uid' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || sed -i '/^first_valid_uid/i mail_uid = vpopmail\nmail_gid = vchkpw' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true
grep -q '^mail_location' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || sed -i '/^mail_uid/i mail_location = maildir:/home/vpopmail/domains/%d/%n/Maildir' /etc/dovecot/conf.d/10-mail.conf 2>/dev/null || true
info "Dovecot mail config updated for vpopmail"

# ─── Fix 6: Configure ClamAV ──────────────────────────────────────────────
info "Fix 6: Configuring ClamAV..."

# Enable LocalSocket in clamd config
if [ -f /etc/clamd.d/scan.conf ]; then
  sed -i 's/^#LocalSocket /LocalSocket /' /etc/clamd.d/scan.conf 2>/dev/null || true
  info "ClamAV LocalSocket enabled"
fi

# Fix clamav directory ownership
chown -R clamupdate:clamupdate /var/lib/clamav 2>/dev/null || true

# Run freshclam if database is empty
if [[ ! -f /var/lib/clamav/main.cvd ]] && [[ ! -f /var/lib/clamav/main.cld ]]; then
  info "Running initial ClamAV database update..."
  freshclam 2>/dev/null && info "ClamAV DB updated" || warn "ClamAV DB update failed — run freshclam manually"
fi

systemctl enable clamd@scan 2>/dev/null || true
systemctl enable clamav-freshclam 2>/dev/null || true

# ─── Fix 7: Set Up vpopmail Database ──────────────────────────────────────
info "Fix 7: Setting up vpopmail database in MariaDB..."

if command -v mysql &>/dev/null && systemctl is-active --quiet mariadb; then
  # Get MySQL root password
  if [[ -f "$SYSADMINHCP_ROOT/etc/mysql-root-password" ]]; then
    MYSQL_ROOT_PASS=$(cat "$SYSADMINHCP_ROOT/etc/mysql-root-password")
  elif [[ -f /root/.my.cnf ]]; then
    MYSQL_ROOT_PASS=$(grep '^password=' /root/.my.cnf | cut -d= -f2)
  else
    MYSQL_ROOT_PASS='kloxoroot'
  fi

  # Get sysadminhcp MySQL password
  if [[ -f "$SYSADMINHCP_ROOT/etc/sysadminhcp.env" ]]; then
    KLOXOJRA_DB_PASS=$(grep '^SYSADMINHCP_MYSQL_PASS=' "$SYSADMINHCP_ROOT/etc/sysadminhcp.env" | cut -d= -f2)
  else
    KLOXOJRA_DB_PASS='sysadminhcp123'
  fi

  VPOPMAIL_DB_PASS=$(openssl rand -hex 8 2>/dev/null || echo "vpopmail123")

  mysql -u root -p"${MYSQL_ROOT_PASS}" <<EOSQL 2>/dev/null || warn "vpopmail database setup failed (may need manual configuration)"
CREATE DATABASE IF NOT EXISTS vpopmail;
CREATE USER IF NOT EXISTS 'vpopmail'@'localhost' IDENTIFIED BY '${VPOPMAIL_DB_PASS}';
GRANT ALL PRIVILEGES ON vpopmail.* TO 'vpopmail'@'localhost';
FLUSH PRIVILEGES;
EOSQL

  # Also ensure sysadminhcp user has SELECT on vpopmail
  mysql -u root -p"${MYSQL_ROOT_PASS}" <<EOSQL2 2>/dev/null || warn "sysadminhcp vpopmail grant failed"
GRANT SELECT ON vpopmail.* TO 'sysadminhcp'@'localhost';
FLUSH PRIVILEGES;
EOSQL2

  info "vpopmail database configured (password: ${VPOPMAIL_DB_PASS})"

  # Update vpopmail config with database credentials
  if [ -f /home/vpopmail/etc/vpopmail.mysql ]; then
    sed -i "s/localhost|0|vpopmailuser|vpoppasswd/localhost|0|vpopmail|${VPOPMAIL_DB_PASS}/" /home/vpopmail/etc/vpopmail.mysql 2>/dev/null || true
    info "vpopmail MySQL config updated"
  fi
else
  warn "MariaDB is not running - skipping vpopmail database setup"
  warn "Run this script again after starting MariaDB: systemctl start mariadb"
fi

# ─── Fix 8: Configure phpMyAdmin SSO ──────────────────────────────────────
info "Fix 8: Configuring phpMyAdmin SSO..."
# Ensure mysqli extension (php-mysqlnd) is present — required by phpMyAdmin
yum install -y php-mysqlnd 2>/dev/null || true

# Create PMA SSO token directory
mkdir -p /var/lib/sysadminhcp/pma-tokens
chown sysadminhcp:sysadminhcp /var/lib/sysadminhcp/pma-tokens
chmod 755 /var/lib/sysadminhcp/pma-tokens

if [[ -d /usr/share/phpMyAdmin ]]; then
  # Create signon directory
  mkdir -p /usr/share/phpMyAdmin/sysadminhcp-signon

  # Deploy signon.php from SysAdminHCP source
  SIGNON_SRC=""
  if [[ -f "$SYSADMINHCP_ROOT/httpdocs/../pma-signon/signon.php" ]]; then
    SIGNON_SRC="$SYSADMINHCP_ROOT/httpdocs/../pma-signon/signon.php"
  elif [[ -f "/usr/local/sysadminhcp/pma-signon/signon.php" ]]; then
    SIGNON_SRC="/usr/local/sysadminhcp/pma-signon/signon.php"
  fi

  if [[ -n "$SIGNON_SRC" ]]; then
    cp "$SIGNON_SRC" /usr/share/phpMyAdmin/sysadminhcp-signon/signon.php
    chown -R apache:apache /usr/share/phpMyAdmin/sysadminhcp-signon
    info "phpMyAdmin signon script deployed"
  else
    warn "signon.php not found — phpMyAdmin SSO will not work until deployed manually"
  fi

  # Deploy phpMyAdmin config with signon auth
  CONFIG_SRC=""
  if [[ -f "$SYSADMINHCP_ROOT/httpdocs/../pma-signon/config.inc.php" ]]; then
    CONFIG_SRC="$SYSADMINHCP_ROOT/httpdocs/../pma-signon/config.inc.php"
  elif [[ -f "/usr/local/sysadminhcp/pma-signon/config.inc.php" ]]; then
    CONFIG_SRC="/usr/local/sysadminhcp/pma-signon/config.inc.php"
  fi

  if [[ -n "$CONFIG_SRC" ]]; then
    cp "$CONFIG_SRC" /etc/phpMyAdmin/config.inc.php
    info "phpMyAdmin config deployed (signon auth mode)"
  else
    warn "config.inc.php not found — phpMyAdmin will use default cookie auth"
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
  warn "Install phpMyAdmin first: yum install -y phpmyadmin"
fi

# ─── Fix 9: Restart Services ───────────────────────────────────────────────
info "Fix 9: Restarting services..."

systemctl restart mariadb 2>/dev/null || warn "MariaDB failed to restart"
systemctl restart qmail 2>/dev/null || warn "Qmail failed to restart"
systemctl restart dovecot 2>/dev/null || warn "Dovecot failed to restart"
systemctl restart spamassassin 2>/dev/null || warn "SpamAssassin failed to restart"
systemctl restart clamd@scan 2>/dev/null || warn "ClamAV failed to restart"
systemctl restart httpd 2>/dev/null || warn "Apache failed to restart"
systemctl restart php-fpm 2>/dev/null || warn "PHP-FPM failed to restart"
systemctl restart sysadminhcp 2>/dev/null || warn "SysAdminHCP failed to restart"

# ─── Done ──────────────────────────────────────────────────────────────────
echo ""
info "================================================"
info "  Qmail and phpMyAdmin Fix Complete!"
info "================================================"
echo ""
info "  Services restarted:"
info "    - MariaDB"
info "    - Qmail (qmailctl stat to check status)"
info "    - Dovecot"
info "    - SpamAssassin"
info "    - ClamAV"
info "    - Apache (httpd)"
info "    - PHP-FPM"
info "    - SysAdminHCP"
echo ""
info "  Verify Qmail status:"
info "    qmailctl stat"
info "    qmailctl qstat"
echo ""
info "  Verify Dovecot auth:"
info "    doveadm auth test user@domain.com password"
echo ""
info "  Verify phpMyAdmin SSO:"
info "    Access via Admin Portal → Hosting → phpMyAdmin"
echo ""
warn "  If vpopmail database was just created, add your first domain:"
warn "    vadddomain example.com"
warn "    vadduser user@example.com password"
echo ""