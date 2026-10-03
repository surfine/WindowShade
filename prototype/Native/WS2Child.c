#define _GNU_SOURCE 1
#include "WS2Child.h"
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/wait.h>
#if defined(__APPLE__)
#include <libproc.h>
#endif

// All calls for an instance must use one serial executor. No global SIGCHLD handler.
// Keeping the leader unreaped until the last group signal pins its PID against reuse.
// A descendant that deliberately leaves the group is NOT covered by this contract.
struct WS2Child {
    pid_t pid;
    /// spawn 当时核对过的自有进程组号（== pid）；退出后 macOS 不再回答 getpgid，只能靠它。
    pid_t owned_group;
    int stopping;
    double kill_at;
    WS2ChildState state;
};
static double monotonic_seconds(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return -1;
    return (double)value.tv_sec + (double)value.tv_nsec / 1e9;
}
static void close_fd(int *fd) { if (*fd >= 0) { (void)close(*fd); *fd = -1; } }
static int pipe_cloexec(int pair[2]) {
    if (pipe(pair) != 0) return errno;
    for (int i = 0; i < 2; ++i) {
        if (pair[i] < 3) {
            int next = fcntl(pair[i], F_DUPFD_CLOEXEC, 3);
            if (next < 0) { int e = errno; close_fd(&pair[0]); close_fd(&pair[1]); return e; }
            close_fd(&pair[i]); pair[i] = next;
        }
        if (fcntl(pair[i], F_SETFD, FD_CLOEXEC) < 0) {
            int e = errno; close_fd(&pair[0]); close_fd(&pair[1]); return e;
        }
    }
    return 0;
}
static int nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL);
    return flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0 ? errno : 0;
}
int ws2_child_spawn(const char *executable, char *const argv[], char *const envp[],
                   const char *cwd, int capture_stderr, WS2Child **child,
                   int *stdin_fd, int *stdout_fd, int *stderr_fd) {
    if (!executable || executable[0] != '/' || !cwd || cwd[0] != '/' ||
        !argv || !argv[0] || !envp || !child || !stdin_fd || !stdout_fd || !stderr_fd) return EINVAL;
    *child = NULL; *stdin_fd = *stdout_fd = *stderr_fd = -1;
    int in[2] = {-1,-1}, out[2] = {-1,-1}, err[2] = {-1,-1}, nullfd = -1;
    int error = 0, actions_ready = 0, attrs_ready = 0;
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attrs;
    WS2Child *c = calloc(1, sizeof(*c));
    if (!c) return ENOMEM;
    if ((error = pipe_cloexec(in)) || (error = pipe_cloexec(out))) goto fail;
    if (capture_stderr) { if ((error = pipe_cloexec(err))) goto fail; }
    else { nullfd = open("/dev/null", O_WRONLY | O_CLOEXEC); if (nullfd < 0) { error = errno; goto fail; } }
    if ((error = nonblocking(in[1])) || (error = nonblocking(out[0])) ||
        (capture_stderr && (error = nonblocking(err[0])))) goto fail;
    if ((error = posix_spawn_file_actions_init(&actions))) goto fail;
    actions_ready = 1;
    if ((error = posix_spawnattr_init(&attrs))) goto fail;
    attrs_ready = 1;
    // Never change the app's global cwd. macOS 26 起 _np 版本被弃用、正式名字要求 26+：
    // 部署目标是 14，所以运行时用 @available 选路，旧路用 pragma 明确接受弃用（否则 -Werror 会挡）。
#if defined(__APPLE__)
    // 纯 C 用 __builtin_available（@available 只在 ObjC 里可用）。
    if (__builtin_available(macOS 26.0, *)) {
        error = posix_spawn_file_actions_addchdir(&actions, cwd);
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        error = posix_spawn_file_actions_addchdir_np(&actions, cwd);
#pragma clang diagnostic pop
    }
    if (error) goto fail;
#else
    if ((error = posix_spawn_file_actions_addchdir_np(&actions, cwd))) goto fail;
#endif
    if ((error = posix_spawn_file_actions_adddup2(&actions, in[0], STDIN_FILENO)) ||
        (error = posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO)) ||
        (error = posix_spawn_file_actions_adddup2(&actions, capture_stderr ? err[1] : nullfd, STDERR_FILENO))) goto fail;
    short flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF;
