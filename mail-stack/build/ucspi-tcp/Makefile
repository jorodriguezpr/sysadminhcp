# ucspi-tcp — provides tcpserver/tcprules, the port-25/587 listener wrapper.
#
# Source: vendored from QmailToaster's own EL10 SRPM (mail-stack/vendor/ucspi-tcp/) — the
# real upstream (cr.yp.to, D.J. Bernstein, public domain) has no GitHub mirror or stable
# fetch-at-build-time URL; see mail-stack/vendor/README.md for why this is vendored instead
# of live-fetched. Confirmed live 2026-08-02: every "fetch from github.com/notqmail/..." URL
# a previous version of this Makefile used was a 404 — fabricated by the original Copilot
# research, never actually tested. This version uses QMT's own real, working spec recipe
# (read directly from ucspi-tcp.spec inside the SRPM) plus their own already-engineered
# EL9-to-EL10 patch, with today's GCC14 CFLAGS fix layered on top via build.env.
#
# Installs to /usr/bin, NOT the DJB-default /usr/local/bin — every run script and the panel
# itself hardcode /usr/bin/tcpserver, /usr/bin/tcprules, etc. (confirmed live via the actual
# supervise/smtp/run script content).

include ../../build.env

VENDOR  := ../../vendor/ucspi-tcp
TARBALL := ucspi-tcp-$(UCSPI_TCP_VERSION).tar.gz
SRCDIR  := ucspi-tcp-$(UCSPI_TCP_VERSION)
BINS    := addcr argv0 date@ delcr finger@ fixcrio http@ mconnect mconnect-io rblsmtpd recordio tcpcat tcpclient tcprules tcprulescheck tcpserver who@

.PHONY: build clean

build: /usr/bin/tcpserver

/usr/bin/tcpserver:
	@echo "Building ucspi-tcp $(UCSPI_TCP_VERSION) from vendored source..."
	rm -rf /tmp/$(SRCDIR) && cp $(VENDOR)/$(TARBALL) /tmp/ && cd /tmp && tar xzf $(TARBALL)
	cd /tmp/$(SRCDIR) && patch -p0 < $(CURDIR)/$(VENDOR)/ucspi-tcp-04182004.patch
	cd /tmp/$(SRCDIR) && patch -p0 < $(CURDIR)/$(VENDOR)/ucspi-tcp-rbltimeout.patch
	cd /tmp/$(SRCDIR) && patch -p1 < $(CURDIR)/$(VENDOR)/ucspi-tcp-limits.patch
	cd /tmp/$(SRCDIR) && patch -p1 < $(CURDIR)/$(VENDOR)/ucspi-tcp-el9-to-el10.patch
	echo "gcc $(CFLAGS_COMMON)" > /tmp/$(SRCDIR)/conf-cc
	echo "gcc -s $(CFLAGS_COMMON)" > /tmp/$(SRCDIR)/conf-ld
	echo "/usr" > /tmp/$(SRCDIR)/conf-home
	cd /tmp/$(SRCDIR) && make
	@for b in $(BINS); do install -m 755 /tmp/$(SRCDIR)/$$b /usr/bin/$$b; done
	@test -x /usr/bin/tcpserver || (echo "ERROR: ucspi-tcp build did not produce tcpserver" && exit 1)
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)

clean:
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)
