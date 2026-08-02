# simscan — SMTP-time ClamAV + SpamAssassin scanning, invoked via QMAILQUEUE.
#
# Source: vendored from QmailToaster's own EL10 SRPM (mail-stack/vendor/simscan/) — see
# mail-stack/vendor/README.md. Confirmed live 2026-08-02: the previous version of this
# Makefile's github.com/notqmail/simscan URL was a 404. This uses QMT's own real spec recipe
# (autoconf ./configure) plus their own 5 patches (qt-combined, pid, dspam-debug,
# dspam-xclass, el9-to-el10), including their own already-engineered fix for simscan's
# vendored DJB cdb library (same class of GCC14 implicit-function-declaration issue
# notqmail/vpopmail hit — QMT's spec sed-patches cdb/conf-cc for exactly this).
#
# Installs SUID clamscan:root per the real spec (4711) — simscan runs as the unprivileged
# clamscan user even when invoked from qmail-queue running as qmails.
#
# simscan's own configure.in hard-requires the legacy PCRE1 API (pcre.h/pcre_compile, NOT
# PCRE2's pcre2.h/pcre2_compile) — confirmed live 2026-08-02, the spec's own
# "BuildRequires: pcre2-devel" is stale/wrong, ./configure fails looking for pcre.h
# regardless. AlmaLinux 10 dropped PCRE1 (PCRE2 only), and the ONLY place PCRE1-devel exists
# for EL10 is QMT's own repo — but PCRE1 itself is a real, independent, non-QMT open-source
# library (pcre.org / sourceforge), so it's built from ITS OWN real upstream here rather
# than depending on QMT for it too.

include ../../build.env

VENDOR    := ../../vendor/simscan
TARBALL   := simscan-$(SIMSCAN_VERSION).tar.gz
SRCDIR    := simscan-$(SIMSCAN_VERSION)
PCRE_VERSION := 8.45
PCRE_TARBALL := pcre-$(PCRE_VERSION).tar.gz
PCRE_SRCDIR  := pcre-$(PCRE_VERSION)
PCRE_VENDOR  := ../../vendor/pcre1

.PHONY: build clean

build: /var/qmail/bin/simscan

# Vendored rather than live-fetched from sourceforge — its mirror redirect
# (dl.sourceforge.net -> a random regional mirror) proved flaky/intermittent live
# 2026-08-02, unlike vpopmail's sourceforge fetch which succeeded reliably; vendoring avoids
# depending on that redirect working at every install.
/usr/local/lib/libpcre.so:
	@echo "Building legacy PCRE1 $(PCRE_VERSION) from vendored source (real pcre.org upstream)..."
	rm -rf /tmp/$(PCRE_SRCDIR) && cp $(PCRE_VENDOR)/$(PCRE_TARBALL) /tmp/ && cd /tmp && tar xzf $(PCRE_TARBALL)
	cd /tmp/$(PCRE_SRCDIR) && CFLAGS="$(CFLAGS_COMMON)" ./configure --prefix=/usr/local
	cd /tmp/$(PCRE_SRCDIR) && make && make install
	ldconfig 2>/dev/null || true
	rm -rf /tmp/$(PCRE_SRCDIR) /tmp/$(PCRE_TARBALL)

/var/qmail/bin/simscan: /var/qmail/bin/qmail-smtpd /usr/bin/ripmime /usr/local/lib/libpcre.so
	@echo "Building simscan $(SIMSCAN_VERSION) from vendored source..."
	getent passwd clamscan >/dev/null || useradd -r -d /var/qmail/simscan -s /sbin/nologin clamscan
	rm -rf /tmp/$(SRCDIR) && cp $(VENDOR)/$(TARBALL) /tmp/ && cd /tmp && tar xzf $(TARBALL)
	cd /tmp/$(SRCDIR) && patch -p1 < $(CURDIR)/$(VENDOR)/simscan-1.4.0.qt.patch
	cd /tmp/$(SRCDIR) && patch -p1 < $(CURDIR)/$(VENDOR)/simscan-1.4.0-pid.patch
	cd /tmp/$(SRCDIR) && patch -p1 < $(CURDIR)/$(VENDOR)/simscan-1.4.0-dspam-debug.patch
	cd /tmp/$(SRCDIR) && patch -p0 < $(CURDIR)/$(VENDOR)/simscan-1.4.0-dspam-xclass.patch
	cd /tmp/$(SRCDIR) && patch -p1 < $(CURDIR)/$(VENDOR)/simscan-el9-to-el10.patch
	cd /tmp/$(SRCDIR) && CFLAGS="$(CFLAGS_COMMON) -I/usr/local/include" LDFLAGS="-L/usr/local/lib -Wl,-rpath,/usr/local/lib" ./configure \
	  --with-pcre-include=/usr/local/include \
	  --with-pcre-lib=/usr/local/lib \
	  --enable-attach \
	  --enable-clamdscan=/usr/bin/clamdscan \
	  --enable-clamavdb-path=/var/lib/clamav \
	  --enable-custom-smtp-reject \
	  --enable-per-domain \
	  --enable-qmaildir=/var/qmail \
	  --enable-qmail-queue=/var/qmail/bin/qmail-queue \
	  --enable-received \
	  --enable-ripmime=/usr/bin/ripmime \
	  --enable-sigtool-path=/usr/bin/sigtool \
	  --enable-spam \
	  --enable-spam-hits=40 \
	  --enable-spamassassin-path=/usr/bin/spamassassin \
	  --enable-spamc=/usr/bin/spamc \
	  --enable-spamc-user=y \
	  --enable-user=clamscan \
	  --enable-dspam=y \
	  --enable-dspam-user=y \
	  --enable-dspam-path=/usr/bin/dspamc \
	  --enable-rspam=y \
	  --enable-rspam-path=/usr/bin/rspamc \
	  --enable-regex=y
	sed -i "s|-O2|-fPIC -O2 $(CFLAGS_COMMON)|g" /tmp/$(SRCDIR)/cdb/conf-cc
	cd /tmp/$(SRCDIR) && make
	mkdir -p /var/qmail/simscan
	chown clamscan:clamscan /var/qmail/simscan && chmod 750 /var/qmail/simscan
	install -m 4711 -o clamscan -g root /tmp/$(SRCDIR)/simscan /var/qmail/bin/simscan
	install -m 4755 -o root -g root /tmp/$(SRCDIR)/simscanmk /var/qmail/bin/simscanmk
	install -m 755 $(VENDOR)/update-simscan /var/qmail/bin/update-simscan
	[ -f /var/qmail/control/simcontrol ] || install -m 644 -o clamscan $(VENDOR)/simcontrol /var/qmail/control/simcontrol
	/var/qmail/bin/update-simscan || true
	@test -x /var/qmail/bin/simscan || (echo "ERROR: simscan build did not produce a binary" && exit 1)
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)

clean:
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)
