# vpopmail — virtual domain/mailbox management, the component that actually needed fixing.
#
# Root cause (confirmed live on a real AlmaLinux 10 box): prebuilt QmailToaster vpopmail RPMs
# link against libmysqlclient.so.24, which doesn't exist on AlmaLinux 10 or modern
# Ubuntu/Debian — only MariaDB Connector/C (libmariadb.so.3) is available. This breaks every
# vpopmail CLI tool (vadduser/vpasswd/vadddomain/vdeluser) the panel depends on.
#
# The fix is a real source build against MariaDB's real headers/structs — NOT a same-name
# symlink to libmariadb.so (fails on ELF symbol versioning) and NOT a dlopen-forwarding shim
# (compiles clean but the RPM's binary was compiled against real MySQL client structs, and a
# shim forwarding into MariaDB's differently-laid-out structs segfaults past the first simple
# call — confirmed live: vadduser worked up to its domain-existence check, then segfaulted on
# the next real query). A genuine source rebuild avoids this because the compiler uses
# MariaDB's actual struct layouts throughout, not a mix of two ABIs.
#
# Logic ported directly from sysadminhcp/deploy/install-almalinux10.sh (LIVE-VERIFIED on a
# real AlmaLinux 10 box, 2026-08-02 — vadddomain/vadduser/vpasswd/vdeluser, real SMTP
# delivery, and real IMAP login all confirmed working) and sysadminhcp/deploy/install-ubuntu22.sh
# (live-verified working on real Ubuntu boxes) — keep those three copies in sync if this
# build logic changes; don't let them drift.
#
# No source patch needed to vpopmail's own top-level code — see patches/README.md. Only
# CFLAGS + configure flags, PLUS one real fix found during live verification: vpopmail
# vendors its OWN copy of the DJB cdb library (cdb/cdb_seek.c — the exact same file/issue as
# notqmail's seek_*.c), built via its own internal conf-cc that does NOT respect the outer
# CFLAGS below. Without patching cdb/conf-cc too, cdb_seek.o fails with the same GCC 14
# implicit-function-declaration/incompatible-pointer-types errors as notqmail did.
#
# ORDERING MATTERS: cdb/conf-cc must be patched AFTER ./configure runs, not before — the
# file doesn't even exist in the raw tarball; ./configure's own generated script writes it
# fresh (`echo "${CC} -O2" > cdb/conf-cc`) as one of its last steps. An earlier version of
# this fix patched it before configure and silently got overwritten — confirmed live: the
# full install script reported success (all core services running) while vadddomain/vadduser
# didn't exist at all, because vpopmail's build had actually failed with the exact same error
# this fix is supposed to prevent. Always re-verify with a REAL vadduser call after any
# change here, not just a "did the script exit 0" check.

include ../../build.env

TARBALL := vpopmail-$(VPOPMAIL_VERSION).tar.gz
SRCDIR  := vpopmail-$(VPOPMAIL_VERSION)
URL     := https://sourceforge.net/projects/vpopmail/files/vpopmail-stable/$(VPOPMAIL_VERSION)/$(TARBALL)/download

.PHONY: build clean

# Split into two independent targets rather than one — /etc/libvpopmail must be checked
# every run, not just when vpopmail itself needs a fresh build. Confirmed live 2026-08-02:
# with a single combined target, Make's own idempotency check on $(VPOPMAIL_HOME)/bin/
# vadddomain (already present from an earlier run) skipped the ENTIRE recipe, including the
# symlink-creation lines, leaving qmailadmin/vqadmin's builds unable to find
# /etc/libvpopmail/lib_deps even though vpopmail itself was perfectly fine.
build: $(VPOPMAIL_HOME)/bin/vadddomain /etc/libvpopmail

