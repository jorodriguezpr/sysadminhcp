# ripmime — MIME attachment extraction, used by simscan at SMTP time. No dependencies, no
# patches needed (QMT ships this component patch-free — real spec confirmed, it's actually
# just Fedora's own ripmime package, not QMT-authored at all).
#
# Source: vendored from QmailToaster's own EL10 SRPM (mail-stack/vendor/ripmime/) — see
# mail-stack/vendor/README.md. Confirmed live 2026-08-02: the previous version of this
# Makefile's github.com/wettenhaller/ripMIME URL was a 404.

include ../../build.env

VENDOR  := ../../vendor/ripmime
TARBALL := ripmime-$(RIPMIME_VERSION).tar.gz
SRCDIR  := ripmime-$(RIPMIME_VERSION)

.PHONY: build clean

build: /usr/bin/ripmime

/usr/bin/ripmime:
	@echo "Building ripmime $(RIPMIME_VERSION) from vendored source..."
	rm -rf /tmp/$(SRCDIR) && cp $(VENDOR)/$(TARBALL) /tmp/ && cd /tmp && tar xzf $(TARBALL)
	cd /tmp/$(SRCDIR) && make CFLAGS="$(CFLAGS_COMMON)"
	install -m 755 /tmp/$(SRCDIR)/ripmime /usr/bin/ripmime
	@test -x /usr/bin/ripmime || (echo "ERROR: ripmime build did not produce a binary" && exit 1)
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)

clean:
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)
