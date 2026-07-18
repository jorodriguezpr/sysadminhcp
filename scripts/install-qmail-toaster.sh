#!/bin/bash
# SysAdminHCP - QmailToaster Install Script for AlmaLinux/Rocky 9
# Based on: http://wiki.qmailtoaster.org/index.php?title=Rocky,_Alma,_Springdale_9_QT_Install
# This script must be run as root (called via sudo from SysAdminHCP)

set -e

LOGFILE="/var/log/sysadminhcp/qmail-toaster-install.log"
mkdir -p /var/log/sysadminhcp
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== QmailToaster Install Started: $(date) ==="

# Check if already installed
if [ -d /var/qmail ] && rpm -q qmail >/dev/null 2>&1; then
    echo "Qmail-toaster is already installed. Exiting."
    exit 0
fi

# Step 1: Install QMT repo
if ! rpm -q qmt-release >/dev/null 2>&1; then
    echo "Installing QmailToaster repository..."
    cd /tmp
    rm -f qmt-release-1-8.qt.el9.noarch.rpm
    curl -L -o qmt-release-1-8.qt.el9.noarch.rpm http://repo.whitehorsetc.com/9/testing/x86_64/qmt-release-1-8.qt.el9.noarch.rpm
    rpm -ivh qmt-release-1-8.qt.el9.noarch.rpm
    # Enable qmt-testing repo (per official install guide)
    dnf config-manager --enable qmt-testing 2>/dev/null || yum-config-manager --enable qmt-testing 2>/dev/null || true
    dnf config-manager --disable qmt-current 2>/dev/null || yum-config-manager --disable qmt-current 2>/dev/null || true
    dnf clean all 2>/dev/null || yum clean all 2>/dev/null
fi

# Step 2: Remove postfix (conflicts with qmail)
echo "Removing postfix (conflicts with qmail)..."
yum remove -y postfix 2>/dev/null || dnf remove -y postfix 2>/dev/null || true
userdel postfix 2>/dev/null || true

# Step 3: Install EPEL if not present (needed for clamav, maildrop)
if ! rpm -q epel-release >/dev/null 2>&1; then
    echo "Installing EPEL repository..."
    dnf install -y epel-release
fi

# Step 4: Install qmail-toaster packages
# Note: vpopmail requires mysql-server which conflicts with MariaDB.
# We install mysql-libs (client library) first, then use --nodeps for vpopmail/qmail.
echo "Installing qmail-toaster packages..."

# Install mysql client libs (needed by vpopmail) alongside MariaDB
dnf install -y mysql-libs 2>/dev/null || yum install -y mysql-libs 2>/dev/null || true

# Install packages that don't have mysql-server dependency
yum install -y --skip-broken \
    daemontools \
    spamassassin \
    ucspi-tcp \
    libsrs2 \
    spamdyke \
    autorespond \
    control-panel \
    qmailmrtg \
    maildrop \
    isoqlog \
    ripmime \
    dovecot \
    dovecot-mysql \
    clamav \
    clamd \
    fetchmail

# Download and install vpopmail, qmail, ezmlm, simscan, qmailadmin, vqadmin with --nodeps
# (they need mysql-server which conflicts with MariaDB, but vpopmail works with MariaDB)
cd /tmp
dnf download --enablerepo=qmt-testing vpopmail qmail ezmlm simscan qmailadmin vqadmin 2>/dev/null || true
rpm -ivh --nodeps vpopmail-*.rpm 2>/dev/null || true
rpm -ivh --nodeps qmail-*.rpm 2>/dev/null || true
rpm -ivh --nodeps ezmlm-*.rpm 2>/dev/null || true
rpm -ivh --nodeps simscan-*.rpm 2>/dev/null || true
rpm -ivh --nodeps qmailadmin-*.rpm 2>/dev/null || true
rpm -ivh --nodeps vqadmin-*.rpm 2>/dev/null || true

# Step 5: Create vpopmail user/group if not present
if ! id -u vpopmail >/dev/null 2>&1; then
    groupadd -g 89 vchkpw 2>/dev/null || true
    useradd -u 89 -g 89 vpopmail -s '/sbin/nologin' 2>/dev/null || true
fi

# Step 6: Enable qmail service
echo "Enabling qmail service..."
chkconfig qmail on 2>/dev/null || systemctl enable qmail 2>/dev/null || true

# Step 7: Fix qmail smtp run script
# The qmail-toaster RPM ships with a broken line: "0 smtp \     $SMTPD" where the
# backslash is followed by spaces instead of a newline, so tcpserver tries to execute
# a literal space as the program name and drops every SMTP connection.
if [ -f /var/qmail/supervise/smtp/run ]; then
    # Increase softlimit
    sed -i 's/softlimit -m.*\\/softlimit -m 256000000 \\/' /var/qmail/supervise/smtp/run 2>/dev/null || true
    # Fix broken line continuation: "0 smtp \     $SMTPD" → proper newline continuation
    perl -i -0pe 's|(0 smtp )\\ +(\$SMTPD)|$1\\\n     $2|g' /var/qmail/supervise/smtp/run 2>/dev/null || true
    # Verify the fix applied by rewriting the file from scratch if still broken
    if grep -qP '0 smtp \\\s+\$SMTPD' /var/qmail/supervise/smtp/run 2>/dev/null; then
        QMAILDUID=$(id -u vpopmail)
        NOFILESGID=$(id -g vpopmail)
        cat > /var/qmail/supervise/smtp/run << 'RUNEOF'
