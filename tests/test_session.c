#include "test.h"
#include "../core/session.h"
#include <stdlib.h>

int main(void)
{
    Session *s = session_new(), *q = session_new();
    SessionFile f;
    char buf[4096];
    unsigned n;
    int i;

    memset(&f, 0, sizeof f);
    f.wrap = -1;
    strcpy(f.path, "/home/jade/a.c");
    f.caret = 120;
    f.scroll = 330;
    CHECK(session_add(s, &f));
    memset(&f, 0, sizeof f);
    strcpy(f.path, "/Users/jade/My Docs/b c.txt");        /* spaces in the path */
    f.has_frame = 1; f.fx = -10; f.fy = 40; f.fw = 640; f.fh = 480;
    f.wrap = 1; f.sel = 7; f.caret = 3;
    CHECK(session_add(s, &f));
    strcpy(f.path, "");
    CHECK(!session_add(s, &f));                            /* no path */
    strcpy(f.path, "/a\nb");
    CHECK(!session_add(s, &f));                            /* a newline */
    CHECK(s->n == 2);

    n = session_format(s, buf, sizeof buf);
    CHECK(n == strlen(buf));
    CHECK(strcmp(buf, "file caret=120 sel=0 scroll=330 path=/home/jade/a.c\n"
                      "file caret=3 sel=7 scroll=0 frame=-10,40,640,480 wrap=1 path=/Users/jade/My Docs/b c.txt\n") == 0);
    CHECK(session_format(s, buf, 5) == n);                 /* too small: reports what is needed */
    session_format(s, buf, sizeof buf);
    session_parse(q, buf);
    CHECK(q->n == 2);
    CHECK(strcmp(q->f[0].path, "/home/jade/a.c") == 0 && q->f[0].caret == 120 && q->f[0].scroll == 330 && !q->f[0].has_frame && q->f[0].wrap == -1);
    CHECK(strcmp(q->f[1].path, "/Users/jade/My Docs/b c.txt") == 0 && q->f[1].has_frame && q->f[1].fx == -10 && q->f[1].fw == 640 && q->f[1].wrap == 1 && q->f[1].sel == 7);

    session_parse(q, "# comment\nfile caret=1 path=/x\nbogus line\nfile caret=2\nfile frame=1,2 path=/y\nfile caret=5 future=9 path=/z w\n\nfile path=\n");
    CHECK(q->n == 3);                                      /* the ones with a path: /x, /y (bad frame ignored), /z w */
    CHECK(strcmp(q->f[0].path, "/x") == 0 && q->f[0].caret == 1);
    CHECK(strcmp(q->f[1].path, "/y") == 0 && !q->f[1].has_frame);
    CHECK(strcmp(q->f[2].path, "/z w") == 0 && q->f[2].caret == 5);

    session_parse(q, "file path=/crlf\r\n");
    CHECK(q->n == 1 && strcmp(q->f[0].path, "/crlf") == 0);

    for (i = 0; i < SESSION_MAX_FILES; i++) { memset(&f, 0, sizeof f); strcpy(f.path, "/p"); session_add(s, &f); }
    CHECK(s->n == SESSION_MAX_FILES);
    CHECK(!session_add(s, &f));                            /* full */
    session_free(s);
    session_free(q);
    TEST_DONE("test_session");
}
