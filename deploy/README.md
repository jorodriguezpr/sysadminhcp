# SysAdminHCP Deployment Guide

## Supported Operating Systems

| Installer | OS |
|---|---|
| `install-almalinux8.sh` | AlmaLinux 8 / RHEL 8 clones |
| `install-almalinux9.sh` | AlmaLinux 9 / RHEL 9 clones |
| `install-almalinux10.sh` | AlmaLinux 10 / RHEL 10 clones |
| `install-ubuntu22.sh` | Ubuntu 22.04+ / Debian (WSL or bare metal) |

## Ubuntu 22.04+ (WSL or Bare Metal)

### Quick Install

```bash
sudo bash deploy/install-ubuntu22.sh
```

### How it works

The panel's application code (routes, services, drivers) is written against the RHEL
layout (`/etc/httpd`, `/etc/named.conf`, `/var/named`, `/etc/php-fpm.d`, an `apache`
run user, `dnf`/`rpm`). Rather than forking that code per-OS, the Ubuntu installer
builds a **compatibility layer** so the exact same code paths work unchanged:

- Creates an `apache` system user/group; Apache and the default PHP-FPM pool run as it
- `systemctl restart httpd` → aliased to `apache2.service`
- `systemctl restart php-fpm` → aliased to the distro's `phpX.Y-fpm.service`
- `/etc/httpd/conf.d/*.conf` → wired into `apache2.conf` via `IncludeOptional` (panel-managed vhosts)
- `/etc/php-fpm.d` → symlinked to `/etc/php/X.Y/fpm/pool.d` (default version)
- `/etc/named.conf` → symlinked to `/etc/bind/named.conf`; `/var/named` created with an AppArmor override (Debian confines `named` to `/var/cache/bind` by default)
- `/etc/my.cnf.d/` → wired into MariaDB via `!includedir`
- `/etc/pki/tls/certs` → self-signed cert generated for code that expects RHEL cert paths
- `firewalld` replaces `ufw` so the panel's Security → Blocked/Whitelist IP pages work identically
- **qmail (notqmail), vpopmail, and spamdyke are compiled from source** into the identical `/var/qmail` and `/home/vpopmail` layout used on RHEL — none of these have Debian packages, and QmailToaster (the RHEL source) is EL-only

Code in `src/` that genuinely differs by distro (package manager, PHP multi-version
repo, BIND's run-as user) branches on `Config.isDebianFamily` / `Config.packageManager`
— see `src/config/config.ts`.

### PHP version management on Ubuntu

The distro's default PHP version (8.1 on 22.04, 8.3 on 24.04) is installed and treated
as the protected "system" version, same as PHP 8.0-on-AppStream on AlmaLinux 9.
Additional versions (7.4–8.4) come from the **ondrej/php PPA** instead of Remi — use
the same "Install Remi Repo" button in Admin Portal → Server → PHP Modules (it detects
the OS and adds the PPA on Ubuntu).

### Known limitations vs. RHEL

- SELinux policies don't apply (Ubuntu uses AppArmor; only the BIND override is added)
- spamdyke and vpopmail are source builds, not packages — upgrading them means
  re-running the relevant section of the installer with an updated version number
- phpMyAdmin's Debian package layout differs slightly (`/usr/share/phpmyadmin`,
  lowercase); the installer symlinks the RHEL-style capitalized paths the panel's
  SSO code expects

## AlmaLinux 9 (WSL or Bare Metal)

### Quick Install

```bash
# Clone or copy the sysadminhcp project, then run:
sudo bash deploy/install-almalinux9.sh
```

### What the Installer Does

1. **System update** - Updates all packages via `dnf`
2. **EPEL repo** - Installs Extra Packages for Enterprise Linux
3. **Node.js 20.x** - Installs via NodeSource repository
4. **Build tools** - Installs gcc-c++, make, python3
5. **Service dependencies** - Installs Apache, BIND, MariaDB, Pure-FTPd, PHP-FPM
6. **Kloxo user** - Creates system user `sysadminhcp`
7. **Directory structure** - Creates all required directories
8. **Application** - Compiles TypeScript and deploys to `/usr/local/sysadminhcp/httpdocs/`
9. **Environment** - Creates `/usr/local/sysadminhcp/etc/sysadminhcp.env`
10. **Permissions** - Sets ownership for sysadminhcp user
11. **Systemd service** - Installs and enables `sysadminhcp.service` (WSL-aware)
12. **Firewall** - Opens ports 7778, 7777, 80, 443
13. **SELinux** - Configures policies (bare metal only)
14. **Starts services** - MariaDB, Apache, BIND, Pure-FTPd, PHP-FPM, SysAdminHCP
15. **Verification** - Health check and database verification

