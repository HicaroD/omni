#define _DARWIN_C_SOURCE
#include "platform.h"
#include <crt_externs.h>
#include <errno.h>
#include <fcntl.h>
#include <locale.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <wchar.h>

uint64_t omni_argc(void) { return (uint64_t)*_NSGetArgc(); }
const char *omni_arg(uint64_t i) { return i < omni_argc() ? (*_NSGetArgv())[i] : ""; }
int32_t omni_root(const char *path) { return chdir(path); }
void omni_locale(void) { setlocale(LC_CTYPE, ""); }
int32_t omni_width(uint32_t cp) { return wcwidth((wchar_t)cp); }
uint8_t omni_byte(const char *s, uint64_t i) { return (uint8_t)s[i]; }
const char *omni_cview(void *p) { return p; }

int32_t omni_path(const char *path, void **resolved) {
    char *full = realpath(path, NULL);
    if (full) { *resolved = full; return 0; }
    if (errno != ENOENT || !*path) return -1;
    char *copy = strdup(path);
    if (!copy) return -1;
    char *slash = strrchr(copy, '/');
    const char *base = slash ? slash + 1 : copy;
    if (!*base || !strcmp(base, ".") || !strcmp(base, "..")) { free(copy); return -1; }
    char *parent;
    if (slash) { *slash = 0; parent = realpath(*copy ? copy : "/", NULL); }
    else parent = realpath(".", NULL);
    if (!parent) { free(copy); return -1; }
    size_t n = strlen(parent) + strlen(base) + 2;
    full = malloc(n);
    if (full) snprintf(full, n, "%s/%s", parent, base);
    free(parent); free(copy);
    if (!full) return -1;
    *resolved = full;
    return 0;
}
uint64_t omni_stamp(const char *path) {
    struct stat st;
    if (stat(path, &st)) return 0;
    uint64_t result = (uint64_t)st.st_ino ^ ((uint64_t)st.st_size << 17);
    result ^= (uint64_t)st.st_mtimespec.tv_sec * 1000000007u;
    result ^= (uint64_t)st.st_mtimespec.tv_nsec;
    return result ? result : 1;
}

static int read_file(FILE *f, void **data, uint64_t *length) {
    size_t n = 0, cap = 8192;
    unsigned char *p = malloc(cap);
    if (!p) return -1;
    for (;;) {
        if (n == cap) {
            if (cap > SIZE_MAX / 2) { free(p); return -1; }
            cap *= 2;
            void *q = realloc(p, cap);
            if (!q) { free(p); return -1; }
            p = q;
        }
        size_t got = fread(p + n, 1, cap - n, f);
        n += got;
        if (!got) break;
    }
    if (ferror(f)) { free(p); return -1; }
    *data = p; *length = n;
    return 0;
}
int32_t omni_load(const char *path, void **data, uint64_t *length) {
    FILE *f = fopen(path, "rb");
    if (!f) return errno == ENOENT ? 1 : -1;
    struct stat st;
    if (fstat(fileno(f), &st) || !S_ISREG(st.st_mode)) { fclose(f); return -1; }
    int result = read_file(f, data, length);
    fclose(f);
    return result;
}
int32_t omni_preview(const char *path, void **data, uint64_t *length) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    struct stat st;
    if (fstat(fileno(f), &st) || !S_ISREG(st.st_mode)) { fclose(f); return -1; }
    void *p = malloc(1048576);
    if (!p) { fclose(f); return -1; }
    size_t n = fread(p, 1, 1048576, f);
    bool failed = ferror(f);
    fclose(f);
    if (failed) { free(p); return -1; }
    *data = p; *length = n;
    return 0;
}
/* Refuse symlinks rather than replacing their link. Preserve existing permissions.
   A same-directory temporary plus rename prevents truncation on failed writes. */
int32_t omni_save(const char *path, void *data, uint64_t length) {
    struct stat st;
    int exists = lstat(path, &st) == 0;
    if (exists && !S_ISREG(st.st_mode)) return -1;
    size_t n = strlen(path);
    char *temp = malloc(n + 16);
    if (!temp) return -1;
    snprintf(temp, n + 16, "%s.omni-XXXXXX", path);
    int fd = mkstemp(temp), result = -1;
    if (fd < 0) { free(temp); return -1; }
    mode_t mask = umask(0); umask(mask);
    if (fchmod(fd, exists ? (st.st_mode & 0777) : (0666 & ~mask))) goto done;
    uint64_t at = 0;
    while (at < length) {
        ssize_t wrote = write(fd, (char *)data + at, length - at);
        if (wrote < 0 && errno == EINTR) continue;
        if (wrote <= 0) goto done;
        at += (uint64_t)wrote;
    }
    if (fsync(fd)) goto done;
    if (close(fd)) { fd = -1; goto done; }
    fd = -1;
    if (rename(temp, path)) goto done;
    result = 0;
done:
    if (fd >= 0) close(fd);
    if (result) unlink(temp);
    free(temp);
    return result;
}

