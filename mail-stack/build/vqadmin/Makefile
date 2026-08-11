# vqadmin — web-based (CGI) domain-level vpopmail admin. Depends on vpopmail.
#
# Source: vendored from QmailToaster's own EL10 SRPM (mail-stack/vendor/vqadmin/) — see
# mail-stack/vendor/README.md. Confirmed live 2026-08-02: the previous version of this
# Makefile's github.com/notqmail/vqadmin URL was a 404. Now source-built against our own
# real vpopmail (headers/lib at /home/vpopmail, matching what the spec's own hardcoded
# vpopmail.dir file already assumes) via MariaDB Connector/C — same real library vpopmail
# itself links against, replacing the earlier one-line mysql8.4-libs fix with a genuine
# consistent build, one less external dependency (AppStream's mysql8.4-libs is no longer
# needed for this component once source-built).

include ../../build.env

VENDOR  := ../../vendor/vqadmin
TARBALL := vqadmin-$(VQADMIN_VERSION).tar.gz
SRCDIR  := vqadmin-$(VQADMIN_VERSION)
CGIDIR  := /usr/share/toaster/cgi-bin/vqadmin

.PHONY: build clean

build: $(CGIDIR)/toaster.vqadmin

$(CGIDIR)/toaster.vqadmin: $(VPOPMAIL_HOME)/bin/vadddomain
	@echo "Building vqadmin $(VQADMIN_VERSION) from vendored source..."
	rm -rf /tmp/$(SRCDIR) && cp $(VENDOR)/$(TARBALL) /tmp/ && cd /tmp && tar xzf $(TARBALL)
	# The real vqadmin-2.3.7 tarball's html/*.html files are CRLF (old DJB-era templates), but
	# vqadmin.html.patch's "old content" lines lose their CRLF somewhere in git checkout/deploy
	# (confirmed: repo copy has them, server-deployed copy doesn't — depends on transfer path,
	# not reliable to fix by preserving raw bytes through git). Normalize the extracted html
	# files to LF here so they match whatever line-ending convention the patch actually carries
	# at apply time, instead of depending on CRLF surviving the round trip intact.
	cd /tmp/$(SRCDIR) && sed -i 's/\r$$//' html/*.html
	cd /tmp/$(SRCDIR) && patch -p0 < $(CURDIR)/$(VENDOR)/vqadmin.template.patch
	cd /tmp/$(SRCDIR) && patch -p0 < $(CURDIR)/$(VENDOR)/vqadmin.valias.patch
	cd /tmp/$(SRCDIR) && patch -p0 < $(CURDIR)/$(VENDOR)/vqadmin.chrome.patch
	# Normalize the patch itself too (not just the extracted source above) — don't rely on
	# either side's CRLF surviving whatever transfer path deployed this file to the build box.
	cd /tmp/$(SRCDIR) && sed 's/\r$$//' $(CURDIR)/$(VENDOR)/vqadmin.html.patch | patch -p2
	cd /tmp/$(SRCDIR) && patch -p1 < $(CURDIR)/$(VENDOR)/vqadmin.vpopmail.devel.patch
	cd /tmp/$(SRCDIR) && patch -p1 < $(CURDIR)/$(VENDOR)/vqadmin.vpopmail.ver.patch
	cd /tmp/$(SRCDIR) && patch -p1 < $(CURDIR)/$(VENDOR)/vqadmin-dom-defaults.patch
	cd /tmp/$(SRCDIR) && patch -p1 < $(CURDIR)/$(VENDOR)/vqadmin-el9-to-el10.patch
	cd /tmp/$(SRCDIR) && patch -p1 < $(CURDIR)/$(VENDOR)/vqadmin-configure.in.patch
	echo 89 > /tmp/$(SRCDIR)/vpopmail.uid
	echo 89 > /tmp/$(SRCDIR)/vpopmail.gid
	echo $(VPOPMAIL_HOME) > /tmp/$(SRCDIR)/vpopmail.dir
	cd /tmp/$(SRCDIR) && cp /usr/lib/rpm/redhat/config.guess . 2>/dev/null || true
	cd /tmp/$(SRCDIR) && cp /usr/lib/rpm/redhat/config.sub . 2>/dev/null || true
	cd /tmp/$(SRCDIR) && mv configure.in configure.ac
	cd /tmp/$(SRCDIR) && autoreconf -f -i
	cd /tmp/$(SRCDIR) && CFLAGS="$(CFLAGS_COMMON)" ./configure \
	  --enable-qmaildir=$(QMAIL_HOME) \
	  --enable-vpopuser=$(VPOPMAIL_USER) \
	  --enable-vpopgroup=$(VPOPMAIL_GROUP) \
	  --enable-cgibindir=/usr/share/toaster/cgi-bin/
	cd /tmp/$(SRCDIR) && make
	mkdir -p $(CGIDIR)/html /usr/share/toaster/include
	install -m 755 /tmp/$(SRCDIR)/vqadmin $(CGIDIR)/toaster.vqadmin
	install -m 644 /tmp/$(SRCDIR)/vqadmin.acl $(CGIDIR)/vqadmin.acl
	cp -r /tmp/$(SRCDIR)/html/* $(CGIDIR)/html/ 2>/dev/null || true
	[ -d /tmp/$(SRCDIR)/html/en ] && cp -r /tmp/$(SRCDIR)/html/en $(CGIDIR)/html/en-us || true
	@test -x $(CGIDIR)/toaster.vqadmin || (echo "ERROR: vqadmin build did not produce a binary" && exit 1)
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)

clean:
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)