### WSL Notes

- The installer auto-detects WSL and uses a compatible systemd service file
- `ProtectSystem=yes` is disabled under WSL (causes namespace errors)
- systemd must be enabled in WSL: add `[boot]\nsystemd=true` to `/etc/wsl.conf`
- After enabling systemd, restart WSL: `wsl.exe --shutdown` from Windows

### Default Credentials

- **Web UI**: `http://<server-ip>:7778/display`
- **Username**: `admin`
- **Password**: `admin`

⚠️ **Change the default password immediately after first login!**

### Service Management

```bash
sudo systemctl start sysadminhcp
sudo systemctl stop sysadminhcp
sudo systemctl restart sysadminhcp
sudo systemctl status sysadminhcp
```

### Log Files

- Application logs: `/var/log/sysadminhcp/`
- Systemd journal: `journalctl -u sysadminhcp -f`

### Configuration

Edit `/usr/local/sysadminhcp/etc/sysadminhcp.env` to change:
- Port numbers (default: 7778 HTTP, 7777 HTTPS)
- Database type (sqljs or mysql)
- Session secrets
- Default services

### Database

SysAdminHCP uses **sql.js** (embedded SQLite) by default. No external database required.

- Database file: `/usr/local/sysadminhcp/data/sysadminhcp.db`
- Tables are auto-created on first startup (`SYSADMINHCP_DB_SYNC=true`)
- Admin user is auto-seeded on first startup

For production with high traffic, switch to MariaDB:
```env
SYSADMINHCP_DB_TYPE=mysql
SYSADMINHCP_DB_HOST=localhost
SYSADMINHCP_DB_PORT=3306
SYSADMINHCP_DB_USER=sysadminhcp
SYSADMINHCP_DB_PASS=your-password
SYSADMINHCP_DB_NAME=sysadminhcp
```

### Manual Installation (if installer fails)

```bash
# 1. Install Node.js 20
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs

# 2. Create sysadminhcp user
useradd -r -s /sbin/nologin -d /usr/local/sysadminhcp sysadminhcp

# Add sysadminhcp to required groups
usermod -a -G systemd-journal sysadminhcp   # for journalctl access
usermod -a -G named sysadminhcp             # for BIND DNS access (/etc/named.conf, /var/named)

# 3. Create directories
mkdir -p /usr/local/sysadminhcp/{httpdocs,data,etc,file/template,backup,log,tmp}
mkdir -p /var/log/sysadminhcp /var/tmp/sysadminhcp /var/run/sysadminhcp /var/cache/sysadminhcp

# 4. Build and deploy
cd /path/to/sysadminhcp
npm install
npm run build
cp -r dist theme /usr/local/sysadminhcp/httpdocs/
cp package.json /usr/local/sysadminhcp/httpdocs/
cd /usr/local/sysadminhcp/httpdocs
npm install --production

# 5. Configure environment
cp .env.example /usr/local/sysadminhcp/etc/sysadminhcp.env
# Edit the env file with your settings

# 6. Set permissions
chown -R sysadminhcp:sysadminhcp /usr/local/sysadminhcp
chown -R sysadminhcp:sysadminhcp /var/log/sysadminhcp /var/tmp/sysadminhcp /var/run/sysadminhcp /var/cache/sysadminhcp

# Configure sudoers for sysadminhcp user
cat > /etc/sudoers.d/sysadminhcp-logs << 'EOF'
sysadminhcp ALL=(root) NOPASSWD: /usr/bin/tail, /usr/bin/journalctl, /usr/sbin/tail, /usr/local/sysadminhcp/scripts/install-qmail-toaster.sh, /usr/bin/cp, /usr/bin/chmod, /usr/bin/chown, /usr/bin/mkdir, /usr/bin/rm, /usr/bin/systemctl, /usr/bin/tcprules
EOF
chmod 440 /etc/sudoers.d/sysadminhcp-logs

# Set ACLs for BIND DNS access (required especially in WSL where supplementary groups don't work)
setfacl -m u:sysadminhcp:rw /etc/named.conf 2>/dev/null || true
setfacl -R -m u:sysadminhcp:rwx /var/named/ 2>/dev/null || true

# 7. Install and start service
cp deploy/sysadminhcp.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable sysadminhcp
systemctl start sysadminhcp

# 8. Verify
curl http://localhost:7778/health
```