#!/bin/sh
QMAILDUID=`id -u vpopmail`
NOFILESGID=`id -g vpopmail`
MAXSMTPD=`cat /var/qmail/control/concurrencyincoming`
SMTPD="/var/qmail/bin/qmail-smtpd"
TCP_CDB="/etc/tcprules.d/tcp.smtp.cdb"
HOSTNAME=`hostname`
VCHKPW="/home/vpopmail/bin/vchkpw"
export SMTPAUTH="-"

exec /usr/bin/softlimit -m 256000000 \
     /usr/bin/tcpserver -v -R -H -l $HOSTNAME -x $TCP_CDB -c "$MAXSMTPD" \
     -u "$QMAILDUID" -g "$NOFILESGID" 0 smtp \
     $SMTPD $VCHKPW /bin/true 2>&1
RUNEOF
        chmod +x /var/qmail/supervise/smtp/run
    fi
    echo "qmail smtp run script configured"
fi

# Step 8: Configure clamav
if [ -f /etc/clamd.d/scan.conf ]; then
    sed -i 's/^#LocalSocket /LocalSocket /' /etc/clamd.d/scan.conf 2>/dev/null || true
fi
chown -R clamupdate:clamupdate /var/lib/clamav 2>/dev/null || true

# Step 9: Configure dovecot for vpopmail MySQL auth
if [ -f /etc/dovecot/dovecot.conf ]; then
    mv /etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf.bak 2>/dev/null || true
fi
if [ -f /etc/dovecot/dovecot-sql.conf.ext ]; then
    mv /etc/dovecot/dovecot-sql.conf.ext /etc/dovecot/dovecot-sql.conf.ext.bak 2>/dev/null || true
fi

# Download dovecot config from QMT
if [ ! -f /etc/dovecot/dovecot.conf ]; then
    wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot.conf 2>/dev/null || true
fi
if [ ! -f /etc/dovecot/dovecot-sql.conf.ext ]; then
    wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot-sql.conf.ext 2>/dev/null || true
fi

# Step 10: Symlink sendmail
if [ ! -h /usr/sbin/sendmail ]; then
    ln -s /var/qmail/bin/sendmail /usr/sbin/sendmail 2>/dev/null || true
fi

# Step 11: Enable man pages for QMT
if ! grep -q '/var/qmail/man' /etc/man_db.conf 2>/dev/null; then
    echo "MANDATORY_MANPATH /var/qmail/man" >> /etc/man_db.conf 2>/dev/null || true
fi

# Step 12: Download ClamAV database
echo "Downloading ClamAV database..."
freshclam 2>/dev/null || true

# Step 13: Start services
echo "Starting mail services..."
systemctl enable --now clamd@scan 2>/dev/null || true
systemctl enable --now clamav-freshclam 2>/dev/null || true
systemctl enable --now dovecot 2>/dev/null || true
systemctl enable --now spamassassin 2>/dev/null || true

# Step 14: Create qmail systemd service
if [ ! -f /etc/systemd/system/qmail.service ]; then
    cat > /etc/systemd/system/qmail.service << 'QMailservice'
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
QMailservice
    systemctl daemon-reload
    systemctl enable qmail
fi
systemctl start qmail 2>/dev/null || true

# Step 15: Fix vpopmail home directory permissions (sysadminhcp user needs access)
chmod 755 /home/vpopmail 2>/dev/null || true

# Step 16: Set up vpopmail database in MariaDB
if [ -f /home/vpopmail/etc/vpopmail.mysql ]; then
    VPOPMAIL_DB_PASS=$(grep '|' /home/vpopmail/etc/vpopmail.mysql | cut -d'|' -f4)
    VPOPMAIL_DB_USER=$(grep '|' /home/vpopmail/etc/vpopmail.mysql | cut -d'|' -f3)
    VPOPMAIL_DB_NAME=$(grep '|' /home/vpopmail/etc/vpopmail.mysql | cut -d'|' -f5)
    if [ -n "$VPOPMAIL_DB_PASS" ] && [ -n "$VPOPMAIL_DB_USER" ]; then
        mysql -u root -e "CREATE DATABASE IF NOT EXISTS $VPOPMAIL_DB_NAME;" 2>/dev/null || true
        mysql -u root -e "CREATE USER IF NOT EXISTS '${VPOPMAIL_DB_USER}'@'localhost' IDENTIFIED BY '${VPOPMAIL_DB_PASS}';" 2>/dev/null || true
        mysql -u root -e "GRANT ALL PRIVILEGES ON ${VPOPMAIL_DB_NAME}.* TO '${VPOPMAIL_DB_USER}'@'localhost';" 2>/dev/null || true
        mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    fi
fi

# Step 17: Set permissions for sysadminhcp user to access mail logs
setfacl -m u:sysadminhcp:r /var/log/maillog 2>/dev/null || true

echo "=== QmailToaster Install Completed: $(date) ==="
echo "Run 'qmailctl stat' or 'toaststat' to check service status."