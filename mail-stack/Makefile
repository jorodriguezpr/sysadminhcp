# SysAdminHCP mail-stack — top-level build orchestrator
#
# Status: all 13 components below are real, live-verified source builds as of 2026-08-02 —
# see README.md's status table and each component's own Makefile header for the specific
# real functional test that proved it (not just "it compiled"). `control-panel` (plain PHP,
# no build step) is deployed directly by install-almalinux10.sh, not listed here.
# RPM/Debian packaging and CI remain explicitly out of scope — direct source-install already
# achieves full independence from QmailToaster's repo with far less overhead; see
# QMAILTOASTER-SELF-HOST-PLAN.md and project memory if that's ever revisited.

include build.env
export

COMPONENTS = ucspi-tcp daemontools libsrs2 ripmime \
             notqmail vpopmail autorespond ezmlm-idx \
             spamdyke simscan qmailadmin vqadmin maildrop \
             qmailmrtg isoqlog

.PHONY: all sources install clean rpms debs $(COMPONENTS)

all: sources

# Build every component, in dependency order (see QMAILTOASTER-SELF-HOST-PLAN.md §4 for the
# full dependency graph — this list is already topologically sorted).
sources: $(COMPONENTS)

$(COMPONENTS):
	@echo "=== Building $@ from source ==="
	@$(MAKE) -C build/$@

# Installs whatever `sources` already built to its real runtime path (/var/qmail,
# /home/vpopmail, etc.) — each component's own Makefile does the actual `make install`,
# this target just makes the intent explicit and gives one thing to run after `make all`.
install: sources
	@echo "All components built. Each build/<component>/Makefile installs directly during"
	@echo "its own 'build' target (no separate DESTDIR/staging step at this layer yet)."

# ─── Not yet implemented — packaging comes after the source-build layer is verified ────────
rpms:
	@echo "RPM packaging not yet implemented — see QMAILTOASTER-SELF-HOST-PLAN.md Phase 3."
	@exit 1

debs:
	@echo "Debian packaging not yet implemented — see QMAILTOASTER-SELF-HOST-PLAN.md Phase 3."
	@exit 1

clean:
	@for c in $(COMPONENTS); do \
		$(MAKE) -C build/$$c clean 2>/dev/null || true; \
	done
	rm -rf sources/*.tar.gz sources/*.tgz
