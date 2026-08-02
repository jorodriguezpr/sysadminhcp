# daemontools — svscan/supervise process management + softlimit/svc/setuidgid binaries.
# On this AlmaLinux 10 install, only the standalone binaries (softlimit, setuidgid, svc,
# multilog, etc.) are actually used — mail services run under systemd units
# (qmail-send.service etc.), not daemontools' own svscan supervision tree. Still built in
# full since every run script hardcodes /usr/bin/softlimit and friends.
#
# Source: vendored from QmailToaster's own EL10 SRPM (mail-stack/vendor/daemontools/) — see
# mail-stack/vendor/README.md. Confirmed live 2026-08-02: the previous version of this
# Makefile's github.com/notqmail/daemontools URL was a 404, fabricated by the original
# Copilot research. This version uses QMT's own real spec recipe plus their own
# already-engineered errno + EL9-to-EL10 patches, with today's GCC14 CFLAGS layered on top.

include ../../build.env

VENDOR  := ../../vendor/daemontools
TARBALL := daemontools-$(DAEMONTOOLS_VERSION).tar.gz
SRCDIR  := admin/daemontools-$(DAEMONTOOLS_VERSION)
BINS    := svscan svscanboot supervise svc svok svstat fghack multilog pgrphack tai64n tai64nlocal readproctitle softlimit envuidgid envdir setlock setuidgid

.PHONY: build clean

build: /usr/bin/svc

/usr/bin/svc:
	@echo "Building daemontools $(DAEMONTOOLS_VERSION) from vendored source..."
	rm -rf /tmp/admin && cp $(VENDOR)/$(TARBALL) /tmp/ && cd /tmp && tar xzf $(TARBALL)
	cd /tmp/$(SRCDIR) && patch -p0 < $(CURDIR)/$(VENDOR)/daemontools-errno.patch
	cd /tmp/$(SRCDIR) && patch -p2 < $(CURDIR)/$(VENDOR)/daemontools-el9-to-el10.patch
	echo "gcc $(CFLAGS_COMMON)" > /tmp/$(SRCDIR)/src/conf-cc
	echo "gcc -s $(CFLAGS_COMMON)" > /tmp/$(SRCDIR)/src/conf-ld
	echo "/usr" > /tmp/$(SRCDIR)/src/conf-home
	cd /tmp/$(SRCDIR) && package/compile
	@for b in $(BINS); do install -m 755 /tmp/$(SRCDIR)/command/$$b /usr/bin/$$b; done
	mkdir -p /command /service
	@test -x /usr/bin/svc || (echo "ERROR: daemontools build did not produce svc" && exit 1)
	rm -rf /tmp/admin

clean:
	rm -rf /tmp/admin
