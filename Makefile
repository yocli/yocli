PREFIX ?= /usr
DESTDIR ?=
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib

PROGNAME ?= yo-cli
BINNAME ?= yo

PLATFORM ?= $(shell uname | cut -d _ -f 1 | tr '[:upper:]' '[:lower:]')
PLATFORMFILE := src/platform/$(PLATFORM).sh

print-%  : ; @echo $* = $($*)

all:
	@echo "Password store is a shell script, so there is nothing to do. Try \"make install\" instead."

ifneq ($(strip $(wildcard $(PLATFORMFILE))),)
install: # install-common
	@install -v -d "$(DESTDIR)$(LIBDIR)/$(PROGNAME)" && install -m 0644 -v "$(PLATFORMFILE)" "$(DESTDIR)$(LIBDIR)/$(PROGNAME)/platform.sh"
	@install -v -d "$(DESTDIR)$(BINDIR)/"
	@trap 'rm -f src/.$(BINNAME)' EXIT; sed 's:.*PLATFORM_FUNCTION_FILE.*:source "$(DESTDIR)$(LIBDIR)/$(PROGNAME)/platform.sh":' src/$(PROGNAME).sh > src/.$(BINNAME) && \
	install -v -d "$(DESTDIR)$(BINDIR)/" && install -m 0755 -v src/.$(BINNAME) "$(DESTDIR)$(BINDIR)/$(BINNAME)"
else
install: # install-common
	@trap 'rm -f src/.$(BINNAME)' EXIT; sed '/PLATFORM_FUNCTION_FILE/d' src/$(PROGNAME).sh > src/.$(BINNAME) && \
	install -v -d "$(DESTDIR)$(BINDIR)/" && install -m 0755 -v src/.$(BINNAME) "$(DESTDIR)$(BINDIR)/$(BINNAME)"
endif

uninstall:
	@rm -vrf \
		"$(DESTDIR)$(BINDIR)/$(BINNAME)" \
		"$(DESTDIR)$(LIBDIR)/$(PROGNAME)" \

.PHONY: all install uninstall
