/*
 * koofr-tray-fix: stop Koofr Desktop from re-announcing the same tray icon
 * every second.
 *
 * Koofr's GUI (storagegui, Go, closed source) loads libappindicator3 with
 * dlopen and, once a second, writes its icon to a new temp file
 * (/tmp/systray_XXXXXX) and passes that path to
 * app_indicator_set_icon_full() and app_indicator_set_attention_icon_full().
 * The image is the same each time, but the path is new, so every tray host
 * gets NewIcon + NewAttentionIcon and re-reads the item once a second. Some
 * hosts (Noctalia, see noctalia-dev/noctalia#4537) rebuild the whole tray on
 * each change, so hover and clicks on every tray icon break.
 *
 * Loaded with LD_PRELOAD, this library wraps dlsym(): when Koofr asks for
 * those two functions it gets a wrapper that reads the icon file, and
 *   - if the image is the same as the last one set, does nothing;
 *   - if it changed, copies it to a stable file named after its content in
 *     $XDG_RUNTIME_DIR/koofr-tray-fix/ and passes that path on (Koofr
 *     deletes its temp files, so the indicator must not point at them).
 * Icon theme names (not absolute paths) are passed through, deduplicated by
 * name. Everything else goes to the real dlsym untouched.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef void (*set_icon_fn)(void *indicator, const char *icon, const char *desc);

static void *(*real_dlsym)(void *, const char *);
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

struct slot {
    set_icon_fn real;
    uint64_t last_hash;      /* 0: nothing set yet */
    char last_path[512];     /* stable copy currently set */
};
static struct slot icon_slot, attention_slot;

static void resolve_real_dlsym(void) {
    if (real_dlsym)
        return;
    real_dlsym = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.34");
    if (!real_dlsym)
        real_dlsym = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
}

static uint64_t fnv1a(const unsigned char *p, size_t n, uint64_t h) {
    for (size_t i = 0; i < n; i++) {
        h ^= p[i];
        h *= 0x100000001b3ULL;
    }
    return h;
}

/* Reads a whole small file; returns its size or -1. */
static ssize_t read_file(const char *path, unsigned char *buf, size_t cap) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return -1;
    size_t got = 0;
    while (got < cap) {
        ssize_t r = read(fd, buf + got, cap - got);
        if (r < 0 && errno == EINTR)
            continue;
        if (r <= 0)
            break;
        got += (size_t)r;
    }
    close(fd);
    return (ssize_t)got;
}

static int write_file(const char *path, const unsigned char *buf, size_t n) {
    char tmp[600];
    snprintf(tmp, sizeof tmp, "%s.tmp", path);
    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (fd < 0)
        return -1;
    size_t done = 0;
    while (done < n) {
        ssize_t w = write(fd, buf + done, n - done);
        if (w < 0 && errno == EINTR)
            continue;
        if (w <= 0) {
            close(fd);
            unlink(tmp);
            return -1;
        }
        done += (size_t)w;
    }
    close(fd);
    return rename(tmp, path);
}

static void filtered_set(struct slot *s, void *indicator, const char *icon, const char *desc) {
    if (!s->real)
        return;
    if (!icon || icon[0] != '/') {
        /* An icon theme name: pass it on only when it changes. */
        uint64_t h = fnv1a((const unsigned char *)(icon ? icon : ""), icon ? strlen(icon) : 0,
                           0xcbf29ce484222325ULL) | 1;
        pthread_mutex_lock(&lock);
        int same = (h == s->last_hash);
        s->last_hash = h;
        pthread_mutex_unlock(&lock);
        if (!same)
            s->real(indicator, icon, desc);
        return;
    }

    static unsigned char buf[1 << 20];   /* tray icons are a few KB */
    pthread_mutex_lock(&lock);
    ssize_t n = read_file(icon, buf, sizeof buf);
    if (n <= 0) {
        pthread_mutex_unlock(&lock);
        s->real(indicator, icon, desc);  /* cannot read it: do what Koofr asked */
        return;
    }
    uint64_t h = fnv1a(buf, (size_t)n, 0xcbf29ce484222325ULL) | 1;
    if (h == s->last_hash) {
        pthread_mutex_unlock(&lock);
        return;                          /* same image: nothing to announce */
    }

    const char *rt = getenv("XDG_RUNTIME_DIR");
    char dir[400], path[512];
    snprintf(dir, sizeof dir, "%s/koofr-tray-fix", rt && rt[0] ? rt : "/tmp");
    mkdir(dir, 0700);
    snprintf(path, sizeof path, "%s/%016llx.png", dir, (unsigned long long)h);
    const char *use = icon;
    if (access(path, R_OK) == 0 || write_file(path, buf, (size_t)n) == 0)
        use = path;

    char previous[512];
    snprintf(previous, sizeof previous, "%s", s->last_path);
    s->last_hash = h;
    snprintf(s->last_path, sizeof s->last_path, "%s", use == path ? path : "");
    pthread_mutex_unlock(&lock);

    s->real(indicator, use, desc);

    /* Drop the previous copy unless the other slot still shows it. */
    pthread_mutex_lock(&lock);
    if (previous[0] && strcmp(previous, icon_slot.last_path) != 0
            && strcmp(previous, attention_slot.last_path) != 0)
        unlink(previous);
    pthread_mutex_unlock(&lock);
}

static void wrap_set_icon_full(void *indicator, const char *icon, const char *desc) {
    filtered_set(&icon_slot, indicator, icon, desc);
}

static void wrap_set_attention_icon_full(void *indicator, const char *icon, const char *desc) {
    filtered_set(&attention_slot, indicator, icon, desc);
}

void *dlsym(void *handle, const char *name) {
    resolve_real_dlsym();
    void *p = real_dlsym ? real_dlsym(handle, name) : NULL;
    if (!p)
        return p;
    if (strcmp(name, "app_indicator_set_icon_full") == 0) {
        icon_slot.real = (set_icon_fn)p;
        return (void *)wrap_set_icon_full;
    }
    if (strcmp(name, "app_indicator_set_attention_icon_full") == 0) {
        attention_slot.real = (set_icon_fn)p;
        return (void *)wrap_set_attention_icon_full;
    }
    return p;
}
