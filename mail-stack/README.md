# SysAdminHCP mail-stack

Self-hosted build system for the QmailToaster-compatible mail stack (qmail + vpopmail +
spamdyke + friends) on AlmaLinux 10. **As of 2026-08-02, `install-almalinux10.sh` has zero
runtime dependency on QmailToaster's own repo (`repo.whitehorsetc.com`) or GitHub
(`github.com/qmtoaster`)** — every one of the 14 real components is either built from source
here or, where genuinely appropriate, a normal AlmaLinux AppStream/CRB package.

Full background, component inventory, dependency graph, and the original (broader) proposal
this was scoped down from: `QMAILTOASTER-SELF-HOST-PLAN.md` in this same directory.

## Current status — all 14 components live-verified, 2026-08-02

| Component | Source | Real functional test |
|---|---|---|
| `notqmail`, `vpopmail` | Real upstream (GitHub/SourceForge) | `vadddomain`/`vadduser`/`vpasswd`/`vdeluser`, real network SMTP, real IMAP login |
| `ucspi-tcp`, `daemontools`, `libsrs2`, `ripmime` | Vendored from QMT's EL10 SRPM (no independent mirror) | Real network SMTP round-trip through the source-built `tcpserver`/`softlimit` |
| `autorespond`, `ezmlm-idx`, `spamdyke` | Vendored from QMT's EL10 SRPM | Real ezmlm mailing list delivery, real queued auto-reply, real SMTP through rebuilt spamdyke |
| `simscan` (+ vendored legacy PCRE1) | Vendored from QMT's EL10 SRPM; PCRE1 from its own real pcre.org/SourceForge upstream | Real EICAR string rejected by simscan+ClamAV (exit 82, `Eicar-Signature FOUND`) |
| `qmailadmin`, `vqadmin` | Vendored from QMT's EL10 SRPM | Real POST-based logins against the live vpopmail MySQL tables, linked against `libmariadb.so.3` |
| `maildrop` (+ vendored courier-unicode) | Vendored from QMT's EL10 SRPM; courier-unicode from its own real courier-mta.org/SourceForge upstream | Real message piped through `maildrop -d`, landed in `/var/mail` |
| `qmailmrtg`, `isoqlog` | Vendored from QMT's EL10 SRPM (no independent mirror) | Real output against the live `/var/qmail/queue` and `/var/log/qmail/send` |
| `control-panel` | Vendored from QMT's EL10 SRPM (plain PHP, QMT's own code, no upstream) | Real HTTP 200 with rendered admin page, real htpasswd auth |
| RPM/Debian packaging, CI/CD, GPG signing | — | Explicitly out of scope — direct source-install achieves the same independence goal with far less overhead; see `QMAILTOASTER-SELF-HOST-PLAN.md`'s original Phase 3/6 if ever revisited |

## The hallucinated-URL lesson

The original scaffolding (ported from a Copilot-authored plan) assumed every component had
a real GitHub mirror (`github.com/notqmail/<name>`). **Checked live: every single one of
those URLs except `notqmail` and `vpopmail`'s own was a fabricated 404** — never actually
tested before being written into the Makefiles. The fix: for every component without a
verified real upstream, pull the exact source QMT compiles their own (already-working)
prebuilt RPMs from — their EL10 `SRPMS/` repo — **once**, and vendor it permanently into
`vendor/`. No more `repo.whitehorsetc.com` dependency after that, regardless of what
happens to their repo in the future. See `vendor/README.md`. Two components' own real
dependencies (legacy PCRE1 for simscan, courier-unicode for maildrop) turned out to have the
exact same problem one level down — same fix, vendored from their own real upstream.

## Layout

```
mail-stack/
├── build.env              # Pinned versions, UID/GID, CFLAGS, MySQL header/lib detection
├── Makefile                # Top-level orchestrator (`make sources`, `make <component>`)
├── build/<component>/      # One Makefile per component — extracts, patches, configures,
│                            #   builds, installs directly to its real runtime path
├── vendor/<component>/     # One-time-forked source + QMT's own real patches for every
│                            #   component with no independent upstream mirror — see
│                            #   vendor/README.md for why and how
├── patches/                # Notes on which QMAILTOASTER-SELF-HOST-PLAN.md "patches" turned
│                            #   out to be real vs. just a configure flag
├── config/                 # Config templates we ship ourselves (qmail supervise scripts,
│                            #   spamdyke.conf, Dovecot SQL auth, systemd units)
├── scripts/
│   └── install-from-source.sh   # Orchestrates build.env + Makefile + config/ end-to-end —
│                                 #   NOT itself live-verified, see its own header comment
└── sources/                # (empty — tarballs are fetched to /tmp and deleted after each
                              #   build, or copied from vendor/, never committed here)
```

## How the pieces fit together

