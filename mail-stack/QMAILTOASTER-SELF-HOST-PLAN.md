# SysAdminHCP — Self-Hosted QmailToaster Build & Integration Plan

> **Goal**: Build, package, and ship the **entire QmailToaster mail stack** from source
> within the SysAdminHCP project, eliminating all runtime dependencies on external RPM
> repositories (`repo.whitehorsetc.com`, Copr `kloxong/kloxo-qmail`) for all current
> and future SysAdminHCP installations on AlmaLinux 8/9/10 (and Ubuntu/Debian).

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Current Architecture Analysis](#2-current-architecture-analysis)
3. [Component Inventory](#3-component-inventory)
4. [Build Dependency Graph](#4-build-dependency-graph)
5. [Proposed Repository Structure](#5-proposed-repository-structure)
6. [Build System Design](#6-build-system-design)
7. [Packaging Strategy](#7-packaging-strategy)
8. [Integration with SysAdminHCP](#8-integration-with-sysadminhcp)
9. [AlmaLinux 10 Specific Challenges](#9-almalinux-10-specific-challenges)
10. [Migration & Upgrade Path](#10-migration--upgrade-path)
11. [Testing Strategy](#11-testing-strategy)
12. [Implementation Phases](#12-implementation-phases)
13. [Risk Assessment](#13-risk-assessment)

---

## 1. Problem Statement

### Current State

SysAdminHCP's mail stack depends on **pre-built QMT RPMs** from two external sources:

| Source | URL | Used For | Status |
|--------|-----|----------|--------|
| Whitehorse TC | `http://repo.whitehorsetc.com/{8,9,10}/testing/x86_64/` | All QMT packages | **Unstable** — version filenames change without notice |
| Copr (kloxong) | `download.copr.fedorainfracloud.org/results/kloxong/kloxo-qmail/` | Legacy KloxoNG packages | **Stale** — not updated for EL10 |
| QMT GitHub | `raw.githubusercontent.com/qmtoaster/scripts/master/` | Dovecot config files | **Static** — config only, no packages |

### Specific Issues on AlmaLinux 10

1. **`libmysqlclient.so.24` missing**: EL10 ships only MariaDB Connector/C (`libmariadb.so`), not the legacy `libmysqlclient.so.24` that prebuilt vpopmail/qmail RPMs link against. Mail delivery and mailbox creation silently fail.

2. **QMT repo URL instability**: The `qmt-release` RPM filename has already changed version numbers (`1-8` → `1-9`), causing 404s that silently break installs — the panel reports success with an empty `/var/qmail/`.

3. **`--nodeps` workaround fragility**: vpopmail, qmail, ezmlm, simscan, qmailadmin, and vqadmin are installed with `rpm -ivh --nodeps` to bypass the `mysql-server` vs MariaDB conflict. This masks missing shared libraries at install time.

4. **Broken RPM run scripts**: The QMT qmail RPM ships a broken `smtp/run` script (backslash-space instead of newline continuation) that drops every SMTP connection until manually patched.

5. **No EL10 packages in stable channel**: `10/current/x86_64/` is empty; only `testing` has packages.

6. **spamdyke TLS cipher bug**: QMT's default `spamdyke.conf` passes TLS 1.3 ciphersuite names to OpenSSL's legacy `SSL_CTX_set_cipher_list()`, which doesn't accept them.

### What We Need

A **self-contained, source-built mail stack** that:
- Compiles every QMT component from source against the target OS's actual libraries
- Produces our own RPMs (for RHEL-family) and .deb packages (for Debian-family)
- Ships all config templates, supervise scripts, and systemd units from our repo
- Never fetches anything from `repo.whitehorsetc.com`, Copr, or QMT GitHub at install time
- Works identically on AlmaLinux 8, 9, 10, Rocky, CentOS, RHEL, Ubuntu 22/24, and Debian 12

---

## 2. Current Architecture Analysis

### Mail Stack Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    SysAdminHCP Panel                         │
│              (Node.js/TypeScript — sysadminhcp/)             │
│                                                             │
│  mailService.ts ──► /home/vpopmail/bin/ (vadddomain, etc.)  │
│  dovecotSniService.ts ──► /etc/dovecot/ (per-domain SNI)   │
│  webmailService.ts ──► RainLoop/Roundcube                   │
│  qmail-ai-filter/ ──► AI spam filter (.qmail-default)       │
└──────────────────────┬──────────────────────────────────────┘
                       │ sudo / shell exec
┌──────────────────────▼──────────────────────────────────────┐
│                   Mail Stack (on server)                     │
│                                                             │
│  qmail (MTA) ─── /var/qmail                                 │
│    ├── qmail-smtpd (port 25/587/465)                        │
│    ├── qmail-send (delivery)                                │
│    ├── daemontools supervise (or systemd units on EL10)     │
│    └── spamdyke (SMTP filtering + TLS)                      │
│                                                             │
│  vpopmail ─── /home/vpopmail                                │
│    ├── MySQL auth (vpopmail.vpopmail table)                 │
│    ├── vadddomain/vadduser/vpasswd/vsetuserquota            │
│    └── Maildir storage at /home/vpopmail/domains/           │
│                                                             │
│  Dovecot ─── IMAP 143/993, POP3 110/995                     │
│    ├── vpopmail MySQL SQL auth (CRYPT password scheme)     │
│    ├── per-domain SNI (Let's Encrypt certs)                 │
│    └── mail_uid=vpopmail, mail_gid=vchkpw                  │
│                                                             │
│  SpamAssassin + ClamAV (via simscan at SMTP time)           │
│  ezmlm (mailing lists)                                     │
│  qmailadmin / vqadmin (web admin CGI)                      │
└─────────────────────────────────────────────────────────────┘
```

### Current Install Flow (AlmaLinux 9/10)

```
install-almalinux{9,10}.sh
  │
  ├── curl qmt-release RPM from repo.whitehorsetc.com     ← EXTERNAL DEP
  ├── rpm -ivh qmt-release (registers yum repo)
  ├── dnf install daemontools ucspi-tcp spamdyke ...       ← from QMT repo
  ├── dnf download vpopmail qmail ezmlm simscan ...        ← from QMT repo
  ├── rpm -ivh --nodeps vpopmail-*.rpm qmail-*.rpm ...     ← fragile
  ├── wget dovecot.conf from github.com/qmtoaster         ← EXTERNAL DEP
  ├── Patch smtp/run script (fix broken RPM)
  ├── Wire spamdyke into smtp/run
  ├── Create systemd units (qmail-send, qmail-smtp, qmail-submission)
  └── Configure Dovecot SQL auth against vpopmail MySQL
```

### Current Install Flow (Ubuntu 22)

```
install-ubuntu22.sh
  │
  ├── Build notqmail from GitHub release tarball            ← EXTERNAL (but source)
  ├── Build vpopmail from SourceForge tarball               ← EXTERNAL (but source)
  ├── Build spamdyke from spamdyke.org / GitHub              ← EXTERNAL (but source)
  ├── apt-get install dovecot, spamassassin, ucspi-tcp      ← OS packages
  └── Create config templates, systemd units
```

### Key Files That Drive the Mail Stack

| File | Role |
|------|------|
| `sysadminhcp/scripts/install-qmail-toaster.sh` | Standalone QMT installer (called via sudo) |
| `sysadminhcp/deploy/install-almalinux{8,9,10}.sh` | Full OS provisioning (includes QMT install) |
| `sysadminhcp/deploy/install-ubuntu22.sh` | Ubuntu install (already source-builds qmail/vpopmail/spamdyke) |
| `sysadminhcp/src/services/mailService.ts` | Panel mail service (vpopmail CLI, queue, status) |
| `sysadminhcp/src/services/dovecotSniService.ts` | Dovecot per-domain SSL/SNI |
| `sysadminhcp/deploy/qmail-ai-filter/` | AI spam filter (PHP, deployed to `/opt/qmail-ai-filter`) |
| `sysadminhcp/deploy/qmail-queue-check.sh` | qmail-queue rate-limit wrapper |
| `kloxo/file/qmail/` | Legacy config templates (supervise scripts, courier/dovecot configs) |
| `kloxo/file/template/spamdyke.conf` | Legacy spamdyke config template |

---

## 3. Component Inventory

### Core QMT Components (must build from source)

| # | Component | Upstream Source | Version | Build System | Key Dependencies | Priority |
|---|-----------|----------------|---------|--------------|------------------|----------|
| 1 | **notqmail** | `github.com/notqmail/notqmail` | 1.08 (1.09 dev) | DJB Makefile | ucspi-tcp, daemontools | **Critical** |
| 2 | **vpopmail** | `github.com/notqmail/vpopmail` | 5.4.x | autoconf | notqmail, MySQL/MariaDB | **Critical** |
| 3 | **ucspi-tcp** | `github.com/notqmail/ucspi-tcp` | 0.88 (patched) | DJB Makefile | None | **Critical** |
| 4 | **daemontools** | `github.com/notqmail/daemontools` | 0.76 (patched) | DJB Makefile | None | **Critical** |
| 5 | **vqadmin** | `github.com/notqmail/vqadmin` | 2.3.x | autoconf | vpopmail | High |
| 6 | **qmailadmin** | `github.com/notqmail/qmailadmin` | 1.2.x | autoconf | vpopmail, ezmlm, autorespond | High |
| 7 | **simscan** | `github.com/notqmail/simscan` | 1.4.x | autoconf | notqmail, clamav, spamassassin, ripmime | High |
| 8 | **ezmlm-idx** | `github.com/notqmail/ezmlm-idx` | 0.53x | DJB Makefile | notqmail, optional MySQL | Medium |
| 9 | **autorespond** | `github.com/notqmail/autorespond` | 2.0.x | Makefile | notqmail | Medium |
| 10 | **spamdyke** | `github.com/spamdyke/spamdyke` | 5.0.1 | autoconf | notqmail, ucspi-tcp, openssl | **Critical** |
| 11 | **libsrs2** | `github.com/libsrs2/libsrs2` | 1.0.x | autoconf | None | Medium |
| 12 | **ripmime** | `github.com/wettenhaller/ripMIME` | 1.4.x | Makefile | None | Medium |
| 13 | **maildrop** | `github.com/courier/maildrop` | 3.x | autoconf | courier-unicode, pcre2 | Low |
| 14 | **libdomainkeys** | SourceForge (abandoned) | 0.69 | Makefile | notqmail, openssl | Low (DKIM supersedes) |

### Supporting Components (from OS repos, not built from source)

| # | Component | Source | Notes |
|---|-----------|--------|-------|
| 15 | **Dovecot** | OS package (dnf/apt) | IMAP/POP3, MySQL auth — config is ours |
| 16 | **SpamAssassin** | OS package | Spam filtering — called by simscan |
| 17 | **ClamAV** | OS package | Antivirus — called by simscan |
| 18 | **fetchmail** | OS package | Remote mail retrieval |
| 19 | **mrtg** | OS package (optional) | For qmailmrtg graphs |

### Abandoned / Optional Components

| # | Component | Status | Recommendation |
|---|-----------|--------|----------------|
| 20 | **qmailmrtg** | Abandoned, no GitHub mirror | Fork into our repo or replace with modern monitoring |
| 21 | **isoqlog** | Abandoned, no GitHub mirror | Fork into our repo or replace with modern log analyzer |
| 22 | **control-panel** | QMT meta-package | Replace with our own meta-package |

### Config & Runtime Artifacts (ours, not upstream)

| Artifact | Current Location | Notes |
|----------|-----------------|-------|
| Dovecot SQL auth config | Generated by install script | `/etc/dovecot/dovecot-sql.conf.ext` |
| Dovecot main config | Downloaded from QMT GitHub | Must ship our own |
| qmail supervise scripts | From QMT RPM (broken) | Must ship our own (already patched in install script) |
| qmail systemd units | Generated by install script | `qmail-send.service`, `qmail-smtp.service`, `qmail-submission.service` |
| spamdyke config | Generated by install script | `/etc/spamdyke/spamdyke.conf`, `spamdyke-submission.conf` |
| tcp.smtp rules | From QMT RPM | `/etc/tcprules.d/tcp.smtp` and `.cdb` |
| qmail-queue wrapper | `deploy/qmail-queue-check.sh` | Rate limiting |
| AI spam filter | `deploy/qmail-ai-filter/` | PHP, our code |

---

## 4. Build Dependency Graph

```
                    ┌─────────────┐
                    │ ucspi-tcp   │ (no deps)
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ daemontools │ (no deps)
                    └──────┬──────┘
                           │
              ┌────────────▼────────────┐
              │      notqmail (qmail)    │
              │  needs: ucspi-tcp,      │
              │        daemontools      │
              └────────────┬────────────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
   ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐
   │  vpopmail   │  │ autorespond │  │ libsrs2     │
   │ needs: qmail│  │ needs: qmail│  │ (no deps)   │
   │       MySQL │  └─────────────┘  └─────────────┘
   └──────┬──────┘
          │
   ┌──────┼──────────────────────────┐
   │      │                          │
┌──▼───┐ ┌▼──────────┐  ┌───────────▼──────────┐
│ezmlm │ │ qmailadmin│  │      vqadmin          │
│-idx  │ │ needs:    │  │  needs: vpopmail      │
│needs:│ │ vpopmail, │  └──────────────────────┘
│qmail │ │ ezmlm,    │
│MySQL?│ │ autoresp.  │
└──────┘ └───────────┘

          ┌─────────────┐
          │   ripmime   │ (no deps)
          └──────┬──────┘
                 │
          ┌──────▼──────┐
          │   simscan   │
          │ needs: qmail│
          │   clamav   │
          │ spamassassin│
          │   ripmime  │
          └────────────┘

          ┌─────────────┐
          │  spamdyke   │
          │ needs: qmail│
          │  ucspi-tcp  │
          │   openssl   │
          └─────────────┘

          ┌─────────────┐
          │libdomainkeys│ (optional, DKIM supersedes)
          │ needs: qmail│
          │   openssl   │
          └─────────────┘

          ┌─────────────┐
          │  maildrop   │ (standalone, no qmail dep)
          └─────────────┘
```

### Build Order (topological sort)

| Step | Component | Depends On (already built) |
|------|-----------|---------------------------|
| 1 | ucspi-tcp | — |
| 2 | daemontools | — |
| 3 | libsrs2 | — |
| 4 | ripmime | — |
| 5 | notqmail | ucspi-tcp, daemontools |
| 6 | vpopmail | notqmail, MySQL/MariaDB dev headers |
| 7 | autorespond | notqmail |
| 8 | ezmlm-idx | notqmail, (optional: MySQL) |
| 9 | libdomainkeys | notqmail, openssl (optional) |
| 10 | spamdyke | notqmail, ucspi-tcp, openssl |
| 11 | simscan | notqmail, clamav, spamassassin, ripmime |
| 12 | qmailadmin | vpopmail, ezmlm-idx, autorespond |
| 13 | vqadmin | vpopmail |
| 14 | maildrop | courier-unicode, pcre2 (standalone) |

---

## 5. Proposed Repository Structure

A new `mail-stack/` directory at the root of the SysAdminHCP project (alongside `sysadminhcp/`):

```
kloxo-8.0.0-25/
├── sysadminhcp/                    # existing panel code
├── kloxo/                          # legacy PHP panel
│
└── mail-stack/                     # NEW — self-hosted QMT build system
    ├── README.md                   # Build & packaging guide
    ├── Makefile                    # Top-level orchestrator: `make all`, `make rpms`, `make debs`
    ├── build.env                   # Shared build variables (versions, paths, UID/GID)
    │
    ├── sources/                    # Git submodules / vendored source tarballs
    │   ├── notqmail/               # submodule → github.com/notqmail/notqmail
    │   ├── vpopmail/                # submodule → github.com/notqmail/vpopmail
    │   ├── ucspi-tcp/               # submodule → github.com/notqmail/ucspi-tcp
    │   ├── daemontools/             # submodule → github.com/notqmail/daemontools
    │   ├── simscan/                 # submodule → github.com/notqmail/simscan
    │   ├── qmailadmin/              # submodule → github.com/notqmail/qmailadmin
    │   ├── vqadmin/                 # submodule → github.com/notqmail/vqadmin
    │   ├── ezmlm-idx/               # submodule → github.com/notqmail/ezmlm-idx
    │   ├── autorespond/             # submodule → github.com/notqmail/autorespond
    │   ├── spamdyke/                # submodule → github.com/spamdyke/spamdyke
    │   ├── libsrs2/                 # submodule → github.com/libsrs2/libsrs2
    │   ├── ripmime/                 # submodule → github.com/wettenhaller/ripMIME
    │   ├── maildrop/                # submodule → github.com/courier/maildrop
    │   └── libdomainkeys/           # vendored tarball (SourceForge, abandoned)
    │
    ├── patches/                    # Our patches applied on top of upstream
    │   ├── notqmail/
    │   │   ├── 01-el10-compat.patch       # EL10 library path fixes
    │   │   └── 02-sysadminhcp-paths.patch  # Custom paths if needed
    │   ├── vpopmail/
    │   │   ├── 01-gcc14-fcommon.patch     # -fcommon for GCC 10+ (multiple definition fix)
    │   │   ├── 02-mariadb-compat.patch    # MariaDB Connector/C compatibility
    │   │   └── 03-el10-libpath.patch      # EL10 library path detection
    │   ├── ucspi-tcp/
    │   │   └── 01-errno.patch             # errno declaration fix (from notqmail mirror)
    │   ├── daemontools/
    │   │   └── 01-errno.patch             # errno declaration fix
    │   ├── spamdyke/
    │   │   └── 01-tls-cipher-fix.patch    # Fix TLS cipher list for OpenSSL 3.x
    │   └── simscan/
    │       └── 01-el10-clamav.patch       # ClamAV API changes for EL10
    │
    ├── specs/                      # RPM spec files (one per component)
    │   ├── sysadminhcp-qmail.spec
    │   ├── sysadminhcp-vpopmail.spec
    │   ├── sysadminhcp-ucspi-tcp.spec
    │   ├── sysadminhcp-daemontools.spec
    │   ├── sysadminhcp-simscan.spec
    │   ├── sysadminhcp-qmailadmin.spec
    │   ├── sysadminhcp-vqadmin.spec
    │   ├── sysadminhcp-ezmlm.spec
    │   ├── sysadminhcp-autorespond.spec
    │   ├── sysadminhcp-spamdyke.spec
    │   ├── sysadminhcp-libsrs2.spec
    │   ├── sysadminhcp-ripmime.spec
    │   ├── sysadminhcp-maildrop.spec
    │   └── sysadminhcp-mail-meta.spec     # Meta-package that pulls everything
    │
    ├── debian/                     # Debian packaging (control files)
    │   ├── sysadminhcp-qmail/
    │   │   ├── debian/
    │   │   │   ├── control
    │   │   │   ├── rules
    │   │   │   ├── changelog
    │   │   │   └── compat
    │   ├── sysadminhcp-vpopmail/
    │   │   └── debian/...
    │   └── ... (one dir per component)
    │
    ├── config/                     # Our config templates (NOT from upstream RPMs)
    │   ├── qmail/
    │   │   ├── supervise/
    │   │   │   ├── smtp/run              # Fixed smtp run script (no broken backslash)
    │   │   │   ├── smtp/log/run
    │   │   │   ├── submission/run        # Port 587 with spamdyke + auth
    │   │   │   ├── submission/log/run
    │   │   │   ├── send/run
    │   │   │   └── send/log/run
    │   │   ├── control/
    │   │   │   ├── defaultdelivery       # ./Maildir/
    │   │   │   ├── concurrencyincoming  # 20
    │   │   │   ├── concurrencyremote     # 40
    │   │   │   └── queuelifetime         # 604800
    │   │   ├── tcprules/
    │   │   │   └── tcp.smtp              # Default tcprules (allow, RELAYCLIENT)
    │   │   └── rc                         # qmail-start wrapper
    │   │
    │   ├── dovecot/
    │   │   ├── dovecot.conf               # Our Dovecot config (not QMT's)
    │   │   ├── dovecot-sql.conf.ext       # vpopmail MySQL auth (CRYPT scheme)
    │   │   └── conf.d/
    │   │       ├── 10-mail.conf           # mail_uid=vpopmail, mail_gid=vchkpw
    │   │       ├── 10-auth.conf           # SQL auth backend
    │   │       └── 10-master.conf         # IMAP/POP3 service ports
    │   │
    │   ├── spamdyke/
    │   │   ├── spamdyke.conf              # Port 25: full anti-spam + TLS
    │   │   └── spamdyke-submission.conf   # Port 587: TLS + AUTH only (no RBL)
    │   │
    │   └── systemd/
    │       ├── qmail-send.service         # qmail-send via systemd (EL10)
    │       ├── qmail-smtp.service          # qmail-smtpd via systemd
    │       ├── qmail-submission.service    # qmail submission via systemd
    │       └── qmail.service               # Legacy svscan wrapper (EL8/9)
    │
    ├── scripts/                    # Build & install scripts
    │   ├── build-all.sh            # Build all components from source
    │   ├── build-rpms.sh            # Build all RPMs (calls rpmbuild per spec)
    │   ├── build-debs.sh            # Build all .deb packages
    │   ├── install-from-source.sh  # Install directly from source (no RPMs)
    │   ├── install-from-rpms.sh     # Install from our own RPMs
    │   ├── install-from-debs.sh     # Install from our own .deb packages
    │   └── create-vpopmail-db.sh    # Create vpopmail MySQL database & user
    │
    └── ci/                         # CI/CD pipeline definitions
        ├── github-actions/
        │   ├── build-rpms-el8.yml
        │   ├── build-rpms-el9.yml
        │   ├── build-rpms-el10.yml
        │   └── build-debs-ubuntu.yml
        └── docker/
            ├── Dockerfile.el8      # Build container for EL8 RPMs
            ├── Dockerfile.el9      # Build container for EL9 RPMs
            ├── Dockerfile.el10     # Build container for EL10 RPMs
            └── Dockerfile.ubuntu   # Build container for .deb packages
```

---

## 6. Build System Design

### 6.1 Top-Level Makefile

```makefile
# mail-stack/Makefile
include build.env

COMPONENTS = ucspi-tcp daemontools libsrs2 ripmime \
             notqmail vpopmail autorespond ezmlm-idx \
             spamdyke simscan qmailadmin vqadmin maildrop

.PHONY: all sources rpms debs install clean

all: sources rpms

sources:
	@for comp in $(COMPONENTS); do \
		echo "=== Building $$comp from source ==="; \
		$(MAKE) -C build/$$comp || exit 1; \
	done

rpms: sources
	@for spec in specs/*.spec; do \
		echo "=== Building RPM from $$spec ==="; \
		rpmbuild -bb $$spec || exit 1; \
	done

debs: sources
	@for pkg in debian/*/; do \
		echo "=== Building .deb from $$pkg ==="; \
		(cd $$pkg && dpkg-buildpackage -us -uc -b) || exit 1; \
	done

install: sources
	scripts/install-from-source.sh

clean:
	rm -rf build/ rpmbuild/RPMS/ rpmbuild/SRPMS/
```

### 6.2 Build Environment (`build.env`)

```bash
# Shared build variables
# UID/GID for vpopmail (must match across all packages)
VPOPMAIL_UID=89
VPOPMAIL_GID=89
VPOPMAIL_USER=vpopmail
VPOPMAIL_GROUP=vchkpw

# qmail users
QMAIL_GROUPS="nofiles qmail"
QMAIL_USERS="alias qmaild qmaill qmailp qmailq qmailr qmails"

# Install paths (match QMT conventions for compatibility)
QMAIL_HOME=/var/qmail
VPOPMAIL_HOME=/home/vpopmail

# Component versions (pinned)
NOTQMAIL_VERSION=1.08
VPOPMAIL_VERSION=5.4.33
UCSPI_TCP_VERSION=0.88
DAEMONTOOLS_VERSION=0.76
SPAMDYKE_VERSION=5.0.1
SIMSCAN_VERSION=1.4.2
QMAILADMIN_VERSION=1.2.16
VQADMIN_VERSION=2.3.7
EZMLM_IDX_VERSION=0.53
AUTORESPOND_VERSION=2.0.5
LIBSRS2_VERSION=1.0.18
RIPMIME_VERSION=1.4.0.10
MAILDROP_VERSION=3.4.4
LIBDOMAINKEYS_VERSION=0.69

# Build flags
CFLAGS_COMMON="-O2 -g -Wall"
CFLAGS_VPOPMAIL="-O2 -g -Wall -fcommon"  # GCC 10+ multiple-definition fix
```

### 6.3 Per-Component Build Approach

#### notqmail (DJB-style Makefile)
```bash
# Build: make it man
# Install: make setup check
# Config: ./config-fast $(hostname)
# Patches: EL10 compat (library paths), SysAdminHCP paths
```

#### vpopmail (autoconf)
```bash
# Critical configure flags:
./configure \
  --enable-auth-module=mysql \
  --enable-many-domains=y \
  --enable-incdir=$(MYSQL_INC_DIR) \
  --enable-libdir=$(MYSQL_LIB_DIR) \
  --enable-auth-logging=y \
  --enable-clear-passwd=y \
  --enable-logging=p
# CFLAGS="-fcommon"  # GCC 10+ fix
# Patches: MariaDB Connector/C compat, EL10 lib path detection
```

#### ucspi-tcp (DJB-style Makefile)
```bash
# Build: make
# Install: make setup check
# Patches: errno declaration fix
```

#### daemontools (DJB-style Makefile)
```bash
# Build: package/compile
# Install: package/install
# Patches: errno declaration fix
```

#### spamdyke (autoconf)
```bash
./configure --with-tls
make
# Patches: TLS cipher list fix for OpenSSL 3.x
```

#### simscan (autoconf)
```bash
./configure \
  --enable-clamav=y \
  --enable-spam=y \
  --enable-spam-hits=5 \
  --enable-ripmime=y \
  --enable-attach=y \
  --qmaildir=/var/qmail
make
```

#### qmailadmin (autoconf)
```bash
./configure \
  --enable-cgibindir=/var/www/cgi-bin \
  --enable-htmldir=/var/www/html/qmailadmin \
  --enable-vpopmaildir=/home/vpopmail \
  --enable-ezmlmdir=/usr/local/bin \
  --enable-autorespond=/usr/bin
make
```

#### vqadmin (autoconf)
```bash
./configure \
  --enable-cgibindir=/var/www/cgi-bin \
  --enable-htmldir=/var/www/html/vqadmin \
  --enable-vpopmaildir=/home/vpopmail
make
```

---

## 7. Packaging Strategy

### 7.1 RPM Packaging (AlmaLinux/RHEL)

Each component gets its own RPM spec file with:
- **Name**: `sysadminhcp-{component}` (not `qmail-toaster` or `vpopmail`)
- **Version**: Pinned from `build.env`
- **Requires**: Our own packages, not QMT's
- **%post**: Create users/groups, install config templates, fix permissions

#### Example: `sysadminhcp-vpopmail.spec` (key sections)

```spec
Name:    sysadminhcp-vpopmail
Version: 5.4.33
Release: 1%{?dist}
Summary: Virtual domain/mailbox management for qmail (SysAdminHCP build)
License: GPL
URL:     https://github.com/notqmail/vpopmail
Source0: vpopmail-%{version}.tar.gz
Patch0:  vpopmail-gcc14-fcommon.patch
Patch1:  vpopmail-mariadb-compat.patch

Requires: sysadminhcp-qmail
Requires: mariadb-connector-c
# NOT: mysql-libs or mysql-server (the QMT conflict source)

%prep
%setup -q -n vpopmail-%{version}
%patch0 -p1
%patch1 -p1

%build
export CFLAGS="-O2 -g -fcommon"
%configure \
  --enable-auth-module=mysql \
  --enable-many-domains=y \
  --enable-incdir=%{_includedir}/mysql \
  --enable-libdir=%{_libdir} \
  --enable-clear-passwd=y \
  --enable-logging=p
make %{?_smp_mflags}

%install
make install-strip DESTDIR=%{buildroot}

# Install our config (not upstream's)
install -d %{buildroot}/home/vpopmail/etc
install -m 600 config/vpopmail.mysql %{buildroot}/home/vpopmail/etc/

%files
/home/vpopmail/bin/*
/home/vpopmail/etc/
/home/vpopmail/lib/
%{_mandir}/man1/*

%post
# Create vpopmail user/group if not present
getent group vchkpw >/dev/null || groupadd -g 89 vchkpw
getent passwd vpopmail >/dev/null || useradd -u 89 -g 89 vpopmail -s /sbin/nologin
```

#### Meta-Package: `sysadminhcp-mail-meta.spec`

```spec
Name:    sysadminhcp-mail-meta
Summary: Meta-package: complete QmailToaster-compatible mail stack for SysAdminHCP
Requires: sysadminhcp-qmail
Requires: sysadminhcp-vpopmail
Requires: sysadminhcp-ucspi-tcp
Requires: sysadminhcp-daemontools
Requires: sysadminhcp-spamdyke
Requires: sysadminhcp-simscan
Requires: sysadminhcp-qmailadmin
Requires: sysadminhcp-vqadmin
Requires: sysadminhcp-ezmlm
Requires: sysadminhcp-autorespond
Requires: sysadminhcp-libsrs2
Requires: sysadminhcp-ripmime
Requires: dovecot
Requires: dovecot-mysql
Requires: spamassassin
Requires: clamav
Requires: clamd
# NO Requires: mysql-libs or mysql-server
```

### 7.2 Debian Packaging (Ubuntu/Debian)

Use `dpkg-buildpackage` with standard `debian/rules` per component. The Ubuntu install script already builds from source — packaging as .deb formalizes this.

### 7.3 Source-Install Fallback

For systems where neither RPM nor .deb is available (or for development), `scripts/install-from-source.sh` builds and installs directly, mirroring the existing `install-ubuntu22.sh` approach.

---

## 8. Integration with SysAdminHCP

### 8.1 Install Script Changes

#### `install-almalinux{8,9,10}.sh` — Replace QMT RPM deps with our packages

**Before** (current):
```bash
# Install QMT repo from whitehorsetc.com
curl -L -o qmt-release-1-8.qt.el9.noarch.rpm http://repo.whitehorsetc.com/...
rpm -ivh qmt-release-1-8.qt.el9.noarch.rpm
dnf install -y daemontools ucspi-tcp spamdyke ...
dnf download --enablerepo=qmt-testing vpopmail qmail ezmlm simscan ...
rpm -ivh --nodeps vpopmail-*.rpm qmail-*.rpm ...
wget -P /etc/dovecot https://raw.githubusercontent.com/qmtoaster/scripts/master/dovecot.conf
```

**After** (proposed):
```bash
# Install our self-built mail stack RPMs (shipped in the repo, no external fetch)
MAIL_RPM_DIR="$REPO_DIR/mail-stack/rpms/el${EL_VERSION}"
dnf install -y $MAIL_RPM_DIR/sysadminhcp-*.rpm
# OR: install from source
# bash $REPO_DIR/mail-stack/scripts/install-from-source.sh
```

No more:
- `curl` to `repo.whitehorsetc.com`
- `rpm -ivh --nodeps`
- `wget` from `github.com/qmtoaster`
- Patching broken RPM scripts at install time

#### `install-qmail-toaster.sh` — Replace with our installer

The standalone `install-qmail-toaster.sh` script (called via sudo from the panel) will be replaced with a version that installs from our local RPMs or builds from source.

### 8.2 Config Template Changes

All config files currently downloaded or generated at install time will be **shipped in `mail-stack/config/`** and installed by the RPM/post-install scripts:

| Config File | Current Source | New Source |
|-------------|---------------|------------|
| `/etc/dovecot/dovecot.conf` | QMT GitHub | `mail-stack/config/dovecot/dovecot.conf` |
| `/etc/dovecot/dovecot-sql.conf.ext` | Generated by install script | `mail-stack/config/dovecot/dovecot-sql.conf.ext` |
| `/var/qmail/supervise/smtp/run` | QMT RPM (broken, patched at install) | `mail-stack/config/qmail/supervise/smtp/run` (fixed) |
| `/var/qmail/supervise/submission/run` | QMT RPM | `mail-stack/config/qmail/supervise/submission/run` |
| `/etc/spamdyke/spamdyke.conf` | Generated by install script | `mail-stack/config/spamdyke/spamdyke.conf` |
| `/etc/spamdyke/spamdyke-submission.conf` | Generated by install script | `mail-stack/config/spamdyke/spamdyke-submission.conf` |
| `/etc/tcprules.d/tcp.smtp` | QMT RPM | `mail-stack/config/qmail/tcprules/tcp.smtp` |
| systemd units | Generated by install script | `mail-stack/config/systemd/*.service` |

### 8.3 Panel Code Changes

`mailService.ts` and other panel files **should not need changes** — they call `/home/vpopmail/bin/` tools and manage configs at the same paths. The key principle is **binary compatibility**: our self-built packages install to the same paths as QMT RPMs.

### 8.4 Sudoers Changes

The sudoers file grants access to `install-qmail-toaster.sh`. This script will be updated to call our local installer instead of fetching external RPMs.

---

## 9. AlmaLinux 10 Specific Challenges

### 9.1 `libmysqlclient.so.24` → MariaDB Connector/C

**Problem**: Prebuilt QMT vpopmail RPMs link against `libmysqlclient.so.24`, which doesn't exist on EL10 (only `libmariadb.so.3`).

**Solution**: Build vpopmail from source against MariaDB Connector/C:
```bash
# EL10: MariaDB Connector/C provides mysql.h compatibility shim
dnf install -y mariadb-connector-c-devel
./configure \
  --enable-auth-module=mysql \
  --enable-incdir=/usr/include/mysql \
  --enable-libdir=%{_libdir}  # libmariadb.so lives here
```

The `--enable-incdir` points to the MariaDB header location (which provides `mysql.h`), and the linker finds `libmariadb.so` instead of `libmysqlclient.so`.

### 9.2 GCC 14 Compatibility

**Problem**: vpopmail's old codebase has tentative-definition globals that GCC 10+ rejects with `-fno-common`.

**Solution**: Apply `-fcommon` in CFLAGS (already done in Ubuntu script, needs to be in RPM spec too).

### 9.3 OpenSSL 3.x

**Problem**: spamdyke's TLS cipher list uses TLS 1.3 ciphersuite names with the legacy `SSL_CTX_set_cipher_list()` API.

**Solution**: Patch spamdyke to use `SSL_CTX_set_ciphersuites()` for TLS 1.3, or ship a config with only TLS 1.2 ciphersuites (already done in install scripts).

### 9.4 `chkconfig` Removed

**Problem**: EL10 removes `chkconfig` — service management is systemd-only.

**Solution**: Ship systemd units directly (already done in `install-almalinux10.sh`). Our RPMs' `%post` scripts use `systemctl` only.

### 9.5 `yum` Removed

**Problem**: EL10 has `dnf` only, no `yum` wrapper.

**Solution**: All scripts use `dnf` (already done in `install-almalinux10.sh`).

### 9.6 Daemontools vs Systemd

**Problem**: QMT uses daemontools (`svscan`) for process supervision. EL10 prefers systemd.

**Solution**: Support both:
- **EL8/9**: daemontools `svscan` wrapped as `qmail.service` (current approach)
- **EL10**: Direct systemd units (`qmail-send.service`, `qmail-smtp.service`, `qmail-submission.service`) — no daemontools needed (already done in `install-almalinux10.sh`)

Our RPMs will include both sets of unit files and select based on OS detection.

---

## 10. Migration & Upgrade Path

### 10.1 Fresh Install

New SysAdminHCP installations will use the self-built mail stack exclusively. No external RPM repos are needed.

### 10.2 Upgrade from Existing QMT RPMs

For servers already running QMT RPMs:

```bash
# 1. Install our packages (they overwrite QMT binaries at same paths)
dnf install -y sysadminhcp-mail-meta-*.rpm

# 2. Restart services
systemctl restart qmail-send qmail-smtp qmail-submission dovecot

# 3. Remove QMT repo
rm -f /etc/yum.repos.d/qmt-*.repo
dnf clean all
```

Since our packages install to the same paths (`/var/qmail/`, `/home/vpopmail/`), the upgrade is transparent — configs, Maildirs, and MySQL data are preserved.

### 10.3 Version Pinning

All component versions are pinned in `build.env`. Upgrades require:
1. Update version in `build.env`
2. Update the git submodule to the new tag
3. Rebuild RPMs/debs
4. Test in CI
5. Ship new packages

---

## 11. Testing Strategy

### 11.1 CI Pipeline (GitHub Actions / Docker)

Build RPMs in Docker containers matching each target OS:

```yaml
# ci/github-actions/build-rpms-el10.yml
jobs:
  build-el10:
    runs-on: ubuntu-latest
    container: almalinux:10
    steps:
      - checkout
      - install build deps (gcc, make, rpmbuild, mariadb-connector-c-devel)
      - run: make rpms
      - upload RPMs as artifacts
```

### 11.2 Integration Tests

After building, spin up a container with the installed mail stack and verify:

| Test | Verification |
|------|-------------|
| qmail-smtpd listens on port 25 | `ss -tlnp \| grep :25` |
| qmail-send process running | `pgrep -x qmail-send` |
| vpopmail `vadddomain` works | `vadddomain test.com password` |
| vpopmail `vadduser` works | `vadduser user@test.com password` |
| Dovecot IMAP login | `doveadm auth test user@test.com password` |
| SMTP AUTH works | `swaks --auth --to user@test.com` |
| spamdyke filtering | Send test mail, check spamdyke log |
| simscan scanning | Send EICAR test, check rejection |
| qmailadmin CGI | `curl http://localhost/cgi-bin/qmailadmin` |
| vqadmin CGI | `curl http://localhost/cgi-bin/vqadmin` |
| Mail delivery | Send mail, check Maildir |
| Maildir format | `ls /home/vpopmail/domains/test.com/user/Maildir/` |

### 11.3 Compatibility Tests

Verify that the panel (`mailService.ts`) can:
- List mail domains (`vdominfo`)
- Create/delete domains (`vadddomain`/`vdeldomain`)
- Create/delete users (`vadduser`/`vdeluser`)
- Change passwords (`vpasswd`)
- Set quotas (`vsetuserquota`)
- Check queue status
- Restart services

---

## 12. Implementation Phases

### Phase 1: Foundation (Weeks 1-2)
- [ ] Create `mail-stack/` directory structure
- [ ] Add git submodules for all upstream sources
- [ ] Write `build.env` with pinned versions
- [ ] Write `Makefile` orchestrator
- [ ] Create `patches/` directory with known patches (errno, fcommon, TLS)
- [ ] Build ucspi-tcp + daemontools from source (no deps)
- [ ] Build notqmail from source
- [ ] Verify: qmail starts, basic SMTP works

### Phase 2: Core Mail Stack (Weeks 3-4)
- [ ] Build vpopmail from source (with MariaDB compat patches)
- [ ] Build spamdyke from source (with TLS fix)
- [ ] Build autorespond from source
- [ ] Build ezmlm-idx from source
- [ ] Create all config templates in `config/`
- [ ] Write `install-from-source.sh`
- [ ] Verify: vadddomain, vadduser, SMTP AUTH, IMAP login, mail delivery

### Phase 3: RPM Packaging (Weeks 5-6)
- [ ] Write RPM spec files for all components
- [ ] Set up Docker build containers (EL8, EL9, EL10)
- [ ] Build RPMs in CI
- [ ] Write `install-from-rpms.sh`
- [ ] Verify: fresh install from RPMs on clean EL9 and EL10 containers
- [ ] Verify: upgrade from QMT RPMs to our RPMs

### Phase 4: Web Admin & Scanning (Weeks 7-8)
- [ ] Build simscan from source
- [ ] Build qmailadmin from source
- [ ] Build vqadmin from source
- [ ] Build ripmime from source
- [ ] Build libsrs2 from source
- [ ] Verify: simscan + ClamAV + SpamAssassin scanning
- [ ] Verify: qmailadmin and vqadmin CGI work

### Phase 5: Integration & Polish (Weeks 9-10)
- [ ] Update `install-almalinux{8,9,10}.sh` to use our packages
- [ ] Update `install-qmail-toaster.sh` to use our packages
- [ ] Update `install-ubuntu22.sh` to use our build system
- [ ] Add Debian packaging (.deb)
- [ ] Full end-to-end testing on all target OSes
- [ ] Documentation: build guide, install guide, architecture docs

### Phase 6: CI/CD & Release (Weeks 11-12)
- [ ] GitHub Actions pipeline for automated RPM/.deb builds
- [ ] Automated integration tests in CI
- [ ] Release artifacts published to GitHub Releases
- [ ] Remove all external repo dependencies from install scripts
- [ ] Final verification: clean install with zero external dependencies

---

## 13. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| vpopmail source doesn't compile on EL10 (MariaDB compat) | Medium | High | Patch + test early in Phase 2; fallback to SourceForge 5.4.33 with patches |
| notqmail 1.08 has breaking changes vs QMT qmail | Low | Medium | notqmail maintains `/var/qmail` layout; test config-fast, qmail-start |
| spamdyke TLS patch is complex | Medium | Medium | Ship TLS 1.2-only cipher config as fallback (already done) |
| qmailadmin/vqadmin CGI needs specific web server config | Low | Low | Ship Apache/Nginx config templates; panel already manages webmail |
| simscan ClamAV API changes on EL10 | Medium | Medium | Patch for ClamAV 1.x API; test with EICAR |
| ezmlm-idx MySQL variant build complexity | Low | Low | Build non-MySQL variant first; add MySQL variant later |
| Git submodules add complexity to deployment | Low | Low | Vendor tarballs as fallback; `git submodule update --init` in build script |
| RPM signing (GPG) needed for production | Medium | Low | Generate SysAdminHCP GPG key; sign all RPMs; ship public key |
| Package naming conflicts with QMT RPMs on upgrade | Low | Medium | Use `sysadminhcp-` prefix; handle upgrade in `%post` |
| qmailmrtg/isoqlog abandoned, no source | Medium | Low | Fork last known source into our repo; or replace with modern alternatives |

---

## Appendix A: Upstream Source URLs

| Component | URL | Version |
|-----------|-----|---------|
| notqmail | `https://github.com/notqmail/notqmail` | 1.08 |
| vpopmail | `https://github.com/notqmail/vpopmail` | 5.4.x |
| ucspi-tcp | `https://github.com/notqmail/ucspi-tcp` | 0.88 |
| daemontools | `https://github.com/notqmail/daemontools` | 0.76 |
| simscan | `https://github.com/notqmail/simscan` | 1.4.x |
| qmailadmin | `https://github.com/notqmail/qmailadmin` | 1.2.x |
| vqadmin | `https://github.com/notqmail/vqadmin` | 2.3.x |
| ezmlm-idx | `https://github.com/notqmail/ezmlm-idx` | 0.53x |
| autorespond | `https://github.com/notqmail/autorespond` | 2.0.x |
| spamdyke | `https://github.com/spamdyke/spamdyke` | 5.0.1 |
| libsrs2 | `https://github.com/libsrs2/libsrs2` | 1.0.x |
| ripmime | `https://github.com/wettenhaller/ripMIME` | 1.4.x |
| maildrop | `https://github.com/courier/maildrop` | 3.x |
| libdomainkeys | `https://sourceforge.net/projects/domainkeys/` | 0.69 |

## Appendix B: Current External Dependencies to Eliminate

| External Source | What It Provides | Replacement |
|----------------|------------------|-------------|
| `http://repo.whitehorsetc.com/{8,9,10}/testing/x86_64/` | All QMT RPMs | Our self-built RPMs |
| `qmt-release-*.noarch.rpm` | QMT repo registration | Not needed |
| `raw.githubusercontent.com/qmtoaster/scripts/master/` | Dovecot config | Our `config/dovecot/` |
| `download.copr.fedorainfracloud.org/results/kloxong/kloxo-qmail/` | Legacy KloxoNG QMT RPMs | Our self-built RPMs |
| `sourceforge.net/projects/vpopmail/` | vpopmail source tarball | Git submodule |
| `www.spamdyke.org/releases/` | spamdyke tarball | Git submodule |

## Appendix C: File Paths (Binary Compatibility)

All self-built packages must install to the same paths as QMT RPMs for panel compatibility:

| Path | Component | Notes |
|------|-----------|-------|
| `/var/qmail/bin/` | notqmail | qmail-send, qmail-smtpd, qmail-queue, etc. |
| `/var/qmail/control/` | notqmail | Config files |
| `/var/qmail/supervise/` | daemontools | supervise scripts (EL8/9) |
| `/var/qmail/rc` | notqmail | qmail-start wrapper |
| `/home/vpopmail/bin/` | vpopmail | vadddomain, vadduser, vpasswd, vchkpw, etc. |
| `/home/vpopmail/domains/` | vpopmail | Maildir storage |
| `/home/vpopmail/etc/` | vpopmail | vpopmail.mysql config |
| `/usr/bin/spamdyke` or `/usr/local/bin/spamdyke` | spamdyke | SMTP filter |
| `/etc/spamdyke/` | spamdyke | Config files |
| `/etc/tcprules.d/` | ucspi-tcp | tcp.smtp and tcp.smtp.cdb |
| `/usr/bin/tcpserver` | ucspi-tcp | inetd replacement |
| `/usr/bin/softlimit` | daemontools | Memory limit wrapper |
| `/usr/bin/svc` | daemontools | Service control |
| `/var/www/cgi-bin/qmailadmin` | qmailadmin | CGI binary |
| `/var/www/cgi-bin/vqadmin/` | vqadmin | CGI binary |
| `/usr/bin/autorespond` | autorespond | Autoresponder binary |
| `/usr/local/bin/ezmlm-*` | ezmlm-idx | Mailing list tools |
| `/usr/bin/ripmime` | ripmime | MIME extraction |
| `/usr/sbin/sendmail` → `/var/qmail/bin/sendmail` | notqmail | Sendmail compat symlink |