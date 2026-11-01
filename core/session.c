#include "session.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

Session *session_new(void)
{
    Session *s = (Session *)malloc(sizeof(Session));

    if (s == NULL) return NULL;
    s->f = (SessionFile *)malloc(SESSION_MAX_FILES * sizeof(SessionFile));
    if (s->f == NULL) { free(s); return NULL; }
    s->n = 0;
    return s;
}

void session_free(Session *s)
{
    if (s == NULL) return;
    free(s->f);
    free(s);
}

int session_add(Session *s, const SessionFile *f)
{
    if (s->n >= SESSION_MAX_FILES || f->path[0] == '\0' || strchr(f->path, '\n') != NULL) return 0;
    if (memchr(f->path, '\0', SESSION_PATH_SIZE) == NULL) return 0;
    s->f[s->n++] = *f;
    return 1;
}

static const char *num(const char *p, long *v)
{
    int neg = 0;

    *v = 0;
    if (*p == '-') { neg = 1; p++; }
    while (*p >= '0' && *p <= '9') { *v = *v * 10 + (*p - '0'); p++; }
    if (neg) *v = -*v;
    return p;
}

void session_parse(Session *s, const char *text)
{
    const char *p = text;

    s->n = 0;
    while (*p != '\0') {
        const char *eol = p;
        SessionFile f;
        const char *q;
        int ok = 0;

        while (*eol != '\0' && *eol != '\n') eol++;
        memset(&f, 0, sizeof f);
        f.wrap = -1;
        if (eol - p > 5 && strncmp(p, "file ", 5) == 0) {
            q = p + 5;
            while (q < eol) {
                long a, b, c, d;

                while (q < eol && *q == ' ') q++;
                if (strncmp(q, "path=", 5) == 0) {
                    size_t len = (size_t)(eol - (q + 5));

                    if (len > 0 && len < SESSION_PATH_SIZE) {
                        memcpy(f.path, q + 5, len);
                        f.path[len] = '\0';
                        if (len > 0 && f.path[len - 1] == '\r') f.path[len - 1] = '\0';
                        ok = f.path[0] != '\0';
                    }
                    break;
                }
                if (strncmp(q, "caret=", 6) == 0) { q = num(q + 6, &a); f.caret = a > 0 ? (unsigned)a : 0; }
                else if (strncmp(q, "sel=", 4) == 0) { q = num(q + 4, &a); f.sel = a > 0 ? (unsigned)a : 0; }
                else if (strncmp(q, "scroll=", 7) == 0) { q = num(q + 7, &a); f.scroll = (int)a; }
                else if (strncmp(q, "wrap=", 5) == 0) { q = num(q + 5, &a); f.wrap = a == 0 ? 0 : 1; }
                else if (strncmp(q, "frame=", 6) == 0) {
                    q = num(q + 6, &a);
                    if (*q == ',') q = num(q + 1, &b); else b = 0;
                    if (*q == ',') q = num(q + 1, &c); else c = 0;
                    if (*q == ',') q = num(q + 1, &d); else d = 0;
                    if (c > 0 && d > 0) { f.has_frame = 1; f.fx = (int)a; f.fy = (int)b; f.fw = (int)c; f.fh = (int)d; }
                }
                else while (q < eol && *q != ' ') q++;                  /* a key we do not know */
            }
        }
        if (ok && s->n < SESSION_MAX_FILES) s->f[s->n++] = f;
        p = *eol == '\n' ? eol + 1 : eol;
    }
}

unsigned session_format(const Session *s, char *out, unsigned cap)
{
    unsigned total = 0;
    int i;

    if (cap > 0) out[0] = '\0';
    for (i = 0; i < s->n; i++) {
        const SessionFile *f = &s->f[i];
        char line[SESSION_PATH_SIZE + 200];
        unsigned l;

        sprintf(line, "file caret=%u sel=%u scroll=%d", f->caret, f->sel, f->scroll);
        if (f->has_frame) sprintf(line + strlen(line), " frame=%d,%d,%d,%d", f->fx, f->fy, f->fw, f->fh);
        if (f->wrap >= 0) sprintf(line + strlen(line), " wrap=%d", f->wrap);
        strcat(line, " path=");
        strcat(line, f->path);
        strcat(line, "\n");
        l = (unsigned)strlen(line);
        if (cap > 0 && total + l < cap) memcpy(out + total, line, l + 1);
        total += l;
    }
    return total;
}
