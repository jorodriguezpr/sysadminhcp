# qmailadmin — web-based (CGI) per-domain mailbox admin. Depends on vpopmail + ezmlm-idx +
# autorespond, all built earlier in the dependency graph.
#
# Source: vendored from QmailToaster's own EL10 SRPM (mail-stack/vendor/qmailadmin/) — see
# mail-stack/vendor/README.md. Confirmed live 2026-08-02: the previous version of this
# Makefile's github.com/notqmail/qmailadmin URL was a 404. Now source-built against our own
# real vpopmail (headers/lib at /home/vpopmail — NOT QMT's own build convention of
# /etc/libvpopmail, which assumes a separate libvpopmail-static devel package we don't have)
# and MariaDB Connector/C, replacing the earlier one-line mysql8.4-libs fix with a genuine
# consistent build — one less external dependency once source-built.

include ../../build.env

VENDOR  := ../../vendor/qmailadmin
TARBALL := qmailadmin-$(QMAILADMIN_VERSION).tar.gz
SRCDIR  := qmailadmin-$(QMAILADMIN_VERSION)
CGIDIR  := /usr/share/qmailadmin

.PHONY: build clean

build: $(CGIDIR)/qmailadmin

$(CGIDIR)/qmailadmin: $(VPOPMAIL_HOME)/bin/vadddomain /usr/bin/ezmlm-make /usr/bin/autorespond
	@echo "Building qmailadmin $(QMAILADMIN_VERSION) from vendored source..."
	MYSQL_INC=""; \
	for d in $(MYSQL_INC_CANDIDATES); do [ -d "$$d" ] && MYSQL_INC="$$d" && break; done; \
	rm -rf /tmp/$(SRCDIR) && cp $(VENDOR)/$(TARBALL) /tmp/ && cd /tmp && tar xzf $(TARBALL) && \
	cd /tmp/$(SRCDIR) && \
	patch -p1 < $(CURDIR)/$(VENDOR)/qmailadmin-vpop-devel.patch && \
	patch -p1 < $(CURDIR)/$(VENDOR)/qmailadmin-vpop-nouser.patch && \
	patch -p1 < $(CURDIR)/$(VENDOR)/qmailadmin-bounce-fix.patch && \
	patch -p1 < $(CURDIR)/$(VENDOR)/qmailadmin-new-interface.patch && \
	patch -p1 < $(CURDIR)/$(VENDOR)/qmailadmin.authors.patch && \
	patch -p0 < $(CURDIR)/$(VENDOR)/qmailadmin-el9-to-el10.patch && \
	mv configure.in configure.ac && \
	autoreconf -f -i && \
	CFLAGS="$(CFLAGS_COMMON) -I$$MYSQL_INC" LDFLAGS="-L/usr/lib64" ./configure \
	  --prefix=/usr \
	  --datadir=/usr/share/qmailadmin \
	  --enable-autoresponder-path=/usr/bin \
	  --enable-cgibindir=/usr/share/qmailadmin \
	  --enable-cgipath=/qmailadmin/index.cgi \
	  --enable-domain-autofill=n \
	  --enable-ezmlm-mysql=y \
	  --enable-ezmlmdir=/usr/bin \
	  --enable-help=y \
	  --enable-htmllibdir=/usr/share/qmailadmin \
	  --enable-htmldir=/usr/share/qmailadmin \
	  --enable-imagedir=/usr/share/qmailadmin/images \
	  --enable-imageurl=/qmailadmin/images \
	  --enable-maxusersperpage=12 \
	  --enable-maxaliasesperpage=12 \
	  --enable-modify-quota=y \
	  --enable-qmaildir=$(QMAIL_HOME) \
	  --enable-vpopgroup=$(VPOPMAIL_GROUP) \
	  --enable-vpopmaildir=$(VPOPMAIL_HOME) \
	  --enable-vpopuser=$(VPOPMAIL_USER) \
	  --disable-ipauth && \
	make && make install-strip
	@# make install-strip (matching the real spec exactly, instead of manually copying
	@# files afterward) is what actually places html/lang/images correctly — an earlier
	@# version of this Makefile skipped it and manually cp'd files instead, which flattened
	@# the html/ subdirectory structure qmailadmin's own compiled-in template paths expect
	@# (confirmed live: "cannot lstat '/usr/share/qmailadmin/html/header.html'" at runtime).
	ln -sf qmailadmin $(CGIDIR)/index.cgi
	chown $(VPOPMAIL_USER):$(VPOPMAIL_GROUP) $(CGIDIR)/qmailadmin && chmod 6755 $(CGIDIR)/qmailadmin
	@test -x $(CGIDIR)/qmailadmin || (echo "ERROR: qmailadmin build did not produce a binary" && exit 1)
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)

clean:
	rm -rf /tmp/$(SRCDIR) /tmp/$(TARBALL)
