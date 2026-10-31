#include <stdlib.h>
#include <string.h>
#include "rect.h"

static unsigned next_col(unsigned col, u16 c)
{
    return c == '\t' ? (col / 8 + 1) * 8 : col + 1;
}

unsigned rect_index_at_column(const u16 *t, unsigned n, unsigned col, unsigned *short_by)
{
    unsigned i, c = 0;
    for (i = 0; i < n; i++) {
        if (c >= col) {
            if (short_by) *short_by = 0;
            return i;
        }
        c = next_col(c, t[i]);
    }
    if (short_by) *short_by = c >= col ? 0 : col - c;
    return n;
}

unsigned rect_column_of_index(const u16 *t, unsigned n, unsigned index)
{
    unsigned i, c = 0;
    for (i = 0; i < index && i < n; i++) c = next_col(c, t[i]);
    return c;
}

typedef struct { u16 *p; unsigned n, cap; } Buf;

static int put(Buf *b, u16 c)
{
    if (b->n == b->cap) {
        unsigned nc = b->cap ? b->cap * 2 : 256;
        u16 *np = (u16 *)realloc(b->p, nc * sizeof(u16));
        if (!np) return 0;
        b->p = np;
        b->cap = nc;
    }
    b->p[b->n++] = c;
    return 1;
}

static int put_n(Buf *b, const u16 *s, unsigned n)
{
    unsigned i;
    for (i = 0; i < n; i++) if (!put(b, s[i])) return 0;
    return 1;
}

/* The next line of t[pos, n): its end (the '\n' or n). */
static unsigned line_end(const u16 *t, unsigned n, unsigned pos)
{
    while (pos < n && t[pos] != '\n') pos++;
    return pos;
}

int rect_extract(const u16 *t, unsigned n, unsigned c0, unsigned c1, u16 **out, unsigned *outlen)
{
    Buf o = { 0, 0, 0 };
    unsigned pos = 0;

    for (;;) {
        unsigned le = line_end(t, n, pos), ia, ib;
        ia = rect_index_at_column(t + pos, le - pos, c0, NULL);
        ib = rect_index_at_column(t + pos, le - pos, c1, NULL);
        if (ib < ia) ib = ia;
        if (!put_n(&o, t + pos + ia, ib - ia)) goto fail;
        if (le >= n) break;
        if (!put(&o, '\n')) goto fail;
        pos = le + 1;
    }
    *out = o.p;
    *outlen = o.n;
    if (!o.p) { *out = (u16 *)malloc(sizeof(u16)); if (!*out) return 0; }
    return 1;
fail:
    free(o.p);
    return 0;
}

/* Line k of the '\n'-separated `s`: its start, and its length in *len; the length is 0 (and the start s) past the last line. */
static const u16 *nth_line(const u16 *s, unsigned n, unsigned k, unsigned *len)
{
    unsigned pos = 0, e;
    while (k > 0) {
        e = line_end(s, n, pos);
        if (e >= n) { *len = 0; return s; }
        pos = e + 1;
        k--;
    }
    e = line_end(s, n, pos);
    *len = e - pos;
    return s + pos;
}

int rect_replace(const u16 *t, unsigned n, unsigned c0, unsigned c1, const u16 *ins, unsigned nins, int per_line,
                 u16 **out, unsigned *outlen)
{
    Buf o = { 0, 0, 0 };
    unsigned pos = 0, k = 0, nlines = 1, i;

    for (i = 0; i < nins; i++) if (ins[i] == '\n') nlines++;
    for (;;) {
        unsigned le = line_end(t, n, pos), len = le - pos, ia, ib, pad, il;
        const u16 *is;
        ia = rect_index_at_column(t + pos, len, c0, &pad);
        ib = rect_index_at_column(t + pos, len, c1, NULL);
        if (ib < ia) ib = ia;
        if (per_line) is = nth_line(ins, nins, k, &il);
        else { is = ins; il = nins; }
        if (!put_n(&o, t + pos, ia)) goto fail;
        if (il > 0) {
            for (i = 0; i < pad; i++) if (!put(&o, ' ')) goto fail;
            if (!put_n(&o, is, il)) goto fail;
        }
        if (!put_n(&o, t + pos + ib, len - ib)) goto fail;
        k++;
        if (le >= n) break;
        if (!put(&o, '\n')) goto fail;
        pos = le + 1;
    }
    /* more lines to put in than the buffer had: they go below, at column c0 */
    for (; per_line && k < nlines; k++) {
        unsigned il;
        const u16 *is = nth_line(ins, nins, k, &il);
        if (!put(&o, '\n')) goto fail;
        if (il > 0) {
            for (i = 0; i < c0; i++) if (!put(&o, ' ')) goto fail;
            if (!put_n(&o, is, il)) goto fail;
        }
    }
    *out = o.p;
    *outlen = o.n;
    if (!o.p) { *out = (u16 *)malloc(sizeof(u16)); if (!*out) return 0; }
    return 1;
fail:
    free(o.p);
    return 0;
}
