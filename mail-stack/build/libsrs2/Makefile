# libsrs2 — Sender Rewriting Scheme, used by qmail for SPF-safe forwarding. No dependencies,
# no patches needed (QMT ships this component patch-free — real spec confirmed).
#
# Source: vendored from QmailToaster's own EL10 SRPM (mail-stack/vendor/libsrs2/) — see
# mail-stack/vendor/README.md. Confirmed live 2026-08-02: the previous version of this
# Makefile's github.com/libsrs2/libsrs2 URL was a 404. --libdir=/usr/lib64 (not the
# ./configure default /usr/local/lib) matches QMT's own real spec, since spamdyke and
# anything else linking against libsrs2 expects it on the standard runtime linker path.

include ../../build.env

VENDOR  := ../../vendor/libsrs2
TARBALL := libsrs2-$(LIBSRS2_VERSION).tar.gz
SRCDIR  := libsrs2-$(LIBSRS2_VERSION)

.PHONY: build clean

build: /usr/lib64/libsrs2.so

/usr/lib64/libsrs2.so:
	@echo "Building libsrs2 $(LIBSRS2_VERSION) from vendored source..."
	rm -rf /tmp/$(SRCDIR) && cp $(VENDOR)/$(TARBALL) /tmp/ && cd /tmp && tar xzf $(TARBALL)
	cd /tmp/$(SRCDIR) && CFLAGS="$(CFLAGS_COMMON)" ./configure --prefix=/usr --libdir=/usr/lib64
	cd /tmp/$(SRCDIR) && make
	cd /tmp/$(SRCDIR) && make install
	ldconfig 2>/dev/null || true
	@test -f /usr/lib64/libsrs2.so || (echo "ERROR: libsrs2 build did not produce libsrs2.so" && exit 1)
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)

clean:
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)
