#import "Compat.h"
#import "AppController.h"
#import "UIHelpers.h"
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

/*
 * Startup is narrated with NSLog so a launch that "does nothing" can be diagnosed:
 * run  ./JOSE.app/JOSE  from a Terminal and see how far it gets.
 * Workspace throws a launched application's stderr away, so the same narration is also written
 * to ~/.JOSE.trace when that file exists:   touch ~/.JOSE.trace
 * then launch from Workspace and read the file.
 */
/* A crash must not be silent: while ~/.JOSE.trace exists a fatal signal writes one line to it (using only write(),
 * which is safe in a signal handler) before the process dies as it would have. */
static int traceFD = -1;

static void fatal_signal(int sig)
{
    static const char *const names[] = { "?", "SIGHUP", "SIGINT", "SIGQUIT", "SIGILL", "SIGTRAP", "SIGABRT", "SIGEMT", "SIGFPE",
                                         "SIGKILL", "SIGBUS", "SIGSEGV", "SIGSYS", "SIGPIPE", "SIGALRM", "SIGTERM" };
    const char *name = (sig > 0 && sig < 16) ? names[sig] : names[0];
    if (traceFD >= 0) {
        write(traceFD, "FATAL: ", 7);
        write(traceFD, name, strlen(name));
        write(traceFD, " (the process dies); last step: ", 33);
        write(traceFD, (const char *)ss_crumb, strlen((const char *)ss_crumb));
        write(traceFD, "\n", 1);
    }
    signal(sig, SIG_DFL);
    kill(getpid(), sig);
}

static void leaving(void)
{
    if (traceFD >= 0) write(traceFD, "the process exits\n", 18);
}

/* An exception raised while one event is handled is logged and the event is dropped, instead of ending the program (and the
 * unsaved work in every window with it).  The last step the program reported (SSCrumb) is written with it. */
@interface JOSEApplication : NSApplication
@end

@implementation JOSEApplication
- (void)sendEvent:(NSEvent *)event
{
    NS_DURING
        [super sendEvent:event];
    NS_HANDLER
        NSLog(@"JOSE: exception in an event: %@ -- %@", [localException name], [localException reason]);
        SSTrace("EXCEPTION in an event: %s -- %s; last step: %s", SSCS([localException name]), SSCS([localException reason]), (const char *)ss_crumb);
        NSBeep();
    NS_ENDHANDLER
}
@end

int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool;
    AppController *controller;
    int i;

    /* Descriptors 0, 1 and 2 must be open: a program started by Workspace may have none of them, and then the first files it
     * opens (the pseudo-terminal, a log) would become its "standard output" and "standard error", and Foundation's own
     * messages would be written into the pty.  Whichever are closed are pointed at /dev/null. */
    {
        int fd;
        for (fd = 0; fd < 3; fd++)
            if (fcntl(fd, F_GETFD, 0) < 0) (void)open("/dev/null", O_RDWR);
    }
    pool = [[NSAutoreleasePool alloc] init];
    SSCrumb("starting up");
    NSLog(@"JOSE: starting");
    SSTrace("---- starting, argc=%d", argc);
    for (i = 0; i < argc; i++) SSTrace("  argv[%d] = %s", i, argv[i]);
    SSTrace("  cwd  = %s", SSCS([[NSFileManager defaultManager] currentDirectoryPath]));
    SSTrace("  NSHomeDirectory() = %s", SSCS(NSHomeDirectory()));
    SSTrace("  getenv(\"HOME\")   = %s", getenv("HOME") ? getenv("HOME") : "(not set)");
    SSTrace("  getenv(\"SHELL\")  = %s", getenv("SHELL") ? getenv("SHELL") : "(not set)");
    SSTrace("  NSUserName()      = %s", SSCS(NSUserName()));
    signal(SIGPIPE, SIG_IGN);
    {
        NSString *tp = [NSHomeDirectory() stringByAppendingPathComponent:@".JOSE.trace"];
        traceFD = open(UI_CPATH(tp), O_WRONLY | O_APPEND);        /* only if the file exists: tracing is opt-in */
        if (traceFD >= 0) {
            signal(SIGSEGV, fatal_signal); signal(SIGBUS, fatal_signal); signal(SIGILL, fatal_signal);
            signal(SIGFPE, fatal_signal); signal(SIGABRT, fatal_signal); signal(SIGTERM, fatal_signal);
            signal(SIGHUP, fatal_signal);
            atexit(leaving);
        }
    }

    NS_DURING
        [JOSEApplication sharedApplication];
        NSLog(@"JOSE: NSApplication created");
        SSTrace("NSApplication created");
        controller = [[AppController alloc] init];
        NSLog(@"JOSE: controller created");
        SSTrace("controller created");
        [NSApp setDelegate:controller];
        [controller buildMenu];
        if (argc > 1) {                          /* files named on the command line */
            /* Workspace adds "-NXAutoLaunch NO -NXHost ..." style pairs: a dash option takes the next argument as its value,
             * and only an argument that names an existing file is opened. */
            for (i = 1; i < argc; i++) {
                if (argv[i][0] == '-') { i++; continue; }
                if (access(argv[i], R_OK) == 0) [controller openAtLaunch:[NSString stringWithCString:argv[i]]];
            }
        }
        NSLog(@"JOSE: menu built, entering the event loop");
        SSTrace("menu built, entering the event loop");
        [NSApp run];
        NSLog(@"JOSE: event loop ended");
        SSTrace("event loop ended");
    NS_HANDLER
        NSLog(@"JOSE: uncaught exception: %@ -- %@", [localException name], [localException reason]);
        SSTrace("uncaught exception: %s -- %s", SSCS([localException name]), SSCS([localException reason]));
    NS_ENDHANDLER

    [pool release];
    return 0;
}
