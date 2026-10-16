TAG        := 2026100600
UPSTREAM   := https://github.com/GrapheneOS/hardened_malloc.git
NPROC      := $(shell nproc)
DESTDIR    ?=
PREFIX     := /usr
SYSCONFDIR := /etc
SRCDIR     := hardened_malloc

.PHONY: build test check-upstream install uninstall clean

build: libfake_rlimit.so
	git clone --depth 1 --branch $(TAG) \
		https://github.com/GrapheneOS/hardened_malloc.git $(SRCDIR)
	$(MAKE) -C $(SRCDIR) -j$(NPROC)
	$(MAKE) -C $(SRCDIR) -j$(NPROC) VARIANT=light

test: libfake_rlimit.so
	bash tests/test.sh

libfake_rlimit.so: fake_rlimit.c
	gcc -shared -fPIC -O2 -Wall -Wextra -Werror -o $@ $< -ldl

check-upstream:
	@git ls-remote --tags $(UPSTREAM) \
		| sed -n 's|.*refs/tags/\([0-9]\{10\}\)$$|\1|p' \
		| sort -n \
		| tail -5

install:
	install -Dm644 $(SRCDIR)/out/libhardened_malloc.so \
		$(DESTDIR)$(PREFIX)/lib/libhardened_malloc.so
	install -Dm644 $(SRCDIR)/out-light/libhardened_malloc-light.so \
		$(DESTDIR)$(PREFIX)/lib/libhardened_malloc-light.so
	install -Dm644 libfake_rlimit.so \
		$(DESTDIR)$(PREFIX)/lib/libfake_rlimit.so
	install -Dm644 ld.so.preload \
		$(DESTDIR)$(SYSCONFDIR)/ld.so.preload
	install -Dm644 sysctl.d/20-hardened-malloc.conf \
		$(DESTDIR)$(SYSCONFDIR)/sysctl.d/20-hardened-malloc.conf
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/hardened_malloc/LICENSE

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/lib/libhardened_malloc.so
	rm -f $(DESTDIR)$(PREFIX)/lib/libhardened_malloc-light.so
	rm -f $(DESTDIR)$(PREFIX)/lib/libfake_rlimit.so
	rm -f $(DESTDIR)$(SYSCONFDIR)/ld.so.preload
	rm -f $(DESTDIR)$(SYSCONFDIR)/sysctl.d/20-hardened-malloc.conf
	rm -rf $(DESTDIR)$(PREFIX)/share/licenses/hardened_malloc/
	@echo "Note: run 'sysctl --system' to reload defaults."

clean:
	rm -rf $(SRCDIR) libfake_rlimit.so
