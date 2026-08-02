# Patches — status

Real source-code patches (unified diffs applied to upstream source), as distinct from build
flags/configure options (which live in each component's `build/<name>/Makefile` instead).
Don't confuse the two — most of what QMAILTOASTER-SELF-HOST-PLAN.md's original inventory
called "patches" turned out, once we actually built vpopmail today, to be **configure flags
and `CFLAGS`**, not real source patches. Keep that distinction honest here as each component
gets built for the first time — a "patch" entry that's really just a `./configure` flag
belongs in `build.env`/the component's Makefile, not here.

## Verified — no source patch needed

- **vpopmail**: `-fcommon` (`build.env`'s `CFLAGS_VPOPMAIL`) plus `--enable-incdir`/
  `--enable-libdir` pointed at MariaDB Connector/C's real paths is sufficient. Confirmed
  live on `install-ubuntu22.sh` (working) and `install-almalinux10.sh` (staged, not yet
  live-verified — see project memory). No unified diff required.
- **notqmail**: builds and installs via its own `make setup check` + `./config-fast` with no
  patching, on both Ubuntu and (staged) AlmaLinux 10.

## Unverified — carried over from the original analysis, not yet build-tested

These were listed as needed in QMAILTOASTER-SELF-HOST-PLAN.md but we have not yet actually
built any of these components ourselves to confirm. Treat every claim below as a hypothesis
to verify, not a known fact, the first time each component's `build/<name>/Makefile` runs
for real:

- **ucspi-tcp** `01-errno.patch` — claimed `errno` declaration fix for modern glibc headers
  (old DJB-era code sometimes declares `errno` itself instead of including `<errno.h>`,
  which newer glibc rejects). Not confirmed needed on any OS we've actually built this on.
- **daemontools** `01-errno.patch` — same claim, same caveat.
- **spamdyke** `01-tls-cipher-fix.patch` — **this one we've actually confirmed as a real,
  independently-verified problem** (not via a source patch, though): `install-almalinux10.sh`
  already works around it today by rewriting `spamdyke.conf`'s `tls-cipher-list` after
  install, because spamdyke's default cipher list uses TLS 1.3 suite names with OpenSSL's
  legacy `SSL_CTX_set_cipher_list()` API, which OpenSSL 3.2+ rejects outright. If spamdyke is
  ever source-built here instead of RPM-installed, prefer porting that config-level fix
  (already working) over guessing at a source patch to the TLS setup code itself.
- **simscan** `01-el10-clamav.patch` — claimed ClamAV API changes needed for EL10's ClamAV.
  Not confirmed; simscan is still RPM-installed today (see `install-almalinux10.sh`), not
  source-built, so this has never actually been exercised.

## How to use this directory once a component needs a real patch

`patches/<component>/NN-description.patch`, applied via `patch -p1 < ../../patches/<component>/*.patch`
from the extracted source directory (see `build/vpopmail/Makefile`'s comment for the intended
convention once a component actually needs one — none currently do).
