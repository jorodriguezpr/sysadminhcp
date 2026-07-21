# SysAdminHCP Deployment Guide

## Supported Operating Systems

| Installer | OS |
|---|---|
| `install-almalinux8.sh` | AlmaLinux 8 / RHEL 8 clones (Rocky, CentOS Stream) |
| `install-almalinux9.sh` | AlmaLinux 9 / RHEL 9 clones |
| `install-almalinux10.sh` | AlmaLinux 10 / RHEL 10 clones |
| `install-ubuntu22.sh` | Ubuntu 22.04+ (tested through 24.04) / Debian |

## Recommended: One-Line Installer

```bash
curl -fsSL https://raw.githubusercontent.com/jorodriguezpr/sysadminhcp/main/autoinstall.sh | sudo bash
```

This is the standard way to install or upgrade on a fresh server. `autoinstall.sh`:

1. Detects your OS/version and picks the matching `deploy/install-*.sh` script above
2. Installs `git` + `git-lfs` if missing
3. Clones (or, on re-run, `fetch`/`reset --hard`/`lfs pull`s) the repo to `/usr/local/src/sysadminhcp`
4. Verifies the `sysadminhcp` file is a real ELF binary, not an unresolved Git LFS pointer
5. Hands off to the OS-specific installer

**Important:** this repository ships a pre-built, license-gated **pkg single-binary** (`sysadminhcp`, produced by `npm run gitdeploy:build` from a Linux/WSL2 build — see the main repo's build tooling), not application source code. The per-OS installers detect the binary and install it directly — no `npm install`/`tsc` build happens on the target server. `node-pty` (SSH terminal support) is the one dependency compiled fresh on the target host, since native modules aren't portable across kernels.

Re-running the one-liner on an already-installed server performs an **in-place upgrade**: it fetches the latest binary, swaps it in (atomic `cp` to a `.new` sibling + `mv`, safe against the running process's open fd), and restarts the service. It does not re-run destructive setup steps (existing DBs, vhosts, and certificates are left alone).

## What the Installer Does

Both the AlmaLinux and Ubuntu installers follow the same numbered steps; a few sub-steps only apply where relevant (source-built mail stack on Ubuntu vs. prebuilt QmailToaster RPMs on AlmaLinux).

1. **System update** — via `dnf`/`apt`
2. **EPEL repo** (AlmaLinux) / **base utilities** (Ubuntu) — `wget`, `curl`, `rsync`, `sshpass`, `logrotate`, `htop`, `unzip`, `tar`, `openssl`, etc.
3. **Node.js 20.x** — via NodeSource
4. **Build tools** — `gcc`/`g++`, `make`, `python3` (needed for `node-pty`'s native compile step)
5. **Service dependencies** — Apache/`httpd`, BIND, MariaDB, Pure-FTPd, PHP (+ PHP-FPM), fail2ban, ClamAV
   - 5.5 (Ubuntu only): mail stack (qmail/notqmail, vpopmail, spamdyke) compiled from source into the RHEL-style `/var/qmail` + `/home/vpopmail` layout, since none of these ship as Debian packages. AlmaLinux installs the equivalent via prebuilt QmailToaster RPMs instead.
6. **System user** — creates `sysadminhcp`
7. **Directory structure**
8. **Application install** — deploys the pre-built binary to `/usr/local/sysadminhcp/httpdocs/`; compiles `node-pty`
   - 8.5: installs the qmail-queue rate-limit wrapper (+ DKIM signing wrapper on Ubuntu)
9. **Environment** — `/usr/local/sysadminhcp/etc/sysadminhcp.env`
10. **Permissions** — ownership, sudoers validation, GoAccess install + daily web-stats cron, File Manager ACLs on existing client home directories
11. **Systemd service** — hardened unit on bare metal, WSL-aware fallback under WSL
12. **Firewall** — see port table below
    - 12.5: security tooling (fail2ban jails, ClamAV DB)
13. **SELinux** (AlmaLinux, bare metal only) / **AppArmor** (Ubuntu — only a `named`/BIND override is added; Ubuntu has no SELinux)
14. **Start services** — MariaDB, Apache, BIND, Pure-FTPd, PHP-FPM, mail stack, SysAdminHCP
    - 14.5: phpMyAdmin SSO configuration
    - 14.6 / 14.7: RainLoop and Roundcube webmail (switchable from Admin Portal → Webmail)
    - 14.8: `acme.sh` (Let's Encrypt client) install + default CA set to Let's Encrypt production
    - 14.9: `client:apache` ownership fix across all existing domain web roots
    - 14.10: central ACME HTTP-01 challenge directory (`/var/www/acme-challenge`)
15. **Verification** — health check against the running service, database file check

### Firewall ports opened

| Installer | Ports |
|---|---|
| AlmaLinux (8/9/10) | 7778 (panel HTTP), 7777 (panel HTTPS), 80, 443, DNS (53), FTP (21), 30000-31000 (FTP passive) |
| Ubuntu 22.04+ | Same as above, **plus** SMTP 25, submission 587, IMAP 143/993, POP3 110/995 (mail ports are opened here because Ubuntu's mail stack is installed by this same installer; on AlmaLinux those ports come from the separate QmailToaster RPM setup) |

WSL installs skip firewall configuration entirely (Windows handles networking).

## Access & Default Credentials

- **Web UI:** `https://<server-ip>:7777/display` (HTTPS is primary; port 7778/HTTP redirects to it automatically)
- **Username:** `admin`
- **Password:** `admin`

⚠️ **Change the default password immediately after first login** (Admin Portal → Settings), and review the Security checklist the installer prints at the end (disable SSH password auth, check Fail2ban jails, run an initial ClamAV scan).

## WSL Notes

- The installer auto-detects WSL and uses a compatible systemd service file (`ProtectSystem=yes` disabled — it causes namespace errors under WSL)
- systemd must be enabled in WSL: add `[boot]\nsystemd=true` to `/etc/wsl.conf`, then `wsl.exe --shutdown` from Windows to restart

## Service Management

```bash
sudo systemctl start sysadminhcp
sudo systemctl stop sysadminhcp
sudo systemctl restart sysadminhcp
sudo systemctl status sysadminhcp
```

RHEL-compat aliases apply on Ubuntu too (`systemctl restart httpd` → `apache2`, `php-fpm` → the distro's `phpX.Y-fpm`, `named` → `bind9`) so the panel's own service-management code works unmodified across both OS families.

## Log Files

- Application logs: `/var/log/sysadminhcp/`
- Systemd journal: `journalctl -u sysadminhcp -f`
- Revision info written to `/usr/local/sysadminhcp/etc/revision.json` on every install/upgrade — check this (not just service-restart time) to confirm which version is actually running

## Configuration

Edit `/usr/local/sysadminhcp/etc/sysadminhcp.env` to change:
- Port numbers (default: 7778 HTTP, 7777 HTTPS)
- Database type (`sqljs` or `mysql`)
- Session secrets
- Default services

## Database

SysAdminHCP uses **sql.js** (embedded, in-memory-backed SQLite file) by default. No external database required.

- Database file: `/usr/local/sysadminhcp/data/sysadminhcp.db`
- Tables are auto-created on first startup (TypeORM `synchronize: true`)
- Admin user is auto-seeded on first startup
- Because the DB is loaded into memory at process start, any direct edits to the `.db` file on disk require a service restart to take effect — the running process won't see them otherwise

For production with high traffic, switch to MariaDB:
```env
SYSADMINHCP_DB_TYPE=mysql
SYSADMINHCP_DB_HOST=localhost
SYSADMINHCP_DB_PORT=3306
SYSADMINHCP_DB_USER=sysadminhcp
SYSADMINHCP_DB_PASS=your-password
SYSADMINHCP_DB_NAME=sysadminhcp
```

## Known Limitations vs. RHEL (Ubuntu specifically)

- SELinux policies don't apply (Ubuntu uses AppArmor; only the BIND override is added)
- spamdyke and vpopmail are source builds on Ubuntu, not packages — upgrading them means re-running the relevant section of the installer with an updated version number
- phpMyAdmin's Debian package layout differs slightly (`/usr/share/phpmyadmin`, lowercase); the installer symlinks the RHEL-style capitalized paths the panel's SSO code expects

## Building From Source (development only)

The one-line installer and per-OS `install-*.sh` scripts expect a pre-built binary. If you're developing SysAdminHCP itself rather than deploying it, build and run from source instead:

```bash
# 1. Install Node.js 20
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -   # or the apt equivalent on Debian/Ubuntu
dnf install -y nodejs   # or: apt-get install -y nodejs

# 2. Create the sysadminhcp user + required groups
useradd -r -s /sbin/nologin -d /usr/local/sysadminhcp sysadminhcp
usermod -a -G systemd-journal sysadminhcp   # for journalctl access
usermod -a -G named sysadminhcp             # for BIND DNS access (/etc/named.conf, /var/named)

# 3. Create directories
mkdir -p /usr/local/sysadminhcp/{httpdocs,data,etc,file/template,backup,log,tmp}
mkdir -p /var/log/sysadminhcp /var/tmp/sysadminhcp /var/run/sysadminhcp /var/cache/sysadminhcp /var/backup/sysadminhcp

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
chown -R sysadminhcp:sysadminhcp /var/log/sysadminhcp /var/tmp/sysadminhcp /var/run/sysadminhcp /var/cache/sysadminhcp /var/backup

# Configure sudoers for the sysadminhcp user
cat > /etc/sudoers.d/sysadminhcp-logs << 'EOF'
sysadminhcp ALL=(root) NOPASSWD: /usr/bin/tail, /usr/bin/journalctl, /usr/sbin/tail, /usr/local/sysadminhcp/scripts/install-qmail-toaster.sh, /usr/bin/cp, /usr/bin/chmod, /usr/bin/chown, /usr/bin/mkdir, /usr/bin/rm, /usr/bin/systemctl, /usr/bin/tcprules, /usr/bin/firewall-cmd, /usr/bin/fail2ban-client
EOF
chmod 440 /etc/sudoers.d/sysadminhcp-logs

# Set ACLs for BIND DNS access (required especially in WSL where supplementary groups don't work)
setfacl -m u:sysadminhcp:rw /etc/named.conf 2>/dev/null || true
setfacl -R -m u:sysadminhcp:rwx /var/named/ 2>/dev/null || true

# 7. Install and start the service
cp deploy/sysadminhcp.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable sysadminhcp
systemctl start sysadminhcp

# 8. Verify
curl -k https://localhost:7777/
```

To produce a distributable pkg binary + gitdeploy release bundle from source (rather than running from `dist/` directly), see the main repo's `npm run pkg:build` / `npm run gitdeploy:build` scripts — these require a Linux environment (WSL2 works) since `pkg` only cross-builds reliably on the target OS family.
