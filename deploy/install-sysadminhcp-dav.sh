#!/bin/bash
# SysAdminHCP - Calendar & Contacts (CalDAV/CardDAV) install script.
# Installs Radicale (pip, pinned) in a dedicated venv + our vpopmail-auth/domain-rights
# plugin package. Called via sudo from the panel (RadicaleDriver.install()).
set -euo pipefail

DAV_PLUGIN_SRC="/usr/local/sysadminhcp/httpdocs/deploy/dav-plugin"
DAV_VENV="/opt/sysadminhcp-dav-venv"
DAV_CONFIG_DIR="/etc/sysadminhcp-dav"
DAV_DATA_DIR="/var/lib/sysadminhcp-dav"
DAV_USER="sysadminhcp-dav"

echo "=== SysAdminHCP Calendar & Contacts (Radicale) install ==="

# Step 1: find a Python >= 3.9 interpreter. Radicale 3.7.7 requires it, but several
# supported OSes here (AlmaLinux 8's default /usr/bin/python3 is 3.6, EOL and years
# below Radicale's floor) don't have one as the default `python3`. Prefer the newest
# already-present interpreter; only reach for dnf if nothing suitable exists.
DAV_PY=""
for cand in python3.12 python3.11 python3.10 python3.9; do
  if command -v "$cand" >/dev/null 2>&1; then
    DAV_PY="$cand"
    break
  fi
done

if [[ -z "$DAV_PY" ]]; then
  if command -v dnf >/dev/null 2>&1; then
    dnf module enable -y python39 >/dev/null 2>&1 || true
    dnf install -y python39 python39-pip >/dev/null 2>&1 || true
    command -v python3.9 >/dev/null 2>&1 && DAV_PY="python3.9"
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get install -y python3 python3-pip python3-venv >/dev/null 2>&1 || true
    command -v python3 >/dev/null 2>&1 && DAV_PY="python3"
  fi
fi

if [[ -z "$DAV_PY" ]]; then
  echo "ERROR: no Python >= 3.9 interpreter found or installable (Radicale requires it)" >&2
  exit 1
fi
echo "Using interpreter: $($DAV_PY --version)"

# Step 2: dedicated venv — sidesteps PEP 668 "externally-managed-environment" restrictions
# on modern RHEL9+/Ubuntu22+ entirely (no system-Python packages touched, no
# --break-system-packages needed).
# Debian/Ubuntu's python3.X package deliberately ships without ensurepip/venv support —
# it's a separate python3.X-venv package even when python3.X itself is already present and
# found above (confirmed live: Ubuntu 22 with python3.12 already installed still failed venv
# creation with "ensurepip is not available" until python3.12-venv was installed explicitly).
if ! "$DAV_PY" -m venv "$DAV_VENV" 2>/tmp/dav_venv_err.log; then
  if grep -q "ensurepip is not available" /tmp/dav_venv_err.log && command -v apt-get >/dev/null 2>&1; then
    ver="${DAV_PY#python}"
    # apt-get update first — a stale package index is the likely reason this fails silently
    # on a VPS that hasn't refreshed it recently (confirmed as a real factor live: the same
    # apt-get install line that failed inside a fresh script run succeeded run manually
    # moments later with no other change, on a box that also had a pending kernel update).
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y "python${ver}-venv" python3-venv
    rm -rf "$DAV_VENV"
    "$DAV_PY" -m venv "$DAV_VENV"
  else
    cat /tmp/dav_venv_err.log >&2
    rm -f /tmp/dav_venv_err.log
    exit 1
  fi
fi
rm -f /tmp/dav_venv_err.log
"$DAV_VENV/bin/pip" install --upgrade pip >/dev/null

# Step 3: Radicale (pinned) + our plugin package (auth.py + rights.py)
"$DAV_VENV/bin/pip" install "radicale==3.7.7" vobject mysql-connector-python
"$DAV_VENV/bin/pip" install "$DAV_PLUGIN_SRC"