typedef struct { pid_t pid; int fd; } Process;
int32_t omni_spawn(int32_t kind, const char *query, bool hidden, bool ignored, bool regex, void **out) {
    int p[2];
    if (pipe(p)) return -1;
    Process *process = malloc(sizeof(*process));
    if (!process) { close(p[0]); close(p[1]); return -1; }
    pid_t pid = fork();
    if (pid < 0) { close(p[0]); close(p[1]); free(process); return -1; }
    if (!pid) {
        dup2(p[1], STDOUT_FILENO);
        int null = open("/dev/null", O_WRONLY);
        if (null >= 0) dup2(null, STDERR_FILENO);
        close(p[0]); close(p[1]);
        if (kind == 0) {
            const char *args[12]; int i = 0;
            args[i++] = "rg"; args[i++] = "--files"; args[i++] = "-0";
            if (hidden) args[i++] = "--hidden";
            if (ignored) args[i++] = "--no-ignore";
            args[i++] = "-g"; args[i++] = "!.git"; args[i] = NULL;
            execvp("rg", (char *const *)args);
        } else {
            const char *args[20]; int i = 0;
            args[i++] = "rg"; args[i++] = "--line-number"; args[i++] = "--column";
            args[i++] = "--no-heading"; args[i++] = "--color=never"; args[i++] = "--smart-case"; args[i++] = "--null";
            if (!regex) args[i++] = "--fixed-strings";
            if (ignored) args[i++] = "--no-ignore";
            if (hidden) { args[i++] = "--hidden"; args[i++] = "-g"; args[i++] = "!.git"; }
            args[i++] = "--"; args[i++] = query; args[i++] = "."; args[i] = NULL;
            execvp("rg", (char *const *)args);
        }
        _exit(127);
    }
    close(p[1]);
    if (fcntl(p[0], F_SETFL, O_NONBLOCK) < 0 || fcntl(p[0], F_SETFD, FD_CLOEXEC) < 0) {
        close(p[0]); kill(pid, SIGKILL);
        while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {}
        free(process); return -1;
    }
    process->pid = pid; process->fd = p[0]; *out = process;
    return 0;
}
int32_t omni_poll(void *handle, void *buffer, uint64_t capacity, uint64_t *count) {
    Process *p = handle;
    ssize_t n = read(p->fd, buffer, capacity);
    *count = n > 0 ? (uint64_t)n : 0;
    if (n > 0 || (n < 0 && (errno == EAGAIN || errno == EINTR))) return 0;
    int status = 0;
    pid_t waited;
    do { waited = waitpid(p->pid, &status, WNOHANG); } while (waited < 0 && errno == EINTR);
    if (!waited) return 0;
    p->pid = 0;
    if (waited < 0) return -1;
    return WIFEXITED(status) && WEXITSTATUS(status) <= 1 ? 1 : -1;
}
void omni_cancel(void *handle) {
    if (!handle) return;
    Process *p = handle;
    close(p->fd);
    if (p->pid > 0) { kill(p->pid, SIGKILL); while (waitpid(p->pid, NULL, 0) < 0 && errno == EINTR) {} }
    free(p);
}
int32_t omni_copy(void *data, uint64_t length) {
    FILE *f = tmpfile();
    if (!f) return -1;
    if (fwrite(data, 1, length, f) != length || fflush(f) || fseek(f, 0, SEEK_SET)) { fclose(f); return -1; }
    pid_t child = fork();
    if (!child) {
        dup2(fileno(f), STDIN_FILENO);
        execlp("pbcopy", "pbcopy", (char *)0);
        _exit(127);
    }
    int status = 0;
    pid_t waited;
    do { waited = child > 0 ? waitpid(child, &status, 0) : -1; } while (waited < 0 && errno == EINTR);
    fclose(f);
    return waited > 0 && WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : -1;
}
int32_t omni_paste(void **data, uint64_t *length) {
    FILE *p = popen("pbpaste", "r");
    if (!p) return -1;
    int result = read_file(p, data, length);
    int status = pclose(p);
    if (!result && status) { free(*data); *data = NULL; *length = 0; return -1; }
    return result;
}
