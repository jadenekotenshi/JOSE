#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/time.h>
#ifdef OPENSTEP
/* OPENSTEP's <unistd.h> declares little: the system calls come from <libc.h>, O_NONBLOCK may only be FNDELAY, and wait
 * statuses are a `union wait', so they are taken apart by hand below. */
#include <libc.h>
#include <sys/file.h>
#include <sys/wait.h>
#ifndef O_NONBLOCK
#ifdef FNDELAY
#define O_NONBLOCK FNDELAY
#else
#define O_NONBLOCK 0x0004
#endif
#endif
#else
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#endif
#include "shellrun.h"

typedef struct { char *p; size_t n, cap; } Grow;

static int grow_add(Grow *g, const char *s, size_t n, size_t max, int *truncated)
{
    if (max && g->n + n > max) {
        n = g->n < max ? max - g->n : 0;
        *truncated = 1;
    }
    if (g->n + n + 1 > g->cap) {
        size_t nc = g->cap ? g->cap : 1024;
        char *np;
        while (nc < g->n + n + 1) nc *= 2;
        np = (char *)realloc(g->p, nc);
        if (!np) return 0;
        g->p = np;
        g->cap = nc;
    }
    memcpy(g->p + g->n, s, n);
    g->n += n;
    g->p[g->n] = '\0';
    return 1;
}

static void set_nonblock(int fd)
{
    int fl = fcntl(fd, F_GETFL, 0);
    if (fl != -1) fcntl(fd, F_SETFL, fl | O_NONBLOCK);
}

static unsigned long now_ms(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (unsigned long)tv.tv_sec * 1000UL + (unsigned long)(tv.tv_usec / 1000);
}

void shell_result_free(ShellResult *r)
{
    free(r->out);
    free(r->err);
    r->out = r->err = NULL;
    r->nout = r->nerr = 0;
}

int shell_run(const char *cmd, const char *dir, const char *in, size_t nin, unsigned timeout_ms, size_t max_out,
              ShellResult *r)
{
    int inp[2], outp[2], errp[2];
    int pid;
    Grow go = { 0, 0, 0 }, ge = { 0, 0, 0 };
    size_t written = 0;
    int in_open, out_open = 1, err_open = 1, status = 0, reaped = 0;
    unsigned long start = now_ms();
    void (*old_pipe)(int);

    memset(r, 0, sizeof(*r));
    r->status = -1;
    if (pipe(inp) < 0) goto nostart;
    if (pipe(outp) < 0) { close(inp[0]); close(inp[1]); goto nostart; }
    if (pipe(errp) < 0) { close(inp[0]); close(inp[1]); close(outp[0]); close(outp[1]); goto nostart; }

    pid = fork();
    if (pid < 0) {
        close(inp[0]); close(inp[1]); close(outp[0]); close(outp[1]); close(errp[0]); close(errp[1]);
        goto nostart;
    }
    if (pid == 0) {
        dup2(inp[0], 0);
        dup2(outp[1], 1);
        dup2(errp[1], 2);
        close(inp[0]); close(inp[1]); close(outp[0]); close(outp[1]); close(errp[0]); close(errp[1]);
        if (dir && chdir(dir) < 0) { /* run in the current directory instead */ }
        execl("/bin/sh", "sh", "-c", cmd, (char *)0);
        _exit(127);
    }
    close(inp[0]);
    close(outp[1]);
    close(errp[1]);
    old_pipe = signal(SIGPIPE, SIG_IGN);
    set_nonblock(inp[1]);
    set_nonblock(outp[0]);
    set_nonblock(errp[0]);
    in_open = 1;
    if (!in || nin == 0) { close(inp[1]); in_open = 0; }

    while (out_open || err_open || in_open) {
        fd_set rf, wf;
        struct timeval tv, *tp = NULL;
        int maxfd = -1, n;

        FD_ZERO(&rf);
        FD_ZERO(&wf);
        if (out_open) { FD_SET(outp[0], &rf); if (outp[0] > maxfd) maxfd = outp[0]; }
        if (err_open) { FD_SET(errp[0], &rf); if (errp[0] > maxfd) maxfd = errp[0]; }
        if (in_open)  { FD_SET(inp[1], &wf);  if (inp[1] > maxfd) maxfd = inp[1]; }
        if (timeout_ms) {
            unsigned long el = now_ms() - start;
            if (el >= timeout_ms) { r->timed_out = 1; kill(pid, SIGKILL); break; }
            tv.tv_sec = (timeout_ms - el) / 1000;
            tv.tv_usec = ((timeout_ms - el) % 1000) * 1000;
            tp = &tv;
        }
        n = select(maxfd + 1, &rf, &wf, NULL, tp);
        if (n < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (n == 0) continue;
        if (r->truncated) { kill(pid, SIGKILL); break; }       /* more output than will be kept */
        if (in_open && FD_ISSET(inp[1], &wf)) {
            int w = write(inp[1], in + written, nin - written);
            if (w > 0) written += (size_t)w;
            if ((w < 0 && errno != EAGAIN && errno != EINTR) || written >= nin) { close(inp[1]); in_open = 0; }
        }
        if (out_open && FD_ISSET(outp[0], &rf)) {
            char buf[4096];
            int g = read(outp[0], buf, sizeof buf);
            if (g > 0) grow_add(&go, buf, (size_t)g, max_out, &r->truncated);
            else if (g == 0 || (errno != EAGAIN && errno != EINTR)) { close(outp[0]); out_open = 0; }
        }
        if (err_open && FD_ISSET(errp[0], &rf)) {
            char buf[4096];
            int g = read(errp[0], buf, sizeof buf);
            if (g > 0) grow_add(&ge, buf, (size_t)g, max_out, &r->truncated);
            else if (g == 0 || (errno != EAGAIN && errno != EINTR)) { close(errp[0]); err_open = 0; }
        }
    }
    if (in_open) close(inp[1]);
    if (out_open) close(outp[0]);
    if (err_open) close(errp[0]);
    while (!reaped) {
#ifdef OPENSTEP
        int w = wait((void *)&status);          /* this libc has no waitpid; the only child that matters is the one just started */
#else
        int w = waitpid(pid, &status, 0);
#endif
        if (w == pid) reaped = 1;
        else if (w < 0 && errno != EINTR) break;
    }
    signal(SIGPIPE, old_pipe);
    if (reaped) {
        /* the classic encoding: the low 7 bits are the signal (0: it exited), the next 8 the exit code */
        if ((status & 0x7f) == 0) r->status = (status >> 8) & 0xff;
        else if ((status & 0xff) != 0x7f) r->status = 128 + (status & 0x7f);
    }
    if (!go.p) grow_add(&go, "", 0, 0, &r->truncated);
    if (!ge.p) grow_add(&ge, "", 0, 0, &r->truncated);
    r->out = go.p;
    r->nout = go.n;
    r->err = ge.p;
    r->nerr = ge.n;
    return 1;
nostart:
    r->out = (char *)calloc(1, 1);
    r->err = (char *)calloc(1, 1);
    return 0;
}
