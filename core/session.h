#ifndef SESSION_H
#define SESSION_H

/* A saved set of open files: where each file is, where the caret and the scroll position were, and the window's place.  Plain C so
 * that the text form can be tested on the host.  One line per file:
 *     file caret=12 sel=0 scroll=345 frame=10,20,640,480 wrap=1 path=/some/where/file.c
 * (path last, so that it may hold spaces; a file whose name holds a newline cannot be saved). */

#define SESSION_MAX_FILES 100
#define SESSION_PATH_SIZE 1024

typedef struct {
    unsigned caret, sel;               /* the selection */
    int      scroll;                   /* how far the text was scrolled, in points */
    int      has_frame;
    int      fx, fy, fw, fh;           /* the window's frame */
    int      wrap;                     /* 1 or 0, -1 if not recorded */
    char     path[SESSION_PATH_SIZE];
} SessionFile;

typedef struct {
    SessionFile *f;                    /* SESSION_MAX_FILES of them */
    int          n;
} Session;

Session *session_new(void);
void     session_free(Session *s);
/* Adds a file; 0 if the session is full or the path is empty, too long or holds a newline. */
int      session_add(Session *s, const SessionFile *f);
void     session_parse(Session *s, const char *text);                     /* replaces the contents; bad lines are skipped */
unsigned session_format(const Session *s, char *out, unsigned cap);       /* NUL-terminated; returns the length needed */

#endif
