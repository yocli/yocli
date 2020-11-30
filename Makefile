PREFIX ?= /usr
DESTDIR ?=
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib
# MANDIR ?= $(PREFIX)/share/man

PROGNAME ?= yo-cli
BINNAME ?= yo

PLATFORMFILE := src/platform/$(shell uname | cut -d _ -f 1 | tr '[:upper:]' '[:lower:]').sh

all:
	@echo "Password store is a shell script, so there is nothing to do. Try \"make install\" instead."

# install-common:
# 	@install -v -d "$(DESTDIR)$(MANDIR)/man1" && install -m 0644 -v man/$(BINNAME).1 "$(DESTDIR)$(MANDIR)/man1/$(BINNAME).1"


ifneq ($(strip $(wildcard $(PLATFORMFILE))),)
install: # install-common
	@install -v -d "$(DESTDIR)$(LIBDIR)/$(PROGNAME)" && install -m 0644 -v "$(PLATFORMFILE)" "$(DESTDIR)$(LIBDIR)/$(PROGNAME)/platform.sh"
	@install -v -d "$(DESTDIR)$(LIBDIR)/$(PROGNAME)/extensions"
	@install -v -d "$(DESTDIR)$(BINDIR)/"
	@trap 'rm -f src/.$(BINNAME)' EXIT; sed 's:.*PLATFORM_FUNCTION_FILE.*:source "$(LIBDIR)/$(PROGNAME)/platform.sh":;s:^SYSTEM_EXTENSION_DIR=.*:SYSTEM_EXTENSION_DIR="$(LIBDIR)/$(PROGNAME)/extensions":' src/$(PROGNAME).sh > src/.$(BINNAME) && \
	install -v -d "$(DESTDIR)$(BINDIR)/" && install -m 0755 -v src/.$(BINNAME) "$(DESTDIR)$(BINDIR)/$(BINNAME)"
else
install: # install-common
	@install -v -d "$(DESTDIR)$(LIBDIR)/$(PROGNAME)/extensions"
	@trap 'rm -f src/.$(BINNAME)' EXIT; sed '/PLATFORM_FUNCTION_FILE/d;s:^SYSTEM_EXTENSION_DIR=.*:SYSTEM_EXTENSION_DIR="$(LIBDIR)/$(PROGNAME)/extensions":' src/$(PROGNAME).sh > src/.$(BINNAME) && \
	install -v -d "$(DESTDIR)$(BINDIR)/" && install -m 0755 -v src/.$(BINNAME) "$(DESTDIR)$(BINDIR)/$(BINNAME)"
endif

uninstall:
	@rm -vrf \
		"$(DESTDIR)$(BINDIR)/$(BINNAME)" \
		"$(DESTDIR)$(LIBDIR)/$(PROGNAME)" \
		\ # "$(DESTDIR)$(MANDIR)/man1/$(BINNAME).1"
		"$(DESTDIR)$(BASHCOMPDIR)/$(BINNAME)" \
		"$(DESTDIR)$(ZSHCOMPDIR)/_$(BINNAME)" \
		"$(DESTDIR)$(FISHCOMPDIR)/$(BINNAME).fish"

TESTS = $(sort $(wildcard tests/t[0-9][0-9][0-9][0-9]-*.sh))

test: $(TESTS)

$(TESTS):
	@$@ $(PASS_TEST_OPTS)

clean:
	$(RM) -rf tests/test-results/ tests/trash\ directory.*/ tests/gnupg/random_seed

.PHONY: install uninstall install-common test clean $(TESTS)
