# Vendored source — one-time fork, no more live QMT dependency

Every Copilot-authored `build/<component>/Makefile` that fetched from a "real upstream"
GitHub URL was checked live on 2026-08-02 and found to be **entirely fabricated** — every
single one of those URLs (`github.com/notqmail/ucspi-tcp`, `.../daemontools`, `.../simscan`,
etc.) returns 404. Only `notqmail` and `vpopmail`'s own URLs turned out to be real (already
live-verified separately — see `build/notqmail/` and `build/vpopmail/`).

None of these 12 remaining components have a stable, independent upstream we can fetch from
at build time. What they DO have: a real, working source RPM on QmailToaster's own EL10
`SRPMS/` repo (`repo.whitehorsetc.com/10/testing/SRPMS/`) — the exact source QMT compiles
their own (currently-working) prebuilt RPMs from, patches included.

**This directory is a one-time fork of that source** — the tarball + QMT's own patches,
extracted from each `.src.rpm` and committed here permanently. Every `build/<component>/
Makefile` builds from these vendored files, never from `repo.whitehorsetc.com` — that
dependency is fully eliminated once vendored, regardless of what happens to QMT's repo in
the future.

## Why keep QMT's patches instead of writing our own

Every component here shipped a real, working `*-el9-to-el10.patch` (or equivalent) that QMT
already engineered and QA'd against this exact OS combination — visible proof of this: the
prebuilt RPMs built from these exact patches are the ones that were already running
successfully on this box before today's rebuild. Re-deriving these fixes from scratch (the
way `notqmail`/`vpopmail` needed to, since **no** patch existed for those two anywhere) would
be redundant, slower, and riskier than reusing already-proven work. `build.env`'s
`CFLAGS_COMMON` GCC 14 flags are still applied on top of these patches as a second layer,
since QMT's patches mostly targeted GCC 11 (EL9)/RHEL 8, not GCC 14 specifically.

## Layout

Each `vendor/<component>/` contains the real upstream tarball (unmodified) plus QMT's own
`.patch` files, exactly as extracted from the `.src.rpm`. `vendor/<component>/*.spec` is NOT
vendored (RPM-specific, not needed for a direct build) — the real `%prep`/`%build`/`%install`
recipe from each spec was read once during this work and ported into the matching
`build/<component>/Makefile` as plain shell, the same way `install-almalinux10.sh` already
does for every other component.

## Provenance / licensing

All of these are long-standing open-source projects (public domain DJB tools, BSD/GPL
licensed utilities) that QmailToaster itself redistributes under an open EL10 testing repo —
vendoring the exact same source + patches they already ship is not materially different from
what any Linux distribution's own package maintainers do when they fork upstream + patches
into their own spec-controlled source tree.
