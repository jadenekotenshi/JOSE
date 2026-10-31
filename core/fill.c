#include <stdlib.h>
#include <string.h>
#include "fill.h"

static int is_blank(u16 c) { return c == ' ' || c == '\t' || c == '\r' || c == '\f'; }

/* The length of the comment leader at t[i], 0 if there is none. */
static unsigned leader_at(const u16 *t, unsigned i, unsigned b)
{
    if (i >= b) return 0;
    if (i + 1 < b && ((t[i] == '/' && t[i + 1] == '/') || (t[i] == '-' && t[i + 1] == '-'))) return 2;
    if (t[i] == '#' || t[i] == '*' || t[i] == '>' || t[i] == ';' || t[i] == '%') return 1;
    return 0;
}

/* The length of the prefix of the line [a, b): blanks, then a leader, then blanks.  *lead is where the leader starts and
 * *nlead how long it is (0 if none). */
static unsigned prefix_len(const u16 *t, unsigned a, unsigned b, unsigned *lead, unsigned *nlead)
{
    unsigned i = a;
    while (i < b && is_blank(t[i])) i++;
    *lead = i;
    *nlead = leader_at(t, i, b);
    i += *nlead;
    if (*nlead) while (i < b && is_blank(t[i])) i++;
    return i - a;
}

/* A line with nothing on it but blanks, or blanks and a comment leader, separates paragraphs. */
static int line_is_blank(const u16 *t, unsigned a, unsigned b)
{
    unsigned lead, nlead, p = prefix_len(t, a, b, &lead, &nlead);
    return a + p == b;
}

static unsigned col_after(unsigned col, u16 c)
{
    return c == '\t' ? (col / 8 + 1) * 8 : col + 1;
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

int fill_find_paragraph(const u16 *t, unsigned n, unsigned pos, unsigned *start, unsigned *end)
{
    unsigned ls, le, s, e;

    if (pos > n) pos = n;
    ls = pos;
    while (ls > 0 && t[ls - 1] != '\n') ls--;
    le = pos;
    while (le < n && t[le] != '\n') le++;
    if (line_is_blank(t, ls, le)) return 0;
    s = ls;
    while (s > 0) {
        unsigned ps = s - 1, pb = ps;           /* ps is the '\n' ending the previous line */
        while (ps > 0 && t[ps - 1] != '\n') ps--;
        if (line_is_blank(t, ps, pb)) break;
        s = ps;
    }
    e = le;
    while (e < n) {
        unsigned ns = e + 1, ne = ns;           /* t[e] is the '\n' ending this line */
        while (ne < n && t[ne] != '\n') ne++;
        if (line_is_blank(t, ns, ne)) break;
        e = ne;
    }
    *start = s;
    *end = e;
    return 1;
}

/* Fills the paragraph t[a, b) (whole lines, none of them blank) into `o`. */
static int fill_one(const u16 *t, unsigned a, unsigned b, unsigned width, Buf *o)
{
    unsigned lead1, nlead1, p1, le1, p2a, p2n, ls, linecol, nwords = 0, i;

    for (le1 = a; le1 < b && t[le1] != '\n'; le1++) ;
    p1 = prefix_len(t, a, le1, &lead1, &nlead1);
    p2a = a;                             /* the prefix used for the lines after the first */
    p2n = p1;
    if (le1 < b) {
        unsigned s2 = le1 + 1, e2 = s2, ld, nl, pl;
        while (e2 < b && t[e2] != '\n') e2++;
        pl = prefix_len(t, s2, e2, &ld, &nl);
        if (nl == nlead1 && memcmp(t + lead1, t + ld, nl * sizeof(u16)) == 0) {
            p2a = s2;
            p2n = pl;
        }
    }

    if (!put_n(o, t + a, p1)) return 0;
    linecol = 0;
    for (i = 0; i < p1; i++) linecol = col_after(linecol, t[a + i]);

    for (ls = a; ls <= b; ) {
        unsigned le, w, we, skip;
        for (le = ls; le < b && t[le] != '\n'; le++) ;
        if (ls == a) {
            skip = p1;
        } else {
            unsigned ld, nl, pl = prefix_len(t, ls, le, &ld, &nl);
            if (nl == nlead1 && memcmp(t + lead1, t + ld, nl * sizeof(u16)) == 0) skip = pl;
            else for (skip = 0; skip < le - ls && is_blank(t[ls + skip]); skip++) ;
        }
        for (w = ls + skip; w < le; w = we) {
            unsigned k, wcol = linecol, endcol;
            while (w < le && is_blank(t[w])) w++;
            if (w >= le) break;
            for (we = w; we < le && !is_blank(t[we]); we++) ;
            if (nwords > 0) wcol = col_after(wcol, ' ');
            endcol = wcol;
            for (k = w; k < we; k++) endcol = col_after(endcol, t[k]);
            if (nwords > 0 && endcol > width) {
                if (!put(o, '\n') || !put_n(o, t + p2a, p2n)) return 0;
                linecol = 0;
                for (k = 0; k < p2n; k++) linecol = col_after(linecol, t[p2a + k]);
                nwords = 0;
            } else if (nwords > 0) {
                if (!put(o, ' ')) return 0;
                linecol = wcol;
            }
            if (!put_n(o, t + w, we - w)) return 0;
            for (k = w; k < we; k++) linecol = col_after(linecol, t[k]);
            nwords++;
        }
        if (le >= b) break;
        ls = le + 1;
    }
    return 1;
}

int fill_text(const u16 *t, unsigned n, unsigned width, u16 **out, unsigned *outlen)
{
    Buf o = { 0, 0, 0 };
    unsigned i = 0;

    if (width < 8) width = 8;
    while (i < n) {
        unsigned le = i;
        while (le < n && t[le] != '\n') le++;
        if (line_is_blank(t, i, le)) {
            if (!put_n(&o, t + i, le - i)) goto fail;
            if (le < n && !put(&o, '\n')) goto fail;
            i = le < n ? le + 1 : n;
        } else {
            unsigned pe = le;
            while (pe < n) {
                unsigned ns = pe + 1, ne = ns;
                while (ne < n && t[ne] != '\n') ne++;
                if (line_is_blank(t, ns, ne)) break;
                pe = ne;
            }
            if (!fill_one(t, i, pe, width, &o)) goto fail;
            if (pe < n && !put(&o, '\n')) goto fail;
            i = pe < n ? pe + 1 : n;
        }
    }
    if (o.n == n && (n == 0 || memcmp(o.p, t, n * sizeof(u16)) == 0)) {
        free(o.p);
        return 0;
    }
    *out = o.p;
    *outlen = o.n;
    return 1;
fail:
    free(o.p);
    return 0;
}
