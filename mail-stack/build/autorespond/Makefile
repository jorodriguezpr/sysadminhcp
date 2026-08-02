# autorespond — vacation/autoresponder tool the panel wires into .qmail files.
#
# Source: vendored from QmailToaster's own EL10 SRPM (mail-stack/vendor/autorespond/) — see
# mail-stack/vendor/README.md. Confirmed live 2026-08-02: the previous version of this
# Makefile's github.com/notqmail/autorespond URL was a 404. This version uses QMT's own real
# spec recipe (single gcc compile, no configure) plus their own EL9-to-EL10 patch.

include ../../build.env

VENDOR  := ../../vendor/autorespond
TARBALL := autorespond-$(AUTORESPOND_VERSION).tar.gz
SRCDIR  := autorespond-$(AUTORESPOND_VERSION)

.PHONY: build clean

build: /usr/bin/autorespond

/usr/bin/autorespond: /var/qmail/bin/qmail-smtpd
	@echo "Building autorespond $(AUTORESPOND_VERSION) from vendored source..."
	rm -rf /tmp/$(SRCDIR) && cp $(VENDOR)/$(TARBALL) /tmp/ && cd /tmp && tar xzf $(TARBALL)
	cd /tmp/$(SRCDIR) && patch -p1 < $(CURDIR)/$(VENDOR)/autorespond-el9-to-el10.patch
	cd /tmp/$(SRCDIR) && gcc $(CFLAGS_COMMON) -Wall -o autorespond autorespond.c
	install -m 755 /tmp/$(SRCDIR)/autorespond /usr/bin/autorespond
	@test -x /usr/bin/autorespond || (echo "ERROR: autorespond build did not produce a binary" && exit 1)
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)

clean:
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)
