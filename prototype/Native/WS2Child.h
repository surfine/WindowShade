#ifndef WS2_CHILD_H
#define WS2_CHILD_H
#include <stdint.h>
#include <sys/types.h>

// Caller is the sole reaper. Never pass a PID from another launcher to this API.
typedef struct WS2Child WS2Child;
typedef struct {
    int direct_exited;
    int exit_status;
    int was_signalled;
    int reaped;
    int supervision_error;
    int term_sent;
    int kill_sent;
} WS2ChildState;
int ws2_child_spawn(const char *executable, char *const argv[], char *const envp[],
                    const char *cwd, int capture_stderr, WS2Child **child,
                    int *stdin_fd, int *stdout_fd, int *stderr_fd);
// Nonblocking. Detects direct-child exit independently of inherited pipe EOF.
int ws2_child_poll(WS2Child *child, WS2ChildState *state);
int ws2_child_stop(WS2Child *child);
// After reaping, or after a recorded supervision failure. The latter abandons only
// our bookkeeping: it does NOT certify exit or tree cleanup. EBUSY otherwise.
int ws2_child_destroy(WS2Child *child);
pid_t ws2_child_pid(const WS2Child *child);
#endif
