# maildrop — mail filtering/delivery agent. Standalone (no qmail/vpopmail dependency). Not
# currently wired into any real SysAdminHCP feature (checked systemService.ts — only a
# comment references it, no actual invocation code) — built anyway per explicit direction
# to eliminate QMT repo dependency for every component QMT's install currently pulls in,
# not just the ones actively used today.
#
# Source: vendored from QmailToaster's own EL10 SRPM (mail-stack/vendor/maildrop/) — see
# mail-stack/vendor/README.md. Confirmed live 2026-08-02: the previous version of this
# Makefile's sourceforge courier URL for maildrop itself was untested; this real spec has no
# patches at all (plain upstream courier-mta.org build). One real dependency,
# courier-unicode-devel, only exists for EL10 via qmt-testing — but courier-unicode is a
# real, independent open-source library (courier-mta.org, not QMT-authored) with its own
# real sourceforge release, so it's vendored and built from its own source here too, the
# same way legacy PCRE1 was for simscan.

include ../../build.env

VENDOR       := ../../vendor/maildrop
TARBALL      := maildrop-$(MAILDROP_VERSION).tar.bz2
SRCDIR       := maildrop-$(MAILDROP_VERSION)
CU_VERSION   := 2.3.2
CU_VENDOR    := ../../vendor/courier-unicode
CU_TARBALL   := courier-unicode-$(CU_VERSION).tar.bz2
CU_SRCDIR    := courier-unicode-$(CU_VERSION)

.PHONY: build clean

build: /usr/bin/maildrop

/usr/local/lib/libcourier-unicode.so:
	@echo "Building courier-unicode $(CU_VERSION) from vendored source (real courier-mta.org upstream)..."
	rm -rf /tmp/$(CU_SRCDIR) && cp $(CU_VENDOR)/$(CU_TARBALL) /tmp/ && cd /tmp && tar xjf $(CU_TARBALL)
	cd /tmp/$(CU_SRCDIR) && CFLAGS="$(CFLAGS_COMMON)" CXXFLAGS="$(CFLAGS_COMMON)" ./configure --prefix=/usr/local
	cd /tmp/$(CU_SRCDIR) && make && make install
	ldconfig 2>/dev/null || true
	rm -rf /tmp/$(CU_SRCDIR) /tmp/$(CU_TARBALL)

/usr/bin/maildrop: /usr/local/lib/libcourier-unicode.so
	@echo "Building maildrop $(MAILDROP_VERSION) from vendored source..."
	rm -rf /tmp/$(SRCDIR) && cp $(VENDOR)/$(TARBALL) /tmp/ && cd /tmp && tar xjf $(TARBALL)
	cd /tmp/$(SRCDIR) && CFLAGS="$(CFLAGS_COMMON)" CXXFLAGS="$(CFLAGS_COMMON)" \
	  PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
	  LDFLAGS="-L/usr/local/lib -Wl,-rpath,/usr/local/lib" \
	  ./configure --prefix=/usr --with-devel --enable-syslog=1 \
	  --enable-trusted-users='root mail daemon postmaster qmaild mmdf' \
	  --enable-restrict-trusted=0 \
	  --enable-sendmail=/var/qmail/bin/sendmail
	cd /tmp/$(SRCDIR) && make
	cd /tmp/$(SRCDIR) && make install MAILDROPUID='' MAILDROPGID=''
	@test -x /usr/bin/maildrop || (echo "ERROR: maildrop build did not produce a binary" && exit 1)
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)

clean:
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL) /tmp/$(CU_SRCDIR) /tmp/$(CU_TARBALL)