$(VPOPMAIL_HOME)/bin/vadddomain: /var/qmail/bin/qmail-smtpd
	@echo "Building vpopmail $(VPOPMAIL_VERSION) from source (MySQL auth via MariaDB Connector/C)..."
	getent group $(VPOPMAIL_GROUP) >/dev/null || groupadd -g $(VPOPMAIL_GID) $(VPOPMAIL_GROUP)
	getent passwd $(VPOPMAIL_USER) >/dev/null || useradd -u $(VPOPMAIL_UID) -g $(VPOPMAIL_GID) $(VPOPMAIL_USER) -s /sbin/nologin -d $(VPOPMAIL_HOME)
	mkdir -p $(VPOPMAIL_HOME) && chown $(VPOPMAIL_USER):$(VPOPMAIL_GROUP) $(VPOPMAIL_HOME) && chmod 755 $(VPOPMAIL_HOME)
	cd /tmp && rm -rf $(SRCDIR) && curl -fsSL -o $(TARBALL) "$(URL)"
	cd /tmp && tar xzf $(TARBALL)
	@# Detect the real MariaDB Connector/C header location — this is the actual fix, not a
	@# hardcoded per-OS path. See build.env's MYSQL_INC_CANDIDATES.
	MYSQL_INC=""; \
	for d in $(MYSQL_INC_CANDIDATES); do [ -d "$$d" ] && MYSQL_INC="$$d" && break; done; \
	if [ -z "$$MYSQL_INC" ]; then echo "ERROR: no MariaDB/MySQL client headers found — install mariadb-connector-c-devel (RHEL) or libmariadb-dev-compat (Debian/Ubuntu) first"; exit 1; fi; \
	MYSQL_LIB=""; \
	for d in $(MYSQL_LIB_CANDIDATES); do [ -d "$$d" ] && MYSQL_LIB="$$d" && break; done; \
	cd /tmp/$(SRCDIR) && \
	CFLAGS="$(CFLAGS_VPOPMAIL)" ./configure \
	  --enable-auth-module=mysql \
	  --enable-many-domains=y \
	  --enable-incdir="$$MYSQL_INC" \
	  --enable-libdir="$$MYSQL_LIB" \
	  --enable-auth-logging=y \
	  --enable-clear-passwd=y \
	  --enable-logging=p
	@# MUST run after ./configure — see header comment for why.
	if [ -f /tmp/$(SRCDIR)/cdb/conf-cc ]; then \
	  echo "gcc -O2 -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion" > /tmp/$(SRCDIR)/cdb/conf-cc; \
	fi
	cd /tmp/$(SRCDIR) && make -j$$(nproc)
	cd /tmp/$(SRCDIR) && make install-strip
	@test -x $(VPOPMAIL_HOME)/bin/vadddomain || (echo "ERROR: vpopmail build did not produce vadddomain — check the make output above" && exit 1)
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)

# vpopmail's own stock Makefile.in already writes lib_deps/inc_deps (the exact linker/include
# flags needed to build against libvpopmail.a) to $(VPOPMAIL_HOME)/etc/ — QMT's own
# libvpopmail-devel packaging just relocates these two files to /etc/libvpopmail/ for a
# separate devel RPM (confirmed by reading their own libvpopmail-build-devel patch).
# qmailadmin/vqadmin's real configure.ac scripts hardcode that /etc/libvpopmail/{lib,inc}_deps
# path (and qmailadmin's own patch further redirects to $vpopmaildir/{lib,inc}_deps directly,
# no etc/ subdir — a second, slightly different QMT convention for the same two files) —
# these symlinks satisfy both without actually splitting into a separate package. A separate
# target from vpopmail's own build above, checked every run regardless of whether vpopmail
# itself needed rebuilding — see the "build:" line's own comment for why that split matters.
/etc/libvpopmail: $(VPOPMAIL_HOME)/bin/vadddomain
	mkdir -p /etc
	[ -e /etc/libvpopmail ] || ln -s $(VPOPMAIL_HOME)/etc /etc/libvpopmail
	[ -e $(VPOPMAIL_HOME)/inc_deps ] || ln -s etc/inc_deps $(VPOPMAIL_HOME)/inc_deps
	[ -e $(VPOPMAIL_HOME)/lib_deps ] || ln -s etc/lib_deps $(VPOPMAIL_HOME)/lib_deps

clean:
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)
