# qmailmrtg — MRTG-style qmail queue/traffic grapher, part of the legacy toaster admin skin.
# No independent upstream/GitHub mirror exists (confirmed live 2026-08-02 — this is why it's
# vendored from QmailToaster's own EL10 SRPM, mail-stack/vendor/qmailmrtg/, rather than
# fetched at build time — see mail-stack/vendor/README.md). Real, working code with a real
# binary — kept per explicit direction to migrate every component QMT's install currently
# pulls in, not just the actively-used ones.
#
# QMT's own real spec recipe: two patches (rhel8, el9-to-el10 — both real GCC-compatibility
# fixes for implicit-int / untyped argv issues, the same class notqmail/vpopmail hit), plain
# gcc compile (no configure/make — this is a two-file legacy C program), then install.

include ../../build.env

VENDOR  := ../../vendor/qmailmrtg
TARBALL := qmailmrtg7-$(QMAILMRTG_VERSION).tar.gz
SRCDIR  := qmailmrtg7-$(QMAILMRTG_VERSION)

.PHONY: build clean

build: /usr/bin/qmailmrtg

/usr/bin/qmailmrtg:
	@echo "Building qmailmrtg $(QMAILMRTG_VERSION) from vendored source..."
	rm -rf /tmp/$(SRCDIR) && cp $(VENDOR)/$(TARBALL) /tmp/ && cd /tmp && tar xzf $(TARBALL)
	cd /tmp/$(SRCDIR) && patch -p0 < $(CURDIR)/$(VENDOR)/qmailmrtg.rhel8.patch
	cd /tmp/$(SRCDIR) && patch -p2 < $(CURDIR)/$(VENDOR)/qmailmrtg-el9-to-el10.patch
	cd /tmp/$(SRCDIR) && gcc $(CFLAGS_COMMON) -Wno-implicit-function-declaration checkq.c -o checkq
	cd /tmp/$(SRCDIR) && ./checkq || true
	cd /tmp/$(SRCDIR) && gcc $(CFLAGS_COMMON) -Wno-implicit-function-declaration -O qmailmrtg7.c -o qmailmrtg
	install -m 755 /tmp/$(SRCDIR)/qmailmrtg /usr/bin/qmailmrtg
	mkdir -p /usr/share/toaster/mrtg
	[ -f /usr/share/toaster/mrtg/qmailmrtg.cfg ] || install -m 644 $(VENDOR)/qmailmrtg.cfg /usr/share/toaster/mrtg/qmailmrtg.cfg
	@test -x /usr/bin/qmailmrtg || (echo "ERROR: qmailmrtg build did not produce a binary" && exit 1)
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)

clean:
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)