#if defined(__APPLE__)
    flags |= POSIX_SPAWN_CLOEXEC_DEFAULT;
#elif defined(__GLIBC__) && __GLIBC_PREREQ(2,34)
    if ((error = posix_spawn_file_actions_addclosefrom_np(&actions, 3))) goto fail;
#else
    // Fail rather than quietly inheriting unrelated descriptors on an unsupported libc.
    error = ENOTSUP; goto fail;
#endif
    sigset_t empty, defaults;
    sigemptyset(&empty); sigemptyset(&defaults);
    sigaddset(&defaults, SIGPIPE); sigaddset(&defaults, SIGTERM);
    sigaddset(&defaults, SIGINT); sigaddset(&defaults, SIGCHLD);
    if ((error = posix_spawnattr_setflags(&attrs, flags)) ||
        (error = posix_spawnattr_setpgroup(&attrs, 0)) ||
        (error = posix_spawnattr_setsigmask(&attrs, &empty)) ||
        (error = posix_spawnattr_setsigdefault(&attrs, &defaults))) goto fail;
    error = posix_spawn(&c->pid, executable, &actions, &attrs, argv, envp);
    if (error) goto fail;
    // POSIX_SPAWN_SETPGROUP with pgroup=0 establishes a group whose ID is the child PID.
    // 趁 leader 还活着核对并记下组号；退出后 macOS 的 getpgid 会 ESRCH。
    // 核对失败时先杀掉这个刚起来的子进程并回收，绝不在失败路径上留下不属于自己的进程。
    if (getpgid(c->pid) != c->pid) {
        (void)kill(c->pid, SIGKILL);
        int status = 0;
        while (waitpid(c->pid, &status, 0) < 0 && errno == EINTR) {}
        c->pid = -1;
        error = EPERM;
        goto fail;
    }
    c->owned_group = c->pid;
    *child = c; *stdin_fd = in[1]; in[1] = -1;
    *stdout_fd = out[0]; out[0] = -1;
    if (capture_stderr) { *stderr_fd = err[0]; err[0] = -1; }
