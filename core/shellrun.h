#ifndef SHELLRUN_H
#define SHELLRUN_H

#include <stddef.h>

/* Runs a shell command (sh -c) with some input, collecting what it writes to stdout and to stderr.  Plain C with
 * POSIX calls only (fork, pipe, select, waitpid); the caller's event loop is blocked while it runs, so there is a time
 * limit. */

typedef struct {
    char *out;            /* what it wrote to stdout (malloc'd, NUL-terminated; never NULL after a run) */
    size_t nout;
    char *err;            /* ... and to stderr */
    size_t nerr;
    int status;           /* the exit status; 128 + the signal number if it was killed; -1 if it could not be started */
    int timed_out;        /* it was killed because it ran past the limit */
    int truncated;        /* the output reached max_out and the rest was dropped */
} ShellResult;

/* `dir` (may be NULL) becomes the working directory.  `in` (may be NULL) is the standard input.  timeout_ms 0: no limit.
 * max_out is the most that is kept of each of stdout and stderr (0: no limit).  Returns 1 if the command ran at all. */
int shell_run(const char *cmd, const char *dir, const char *in, size_t nin, unsigned timeout_ms, size_t max_out,
              ShellResult *r);
void shell_result_free(ShellResult *r);

#endif
