# isoqlog — qmail log statistics tool (EnderUNIX Software, BSD-licensed), part of the legacy
# toaster admin skin. No independent GitHub mirror (its real upstream, enderunix.org, is a
# dead/unreliable site now) — vendored from QmailToaster's own EL10 SRPM
# (mail-stack/vendor/isoqlog/), see mail-stack/vendor/README.md. Real, working code with a
# real binary — kept per explicit direction to migrate every component QMT's install
# currently pulls in, not just the actively-used ones.
#
# Only the core binary + isoqlog's own stock templates are installed here — QMT's own
# customized HTML templates and Apache/cron wiring (separate Source files in their spec, not
# needed to vendor since they're purely cosmetic on top of the same real binary) are not
# included; isoqlog's own bundled default templates (from `make install` itself) are used
# instead, so the tool is fully functional, just without QMT's specific skin.
#
# QMT's own real GCC11 compat patch (isoqlog-gcc11.patch) adds proper `extern` declarations
# for ~15 tentative-definition globals — the same GCC10+ -fno-common class of issue vpopmail
# hit (fixed there via -fcommon; isoqlog's own fix is proper extern instead, already
# GCC14-safe, but today's CFLAGS_COMMON is layered on top anyway as a second safety net).

include ../../build.env

VENDOR  := ../../vendor/isoqlog
TARBALL := isoqlog-$(ISOQLOG_VERSION).tar.gz
SRCDIR  := isoqlog-$(ISOQLOG_VERSION)

.PHONY: build clean

build: /usr/bin/isoqlog

/usr/bin/isoqlog:
	@echo "Building isoqlog $(ISOQLOG_VERSION) from vendored source..."
	rm -rf /tmp/$(SRCDIR) && cp $(VENDOR)/$(TARBALL) /tmp/ && cd /tmp && tar xzf $(TARBALL)
	cd /tmp/$(SRCDIR) && patch -p0 < $(CURDIR)/$(VENDOR)/isoqlog-gcc11.patch
	cd /tmp/$(SRCDIR) && CFLAGS="$(CFLAGS_COMMON)" ./configure \
	  --prefix=/usr \
	  --sysconfdir=/etc/isoqlog \
	  --localstatedir=/var
	cd /tmp/$(SRCDIR) && make
	cd /tmp/$(SRCDIR) && make install
	@test -x /usr/bin/isoqlog || (echo "ERROR: isoqlog build did not produce a binary" && exit 1)
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)

clean:
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)
