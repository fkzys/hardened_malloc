#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/resource.h>

/* LD_PRELOAD shim making RLIMIT_AS changes a no-op: glycin (GTK4) limits its
 * loader processes' address space, which breaks hardened_malloc's guard regions. */

typedef int (*prlimit64_fn)(__pid_t, enum __rlimit_resource,
                            const struct rlimit64 *, struct rlimit64 *);
typedef int (*prlimit_fn)(__pid_t, enum __rlimit_resource,
                          const struct rlimit *, struct rlimit *);
typedef int (*setrlimit_fn)(__rlimit_resource_t, const struct rlimit *);
typedef int (*setrlimit64_fn)(__rlimit_resource_t, const struct rlimit64 *);

/* memcpy because ISO C forbids casting dlsym's void* to a function pointer; a
 * missing symbol is fatal, so bail out rather than call through NULL. */
static void resolve_next(const char *symbol, void *out, size_t out_size) {
    void *fn = dlsym(RTLD_NEXT, symbol);
    if (fn == NULL) {
        static const char prefix[] = "libfake_rlimit: cannot resolve ";
        write(STDERR_FILENO, prefix, sizeof(prefix) - 1);
        write(STDERR_FILENO, symbol, strlen(symbol));
        write(STDERR_FILENO, "\n", 1);
        abort();
    }
    memcpy(out, &fn, out_size < sizeof(fn) ? out_size : sizeof(fn));
}

/* Resolved lazily and published atomically; racing threads only ever store the
 * same pointer, since dlsym is idempotent. */
static prlimit64_fn get_real_prlimit64(void) {
    static prlimit64_fn real;
    prlimit64_fn fn = __atomic_load_n(&real, __ATOMIC_ACQUIRE);
    if (fn == NULL) {
        resolve_next("prlimit64", &fn, sizeof(fn));
        __atomic_store_n(&real, fn, __ATOMIC_RELEASE);
    }
    return fn;
}

static prlimit_fn get_real_prlimit(void) {
    static prlimit_fn real;
    prlimit_fn fn = __atomic_load_n(&real, __ATOMIC_ACQUIRE);
    if (fn == NULL) {
        resolve_next("prlimit", &fn, sizeof(fn));
        __atomic_store_n(&real, fn, __ATOMIC_RELEASE);
    }
    return fn;
}

static setrlimit_fn get_real_setrlimit(void) {
    static setrlimit_fn real;
    setrlimit_fn fn = __atomic_load_n(&real, __ATOMIC_ACQUIRE);
    if (fn == NULL) {
        resolve_next("setrlimit", &fn, sizeof(fn));
        __atomic_store_n(&real, fn, __ATOMIC_RELEASE);
    }
    return fn;
}

static setrlimit64_fn get_real_setrlimit64(void) {
    static setrlimit64_fn real;
    setrlimit64_fn fn = __atomic_load_n(&real, __ATOMIC_ACQUIRE);
    if (fn == NULL) {
        resolve_next("setrlimit64", &fn, sizeof(fn));
        __atomic_store_n(&real, fn, __ATOMIC_RELEASE);
    }
    return fn;
}

int prlimit64(__pid_t pid, enum __rlimit_resource resource,
              const struct rlimit64 *new_limit, struct rlimit64 *old_limit) {
    if (resource == RLIMIT_AS && new_limit != NULL) {
        if (old_limit)
            return get_real_prlimit64()(pid, resource, NULL, old_limit);
        return 0;
    }
    return get_real_prlimit64()(pid, resource, new_limit, old_limit);
}

int prlimit(__pid_t pid, enum __rlimit_resource resource,
            const struct rlimit *new_limit, struct rlimit *old_limit) {
    if (resource == RLIMIT_AS && new_limit != NULL) {
        if (old_limit)
            return get_real_prlimit()(pid, resource, NULL, old_limit);
        return 0;
    }
    return get_real_prlimit()(pid, resource, new_limit, old_limit);
}

int setrlimit(__rlimit_resource_t resource, const struct rlimit *rlim) {
    if (resource == RLIMIT_AS)
        return 0;
    return get_real_setrlimit()(resource, rlim);
}

int setrlimit64(__rlimit_resource_t resource, const struct rlimit64 *rlim) {
    if (resource == RLIMIT_AS)
        return 0;
    return get_real_setrlimit64()(resource, rlim);
}
