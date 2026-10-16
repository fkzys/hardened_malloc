#!/usr/bin/env bash
# tests/test.sh — Unit tests for libfake_rlimit.so
# Run from project root: bash tests/test.sh

set -uo pipefail

LIB=./libfake_rlimit.so
PASS=0; FAIL=0; TESTS=0

# ── Test helpers ─────────────────────────────────────────────

ok()   { PASS=$((PASS+1)); TESTS=$((TESTS+1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL+1)); TESTS=$((TESTS+1)); echo "  ✗ $1"; }
section() { echo ""; echo "── $1 ──"; }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        ok "$desc"
    else
        fail "$desc (expected='$expected', got='$actual')"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        ok "$desc"
    else
        fail "$desc ('$needle' not found)"
    fi
}

# End-of-line anchored so "prlimit" does not spuriously match "prlimit64".
assert_export() {
    local sym="$1"
    if nm -D "$LIB" 2>/dev/null | grep -qE "[[:space:]]${sym}\$"; then
        ok "exports ${sym}"
    else
        fail "exports ${sym} (not found in nm -D)"
    fi
}

summary() {
    echo ""
    echo "════════════════════════════════════"
    echo " ${0##*/}: ${PASS} passed, ${FAIL} failed (${TESTS})"
    echo "════════════════════════════════════"
    [[ $FAIL -eq 0 ]]
}

# ── Pre-flight ───────────────────────────────────────────────

if [[ ! -f "$LIB" ]]; then
    echo "Error: $LIB not found — run 'make' first"
    exit 1
fi

TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT


# ── Library structure ────────────────────────────────────────

section "Library structure"

_type=$(file "$LIB" 2>/dev/null || true)
assert_contains "is a shared object" "shared object" "$_type"

assert_export "prlimit"
assert_export "prlimit64"
assert_export "setrlimit"
assert_export "setrlimit64"

_rc=0
LD_PRELOAD="$LIB" /bin/true 2>/dev/null || _rc=$?
assert_eq "loads via LD_PRELOAD" "0" "$_rc"


# ── RLIMIT_AS interception ──────────────────────────────────

section "RLIMIT_AS interception"

cat > "${TESTDIR}/test_shim.c" << 'EOF'
#define _GNU_SOURCE
#include <stddef.h>
#include <sys/resource.h>

int main(void) {
    struct rlimit rl = { .rlim_cur = 1024, .rlim_max = 1024 };
    struct rlimit64 rl64 = { .rlim_cur = 1024, .rlim_max = 1024 };
    struct rlimit check;
    struct rlimit old;

    if (setrlimit(RLIMIT_AS, &rl) != 0) return 1;
    if (setrlimit64(RLIMIT_AS, &rl64) != 0) return 4;
    if (prlimit(0, RLIMIT_AS, &rl, NULL) != 0) return 5;
    if (prlimit64(0, RLIMIT_AS, &rl64, NULL) != 0) return 6;

    getrlimit(RLIMIT_AS, &check);
    if (check.rlim_cur == 1024) return 2;

    if (prlimit(0, RLIMIT_AS, &rl, &old) != 0) return 7;
    if (old.rlim_cur == 1024) return 8;

    struct rlimit rl_no = { .rlim_cur = 512, .rlim_max = 512 };
    struct rlimit64 rl64_no = { .rlim_cur = 512, .rlim_max = 512 };
    if (setrlimit(RLIMIT_NOFILE, &rl_no) != 0) return 3;
    if (setrlimit64(RLIMIT_NOFILE, &rl64_no) != 0) return 9;
    getrlimit(RLIMIT_NOFILE, &check);
    if (check.rlim_cur != 512) return 10;
    if (prlimit(0, RLIMIT_NOFILE, &rl_no, NULL) != 0) return 11;
    if (prlimit64(0, RLIMIT_NOFILE, &rl64_no, NULL) != 0) return 12;

    return 0;
}
EOF

gcc -o "${TESTDIR}/test_shim" "${TESTDIR}/test_shim.c"

_rc=0
LD_PRELOAD="$(realpath "$LIB")" "${TESTDIR}/test_shim" >/dev/null 2>&1 || _rc=$?

case $_rc in
    0)  ok   "RLIMIT_AS blocked on all entry points, other resources passed through" ;;
    1)  fail "setrlimit(RLIMIT_AS) not intercepted (rc=1)" ;;
    2)  fail "RLIMIT_AS was applied despite shim (rc=2)" ;;
    3)  fail "RLIMIT_NOFILE passthrough broken via setrlimit (rc=3)" ;;
    4)  fail "setrlimit64(RLIMIT_AS) not intercepted (rc=4)" ;;
    5)  fail "prlimit(RLIMIT_AS) not intercepted (rc=5)" ;;
    6)  fail "prlimit64(RLIMIT_AS) not intercepted (rc=6)" ;;
    7)  fail "prlimit(RLIMIT_AS, old_limit) call failed (rc=7)" ;;
    8)  fail "prlimit(RLIMIT_AS, old_limit) did not report real limit (rc=8)" ;;
    9)  fail "RLIMIT_NOFILE passthrough broken via setrlimit64 (rc=9)" ;;
    10) fail "RLIMIT_NOFILE not applied via setrlimit64 (rc=10)" ;;
    11) fail "RLIMIT_NOFILE passthrough broken via prlimit (rc=11)" ;;
    12) fail "RLIMIT_NOFILE passthrough broken via prlimit64 (rc=12)" ;;
    *)  fail "shim test crashed (rc=$_rc)" ;;
esac


# ── Sanity: without shim ────────────────────────────────────

section "Sanity (without shim)"

# The shim may be loaded globally via /etc/ld.so.preload, so libc wrappers
# (setrlimit, setrlimit64, prlimit, prlimit64) are intercepted even here.
# Use syscall(SYS_prlimit64, ...) directly — goes straight to the kernel,
# bypassing any LD_PRELOAD symbol interposition.
cat > "${TESTDIR}/test_no_shim.c" << 'EOF'
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/resource.h>

/* Matches kernel's prlimit64 layout — 64-bit fields on all arches */
struct krlimit64 {
    unsigned long long rlim_cur;
    unsigned long long rlim_max;
};

int main(void) {
    struct krlimit64 before, rl, after;

    /* Raw syscall bypasses any shim */
    syscall(SYS_prlimit64, 0, RLIMIT_AS, (void *)0, &before);

    rl.rlim_cur = 1073741824ULL;   /* 1 GiB */
    rl.rlim_max = before.rlim_max; /* keep max unchanged */

    if (syscall(SYS_prlimit64, 0, RLIMIT_AS, &rl, (void *)0) != 0) {
        write(1, "SKIP", 4);
        return 0;
    }

    syscall(SYS_prlimit64, 0, RLIMIT_AS, (void *)0, &after);
    /* Restore */
    syscall(SYS_prlimit64, 0, RLIMIT_AS, &before, (void *)0);

    if (after.rlim_cur == 1073741824ULL)
        write(1, "APPLIED", 7);
    else
        write(1, "UNEXPECTED", 10);

    return 0;
}
EOF

gcc -o "${TESTDIR}/test_no_shim" "${TESTDIR}/test_no_shim.c"

_rc=0
_result=$("${TESTDIR}/test_no_shim" 2>/dev/null) || _rc=$?

if [[ "$_result" == "APPLIED" || "$_result" == "SKIP" ]]; then
    ok "raw prlimit64 syscall applies normally ($_result)"
else
    fail "raw prlimit64 syscall applies normally (rc=$_rc, got='$_result')"
fi


# ── Summary ──────────────────────────────────────────────────

summary
