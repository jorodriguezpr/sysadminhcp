# notqmail — maintained qmail fork, same /var/qmail layout as classic QmailToaster.
# Doesn't need MySQL/MariaDB at all — vpopmail is the only component that does.
#
# Logic ported directly from sysadminhcp/deploy/install-almalinux10.sh (LIVE-VERIFIED on a
# real AlmaLinux 10 box, 2026-08-02) and sysadminhcp/deploy/install-ubuntu22.sh
# (live-verified working) — keep those three copies in sync if this build logic changes;
# don't let them drift.
#
# Real bug found + fixed during live verification: GCC 14 (AlmaLinux 10's default) made
# -Wimplicit-function-declaration an error instead of a warning — breaks
# seek_cur.c/seek_end.c/seek_set.c (call lseek() without including <unistd.h>, ~20-year-old
# K&R-style code). conf-cc (below) is what notqmail's DJB-style build actually reads for the
# compile command — it does NOT respect a CFLAGS env var.

include ../../build.env

TARBALL := notqmail-$(NOTQMAIL_VERSION).tar.gz
SRCDIR  := notqmail-$(NOTQMAIL_VERSION)
URL     := https://github.com/notqmail/notqmail/releases/download/notqmail-$(NOTQMAIL_VERSION)/$(TARBALL)

.PHONY: build clean

build: /var/qmail/bin/qmail-smtpd

/var/qmail/bin/qmail-smtpd:
	@echo "Building notqmail $(NOTQMAIL_VERSION) from source..."
	cd /tmp && rm -rf $(SRCDIR) && curl -fsSL -o $(TARBALL) "$(URL)"
	cd /tmp && tar xzf $(TARBALL)
	echo "cc -O2 -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion" > /tmp/$(SRCDIR)/conf-cc
	cd /tmp/$(SRCDIR) && make -j$$(nproc)
	cd /tmp/$(SRCDIR) && make setup check
	cd /tmp/$(SRCDIR) && ./config-fast "$$(hostname -f 2>/dev/null || hostname)" || true
	echo "./Maildir/" > /var/qmail/control/defaultdelivery
	printf '#!/bin/sh\nexec env - PATH="/var/qmail/bin:$$PATH" \\\nqmail-start "`cat /var/qmail/control/defaultdelivery 2>/dev/null || echo ./Maildir/`"\n' > /var/qmail/rc
	chmod 755 /var/qmail/rc
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)

clean:
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)