# Step 4: dedicated user/group + storage dirs
groupadd -r "$DAV_USER" 2>/dev/null || true
useradd -r -g "$DAV_USER" -d "$DAV_DATA_DIR" -s /sbin/nologin "$DAV_USER" 2>/dev/null || true

mkdir -p "$DAV_DATA_DIR/collections" "$DAV_CONFIG_DIR"
chown -R "$DAV_USER:$DAV_USER" "$DAV_DATA_DIR"
chmod 750 "$DAV_DATA_DIR"

# Step 5: read the vpopmail MySQL password — same credential Dovecot's own
# dovecot-sql.conf.ext already uses (see install-almalinux9.sh's KLOXOJRA_DB_PASS block),
# not a new secret to manage.
DB_PASS=""
if [[ -f /etc/dovecot/dovecot-sql.conf.ext ]]; then
  DB_PASS=$(sed -n "s/.*user=sysadminhcp password=\([^ ]*\).*/\1/p" /etc/dovecot/dovecot-sql.conf.ext | head -1)
fi
if [[ -z "$DB_PASS" ]]; then
  echo "ERROR: could not read vpopmail MySQL password from /etc/dovecot/dovecot-sql.conf.ext" >&2
  exit 1
fi

# Step 5b: internal service credential (panel <-> Radicale, for shared-collection
# provisioning and the public feed export — see sysadminhcp_dav/_service.py). Reuse
# the existing one across re-installs/upgrades so previously-provisioned shared
# collections don't lose panel access; only generate fresh on a true first install.
SERVICE_PASS=""
if [[ -f "$DAV_CONFIG_DIR/config" ]]; then
  SERVICE_PASS=$(sed -n "s/^service_password = \(.*\)$/\1/p" "$DAV_CONFIG_DIR/config" | head -1)
fi
if [[ -z "$SERVICE_PASS" ]]; then
  SERVICE_PASS=$(openssl rand -hex 24)
fi

# Step 6: config
cat > "$DAV_CONFIG_DIR/config" << EOF
[server]
hosts = 127.0.0.1:5232
max_connections = 20
max_content_length = 10000000
script_name = /dav

[auth]
type = sysadminhcp_dav.auth
mysql_host = 127.0.0.1
mysql_port = 3306
mysql_db = vpopmail
mysql_user = sysadminhcp
mysql_password = $DB_PASS
service_password = $SERVICE_PASS
realm = SysAdminHCP Calendar
delay = 1
cache_logins = True
cache_successful_logins_expiry = 15
cache_failed_logins_expiry = 90

[storage]
type = multifilesystem
filesystem_folder = $DAV_DATA_DIR/collections
max_sync_token_age = 2592000

[rights]
type = sysadminhcp_dav.rights

[web]
type = internal

[sharing]
type = csv
collection_by_map = True
collection_by_token = True
permit_create_token = True
permit_create_map = True

[logging]
level = info
EOF

chown "root:$DAV_USER" "$DAV_CONFIG_DIR/config"
chmod 640 "$DAV_CONFIG_DIR/config"

# Step 7: systemd service
cat > /etc/systemd/system/sysadminhcp-dav.service << EOF
[Unit]
Description=SysAdminHCP Calendar & Contacts (CalDAV/CardDAV)
After=network.target mariadb.service
Wants=mariadb.service

[Service]
Type=simple
User=$DAV_USER
Group=$DAV_USER
ExecStart=$DAV_VENV/bin/radicale --config $DAV_CONFIG_DIR/config
Restart=on-failure
RestartSec=5
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=$DAV_DATA_DIR

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now sysadminhcp-dav

echo "sysadminhcp-dav (Radicale 3.7.7, pip-installed in $DAV_VENV) installed and started on 127.0.0.1:5232"
echo "Auth: vpopmail MySQL (direct) — no Dovecot dependency required"
