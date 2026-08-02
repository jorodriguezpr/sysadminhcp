# ezmlm-idx — mailing list manager (base ezmlm + the ezmlm-idx patch overlay, with MySQL
# support wired to MariaDB Connector/C — see below).
#
# Source: vendored from QmailToaster's own EL10 SRPM (mail-stack/vendor/ezmlm-idx/) — see
# mail-stack/vendor/README.md. Confirmed live 2026-08-02: the previous version of this
# Makefile's github.com/notqmail/ezmlm-idx URL was a 404. This is a real merge of two
# tarballs (base ezmlm-0.53 + the ezmlm-idx-0.40 overlay patch set), exactly matching QMT's
# own real spec recipe.
#
# QMT's own spec links this against mysql8.4-devel directly (their real, current EL10
# approach) — but mysql8.4-devel conflicts with mariadb-connector-c-devel (already installed
# for vpopmail) at the package level, both owning the same /usr/include/mysql path. Fix:
# mariadb-connector-c-devel ALSO ships /usr/lib64/libmysqlclient.so as MariaDB's own official
# compatibility symlink (not a hand-rolled shim) plus the same mysql.h — so this links against
# that instead, consistent with vpopmail's already-proven approach: one real library
# throughout, at both compile time and runtime, no ABI mismatch.

include ../../build.env

VENDOR   := ../../vendor/ezmlm-idx
EZTARBALL  := ezmlm-$(EZMLM_IDX_VERSION).tar.gz
IDXTARBALL := ezmlm-idx-0.40.tar.gz
SRCDIR     := ezmlm-$(EZMLM_IDX_VERSION)

.PHONY: build clean

build: /usr/bin/ezmlm-make

/usr/bin/ezmlm-make: /var/qmail/bin/qmail-smtpd
	@echo "Building ezmlm-idx (base $(EZMLM_IDX_VERSION) + idx 0.40 overlay) from vendored source..."
	MYSQL_INC=""; \
	for d in $(MYSQL_INC_CANDIDATES); do [ -d "$$d" ] && MYSQL_INC="$$d" && break; done; \
	if [ -z "$$MYSQL_INC" ]; then echo "ERROR: no MariaDB/MySQL client headers found"; exit 1; fi; \
	rm -rf /tmp/$(SRCDIR) && cp $(VENDOR)/$(EZTARBALL) $(VENDOR)/$(IDXTARBALL) /tmp/ && \
	cd /tmp && tar xzf $(EZTARBALL) && tar xzf $(IDXTARBALL) -C $(SRCDIR) && \
	cd /tmp/$(SRCDIR) && mv -f ezmlm-idx-0.40/* . && rmdir ezmlm-idx-0.40 && \
	patch -s < idx.patch && \
	patch -p1 < $(CURDIR)/$(VENDOR)/ezmlm-gcc.patch && \
	patch -p1 < $(CURDIR)/$(VENDOR)/ezmlm-el9-to-el10.patch && \
	sed -i 's{^#define TXT_ETC_EZMLMRC "/etc/ezmlmrc"{#define TXT_ETC_EZMLMRC "/etc/ezmlm/ezmlmrc"{' idx.h && \
	sed -i "s|\`head -1 conf-sqlld\`|-L/usr/lib64 -lmysqlclient -lm -lz|g" Makefile && \
	echo "gcc $(CFLAGS_COMMON) -Wno-implicit-function-declaration -I$$MYSQL_INC" > conf-cc && \
	echo "gcc $(CFLAGS_COMMON)" > conf-ld && \
	echo /usr/bin > conf-bin && \
	echo /usr/share/man > conf-man && \
	echo "#include <errno.h>" >> error.h && \
	make && make it install
	@# "make it install" compiles the DJB-style ./install HELPER PROGRAM (install.c ->
	@# install binary) — it does NOT copy files anywhere itself. The real copy step, per
	@# QMT's own spec's separate %install section, is running that helper against the BIN
	@# manifest (one c:...:name: line per binary to place in /usr/bin).
	mkdir -p /etc/ezmlm
	cd /tmp/$(SRCDIR) && ./install /usr/bin < BIN
	[ -f /etc/ezmlm/ezmlmrc ] || cp /tmp/$(SRCDIR)/ezmlmrc.en_US /etc/ezmlm/ezmlmrc
	@test -x /usr/bin/ezmlm-make || (echo "ERROR: ezmlm-idx build did not produce ezmlm-make" && exit 1)
	rm -rf /tmp/$(SRCDIR) /tmp/$(EZTARBALL) /tmp/$(IDXTARBALL)

clean:
	rm -rf /tmp/$(SRCDIR) /tmp/$(EZTARBALL) /tmp/$(IDXTARBALL)
