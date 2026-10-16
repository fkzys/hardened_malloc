# Tests

## Overview

| File | Language | Framework | What it tests |
|------|----------|-----------|---------------|
| `tests/test.sh` | Bash + C (compiled inline) | Custom assertions | Library structure (shared object type, exported symbols `prlimit`/`prlimit64`/`setrlimit`/`setrlimit64`, LD_PRELOAD loadability), RLIMIT_AS interception (all four entry points blocked, getrlimit reflects no change, RLIMIT_NOFILE passthrough), sanity without shim (raw `SYS_prlimit64` syscall applies normally bypassing any LD_PRELOAD interposition) |

## Running

```bash
# Build first (compiles hardened_malloc + libfake_rlimit.so)
make build

# Run tests
bash tests/test.sh

# With tracing
bash -x tests/test.sh
```

## How they work

### Test harness

The test script provides a minimal assertion framework:

- **Assertion functions**: `ok`/`fail`/`assert_eq`/`assert_contains`
- **Section headers**: `section` for grouping related tests
- **Summary**: final pass/fail counts; exits non-zero if any test failed

### Pre-flight

The script checks that `./libfake_rlimit.so` exists, then creates a temporary directory (`mktemp -d`) for compiling inline C test programs. The temporary directory is cleaned up via `trap EXIT`.

### Library structure

Validates the built shared object without executing application logic:

- **File type**: uses `file` to confirm the output is a shared object (ELF shared library)
- **Exported symbols**: uses `nm -D` to verify that `prlimit`, `prlimit64`, `setrlimit` and `setrlimit64` are exported — these are the libc functions the shim interposes
- **LD_PRELOAD loading**: runs `/bin/true` with `LD_PRELOAD=./libfake_rlimit.so` to confirm the library loads without errors (no missing symbols, no constructor crashes)

### RLIMIT_AS interception

Compiles and runs an inline C program (`test_shim.c`) under `LD_PRELOAD` that:

1. Calls `setrlimit`, `setrlimit64`, `prlimit` and `prlimit64` with `RLIMIT_AS` — each should return success (intercepted, silently ignored)
2. Calls `getrlimit(RLIMIT_AS, ...)` — the limit should **not** be applied (confirming the shim blocked the actual syscall)
3. Calls `prlimit(RLIMIT_AS, ...)` with a non-null `old_limit` — the reported value should be the real (unchanged) limit
4. Calls `setrlimit`, `setrlimit64`, `prlimit` and `prlimit64` with `RLIMIT_NOFILE` — should succeed and actually apply (passthrough for non-`RLIMIT_AS` resources)

The test uses distinct exit codes to pinpoint which step failed.

### Sanity without shim

Compiles and runs an inline C program (`test_no_shim.c`) **without** `LD_PRELOAD` that uses raw `syscall(SYS_prlimit64, ...)` to:

1. Read the current `RLIMIT_AS` value
2. Set it to 1 GiB via the raw syscall (bypasses any shim)
3. Read back and verify the limit was applied
4. Restore the original value

This confirms that the kernel syscall works normally when the shim is not interposed. The raw syscall approach also handles the edge case where the shim is loaded globally via `/etc/ld.so.preload` — `syscall(SYS_prlimit64, ...)` goes directly to the kernel, bypassing any symbol interposition.

Returns `APPLIED` on success, `SKIP` if the syscall is denied (e.g., seccomp), or `UNEXPECTED` if the value didn't stick.

## CI

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs on push/PR when `verify-lib.c`, `Makefile`, `tests/**`, or the workflow file itself changes:

- **`lint`** job: runs `cppcheck` with `--error-exitcode=1` for warnings, style, and performance checks on `verify-lib.c`
- **`test`** job: compiles via `make build`, then runs the test script twice — once as the regular CI user, once as root via `sudo`

## Test environment

- Bash tests create a temporary directory (`mktemp -d`) cleaned up via `trap EXIT`
- Inline C programs are compiled with `gcc` during the test run (requires a C compiler)
- No root privileges required
- No system resource limits are permanently modified (the sanity test restores original values)
- The shim library is loaded via `LD_PRELOAD` only in the test child process