fail:
    if (actions_ready) posix_spawn_file_actions_destroy(&actions);
    if (attrs_ready) posix_spawnattr_destroy(&attrs);
    close_fd(&in[0]); close_fd(&in[1]); close_fd(&out[0]); close_fd(&out[1]);
    close_fd(&err[0]); close_fd(&err[1]); close_fd(&nullfd);
    if (error) free(c);
    return error;
}
static int observe(WS2Child *c) {
    if (c->state.reaped || c->state.direct_exited) return 0;
    siginfo_t info;
    memset(&info, 0, sizeof(info));
    int result;
    do { result = waitid(P_PID, (id_t)c->pid, &info, WEXITED | WNOHANG | WNOWAIT); }
    while (result < 0 && errno == EINTR);
    if (result < 0) { c->state.supervision_error = errno; return errno; }
    if (info.si_pid == c->pid) {
        c->state.direct_exited = 1;
        c->state.exit_status = info.si_status;
        c->state.was_signalled = info.si_code != CLD_EXITED;
    }
    return 0;
}
// macOS：组里只剩一个僵尸组长时，kill(-pgid) 回 EPERM（Linux 回 ESRCH）；可组里还有收不到信号的
// 成员时回的也是 EPERM。只有组长确已退出、且组里列不出组长以外的任何进程，才算“已空”。
// 列举失败一律当作不空：宁可报监督失败，也不把真正的权限问题当成已经清干净。
static int group_left_only_exited_leader(WS2Child *c, pid_t group) {
    if (observe(c) != 0 || !c->state.direct_exited) return 0;
#if defined(__APPLE__)
    for (int attempt = 0; attempt < 3; ++attempt) {
        int bytes = proc_listpids(PROC_PGRP_ONLY, (uint32_t)group, NULL, 0);
        if (bytes < 0) return 0;
        if (bytes == 0) return 1;
        int capacity = bytes / (int)sizeof(pid_t) + 16;
        pid_t *pids = calloc((size_t)capacity, sizeof(pid_t));
        if (!pids) return 0;
        int filled = proc_listpids(PROC_PGRP_ONLY, (uint32_t)group, pids, capacity * (int)sizeof(pid_t));
        if (filled < 0) { free(pids); return 0; }
        int count = filled / (int)sizeof(pid_t);
        if (count >= capacity) { free(pids); continue; }
        int others = 0;
        for (int i = 0; i < count; ++i) if (pids[i] > 0 && pids[i] != c->pid) others = 1;
        free(pids);
        return !others;
    }
    return 0;
#else
    (void)group;
    return 0;
#endif
}
static int signal_owned_group(WS2Child *c, int signo) {
    if (c->state.reaped || c->state.supervision_error) return ECHILD;
    // macOS：leader 一退出，getpgid() 直接 ESRCH（Linux 的僵尸还锚着 PID），
    // 所以组长身份在 spawn 成功时就核对并记下，之后只用这个记下的组号，绝不再猜。
    pid_t group = c->owned_group;
    if (group != c->pid || group <= 1 || group == getpgrp()) {
        c->state.supervision_error = EPERM;
        return c->state.supervision_error;
    }
    if (kill(-group, signo) != 0) {
        int saved = errno;
        if (saved != ESRCH && !(saved == EPERM && group_left_only_exited_leader(c, group))) {
            c->state.supervision_error = saved; return saved;
        }
    }
    if (signo == SIGTERM) c->state.term_sent = 1;
    if (signo == SIGKILL) c->state.kill_sent = 1;
    return 0;
}
static int begin_stop(WS2Child *c) {
    if (c->stopping || c->state.reaped) return 0;
    double now = monotonic_seconds();
    if (now < 0) { c->state.supervision_error = errno; return errno; }
    c->stopping = 1; c->kill_at = now + 0.500;
    return signal_owned_group(c, SIGTERM);
}
int ws2_child_poll(WS2Child *c, WS2ChildState *state) {
    if (!c || !state) return EINVAL;
    int error = observe(c);
    if (!error && c->state.direct_exited && !c->stopping) error = begin_stop(c);
    if (!error && c->stopping && !c->state.kill_sent && monotonic_seconds() >= c->kill_at)
        error = signal_owned_group(c, SIGKILL);
    // Never reap before the final group signal. Afterwards we will never signal this PID again.
    if (!error && c->state.direct_exited && c->state.kill_sent && !c->state.reaped) {
        int status = 0; pid_t result;
        do { result = waitpid(c->pid, &status, WNOHANG); } while (result < 0 && errno == EINTR);
        if (result == c->pid) c->state.reaped = 1;
        else if (result < 0) { error = errno; c->state.supervision_error = error; }
    }
    *state = c->state;
    return error;
}
int ws2_child_stop(WS2Child *c) {
    if (!c) return EINVAL;
    int error = observe(c);
    return error ? error : begin_stop(c);
}
int ws2_child_destroy(WS2Child *c) {
    if (!c) return 0;
    // Release an untrusted token on supervision failure, without claiming the process exited.
    if (!c->state.reaped && !c->state.supervision_error) return EBUSY;
    free(c); return 0;
}
pid_t ws2_child_pid(const WS2Child *c) { return c ? c->pid : -1; }
