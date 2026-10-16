# hardened\_malloc

[![CI](https://github.com/fkzys/hardened_malloc/actions/workflows/ci.yml/badge.svg)](https://github.com/fkzys/hardened_malloc/actions/workflows/ci.yml)
![License](https://img.shields.io/github/license/fkzys/hardened_malloc)
[![Spec](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/fkzys/specs/refs/heads/main/version.json&maxAge=300)](https://github.com/fkzys/specs)

GrapheneOS [hardened\_malloc](https://github.com/GrapheneOS/hardened_malloc) — packaged for system-wide preloading on Linux.

Builds both variants from source, plus a `libfake_rlimit.so` shim for GTK4/glycin compatibility.

## What gets installed

| File | Purpose |
|------|---------|
| `/usr/lib/libhardened_malloc.so` | Default variant — full hardening, for per-app use via bwrap `LD_PRELOAD` |
| `/usr/lib/libhardened_malloc-light.so` | Light variant — balanced, loaded system-wide via `/etc/ld.so.preload` |
| `/usr/lib/libfake_rlimit.so` | Intercepts `prlimit`/`prlimit64`/`setrlimit`/`setrlimit64` `RLIMIT_AS` calls to prevent crashes |
| `/etc/ld.so.preload` | Preloads `libfake_rlimit.so` + `libhardened_malloc-light.so` globally |
| `/etc/sysctl.d/20-hardened-malloc.conf` | `vm.max_map_count = 1048576` for guard slabs |

## Why fake\_rlimit

GTK4 uses [glycin](https://gitlab.gnome.org/GNOME/glycin) for image loading, which sets `RLIMIT_AS` on its sandboxed loader processes. This is incompatible with hardened\_malloc's large virtual memory reservation (~240 GB `PROT_NONE` guard regions). The shim intercepts the `prlimit`, `prlimit64`, `setrlimit` and `setrlimit64` `RLIMIT_AS` calls, returning success without applying the limit. All other resource limits are passed through unchanged.

## Compatibility

The light variant provides zero-on-free, slab canaries, and guard slabs. The default variant adds slot randomization, write-after-free checks, and slab quarantines.

Applications with custom allocators (Chromium/PartitionAlloc, Firefox/mozjemalloc) are incompatible and must have hardened\_malloc disabled in their bwrap wrappers via `--ro-bind /dev/null /etc/ld.so.preload`. See [dotfiles](https://github.com/fkzys/dotfiles) for per-app configuration.

To use the default (stricter) variant system-wide instead of light, edit `/etc/ld.so.preload`:

```
/usr/lib/libfake_rlimit.so
/usr/lib/libhardened_malloc.so
```

## Install

### With gitpkg

```sh
gitpkg install hardened_malloc
```

See [gitpkg](https://github.com/fkzys/gitpkg) for details.

### Manually

```sh
make build
sudo make install
```

## Uninstall

### With gitpkg

```sh
gitpkg remove hardened_malloc
```

### Manually

```sh
sudo make uninstall
```

## Updating

```bash
# Check latest tags
make check-upstream

# Update TAG in Makefile, commit, then:
gitpkg update hardened_malloc
# or manually:
make clean && make build && sudo make install
```

## Dependencies

- `base-devel` (`gcc`, `make`)
- `git`

## License

AGPL-3.0-or-later
