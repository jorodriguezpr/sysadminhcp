# spamdyke — SMTP-time anti-spam filter + TLS, wrapped around qmail-smtpd via tcpserver.
#
# Source: vendored from QmailToaster's own EL10 SRPM (mail-stack/vendor/spamdyke/) — see
# mail-stack/vendor/README.md. Confirmed live 2026-08-02: the previous version of this
# Makefile's spamdyke.org/github.com/spamdyke URLs were both 404. This uses QMT's own real
# spec recipe — plus their own real spamdyke-openssl3.patch, which modernizes spamdyke's
# OpenSSL API usage (SSL_library_init -> OPENSSL_init_ssl, adds a real "tls-ciphersuites"
# config option for TLS 1.3) instead of just avoiding the problem the way today's earlier
# config-only fix did (restricting to TLS 1.2-only ciphers). Installs to /opt/spamdyke/bin
# with a /usr/bin/spamdyke symlink, matching the real, already-working layout.

include ../../build.env

VENDOR  := ../../vendor/spamdyke
TARBALL := spamdyke-$(SPAMDYKE_VERSION).tgz
SRCDIR  := spamdyke-$(SPAMDYKE_VERSION)

.PHONY: build clean

build: /usr/bin/spamdyke

/usr/bin/spamdyke:
	@echo "Building spamdyke $(SPAMDYKE_VERSION) from vendored source..."
	rm -rf /tmp/$(SRCDIR) && cp $(VENDOR)/$(TARBALL) /tmp/ && cd /tmp && tar xzf $(TARBALL)
	cd /tmp/$(SRCDIR) && patch -p1 < $(CURDIR)/$(VENDOR)/spamdyke-openssl3.patch
	cd /tmp/$(SRCDIR)/spamdyke && CFLAGS="$(CFLAGS_COMMON)" ./configure --enable-tls
	cd /tmp/$(SRCDIR)/spamdyke && make
	mkdir -p /opt/spamdyke/bin /opt/spamdyke/etc /opt/spamdyke/var/graylist
	install -m 755 /tmp/$(SRCDIR)/spamdyke/spamdyke /opt/spamdyke/bin/spamdyke
	ln -sf /opt/spamdyke/bin/spamdyke /usr/bin/spamdyke
	[ -L /etc/spamdyke ] || [ -d /etc/spamdyke ] || ln -sf /opt/spamdyke/etc /etc/spamdyke
	@test -x /usr/bin/spamdyke || (echo "ERROR: spamdyke build did not produce a binary" && exit 1)
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)

clean:
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)