1. `build.env` is `include`'d directly by every Makefile — **no shell-style quotes** in its
   values (Make doesn't strip them). `CFLAGS_COMMON` carries the GCC 14 compatibility flags
   (`-Wno-error=implicit-function-declaration` etc.) applied to every component up front,
   since this class of error hit notqmail, vpopmail, ucspi-tcp, daemontools, ripmime,
   simscan's vendored cdb, and more — all independently.
2. `make sources` (or `make <component>` for just one) walks `COMPONENTS` in the top-level
   Makefile in dependency order and runs `make -C build/<component>`.
3. Each `build/<component>/Makefile` targets a real sentinel file (e.g.
   `/home/vpopmail/bin/vadddomain` for vpopmail) — re-running `make` is a no-op if that file
   already exists. **Watch for false idempotency**: a target gated behind a sentinel that's
   satisfied by an *earlier, unrelated* build step (e.g. vpopmail already being built) will
   skip a recipe that does something else too (e.g. the `/etc/libvpopmail` compat symlink) —
   confirmed live, fixed by splitting into a separate target with its own sentinel. Don't
   bundle "should always run" steps into a target gated by someone else's completion check.
4. `install-almalinux10.sh` calls into these Makefiles directly (`make -C
   "$MAIL_STACK_DIR/build/$comp" build`) rather than re-inlining the same logic — the
   ordering there matters: any component depending on `qmail-smtpd` or vpopmail (most of
   them) must be called *after* the notqmail/vpopmail build block, not before. Confirmed
   live: an earlier version of the wiring put them before it and only worked because the
   test box was never actually starting from scratch between runs.

## Why vpopmail (and qmailadmin/vqadmin/ezmlm-idx) need a real MySQL rebuild, not a shim

A `dlopen`-forwarding shim that redirects a prebuilt-RPM binary's MySQL calls to MariaDB's
library at runtime *loads* successfully, but the RPM was *compiled* against real MySQL
client struct layouts. The moment a call touches a struct MariaDB lays out differently, it
segfaults — confirmed live early in this effort (`vadduser` got past its domain-existence
check, then crashed on the next real query). A genuine source rebuild against MariaDB's
actual headers avoids this because the compiler uses one consistent ABI throughout, not two
mixed ones. All four MySQL-linked components here (`vpopmail`, `qmailadmin`, `vqadmin`,
`ezmlm-idx`) link against `libmariadb.so.3` directly via `mariadb-connector-c-devel`'s own
official `libmysqlclient.so` compatibility symlink — the real vendor-supported mechanism,
not a hand-rolled shim, so no ABI mismatch.

Note: AlmaLinux 10's own AppStream repo separately ships `mysql8.4-libs` (the real Oracle
MySQL 8.4 client), which also worked when qmailadmin/vqadmin briefly used it as a one-line
fix before being migrated to full source builds — genuinely ABI-compatible, just an extra
dependency once source-building anyway. Never tested against the *prebuilt* vpopmail RPM
directly; the source-built version was already live and not worth risking to test an
alternative.

## Real bugs found during this effort (not exhaustive — see git log / project memory)

- GCC 14 promotes `-Wimplicit-function-declaration`/`-Wincompatible-pointer-types` to errors
  by default — hit notqmail, vpopmail's vendored cdb, ucspi-tcp, daemontools, ripmime, and
  simscan's vendored cdb independently. Fixed once via `build.env`'s `CFLAGS_COMMON`.
- vpopmail's `cdb/conf-cc` patch must run *after* `./configure`, not before — configure
  regenerates that file itself near the end of its own run, silently discarding an earlier
  edit.
- `-lnsl` doesn't exist on AlmaLinux 10 (folded into glibc) — ezmlm-idx's real spec still
  references it; drop it from the link line.
- `make install-strip` (the real spec's own install step) must be used instead of manually
  `cp`-ing built files afterward — qmailadmin's compiled-in template paths expect the exact
  directory structure `make install` produces (an `html/` subdirectory), which a flattened
  manual copy breaks.
- `/etc/libvpopmail` (and `$vpopmaildir/{lib,inc}_deps`) are QMT's own devel-package
  packaging convention for files vpopmail's stock `Makefile.in` already writes to
  `$vpopmaildir/etc/` — satisfied with a compatibility symlink instead of a separate
  package, but must be checked on every run, not gated behind vpopmail's own build-skip
  logic (see "false idempotency" above).
- `build.env` had two stale version numbers (`SIMSCAN_VERSION=1.4.2`, `MAILDROP_VERSION=
  3.4.4`) that didn't match the real vendored tarballs (`1.4.0`, `3.1.8`) — carried over
  from the original, never-tested Copilot research.

## Next steps (not yet done)

1. Port the vpopmail database/user/`vpopmail.mysql` config creation step into
   `scripts/install-from-source.sh` (currently only in `install-almalinux10.sh`) if this
   script is ever meant to be a real standalone install path.
2. `libdomainkeys` remains explicitly out of scope (DKIM already covers this — see
   `build/libdomainkeys/NOT-IN-SCOPE.md`).
3. RPM/Debian packaging, CI/CD — deprioritized per explicit direction; direct source-install
   already achieves full independence.
