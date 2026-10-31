#include <stdlib.h>
#include <string.h>
#include "edit.h"

static int blank(u16 c) { return c == ' ' || c == '\t'; }

/* Appends to a growing buffer; returns 0 when out of memory. */
typedef struct { u16 *buf; unsigned used, cap; } Buf;

static int put(Buf *b, u16 c)
{
    if (b->used == b->cap) {
        unsigned nc = b->cap ? b->cap * 2 : 256;
        u16 *nb = (u16 *)realloc(b->buf, nc * sizeof(u16));
        if (nb == NULL) return 0;
        b->buf = nb;
        b->cap = nc;
    }
    b->buf[b->used++] = c;
    return 1;
}

static int put_n(Buf *b, const u16 *s, unsigned n)
{
    unsigned i;
    for (i = 0; i < n; i++)
        if (!put(b, s[i])) return 0;
    return 1;
}

int edit_shift_lines(const u16 *t, unsigned n, int dir, int use_spaces, unsigned width, u16 **out, unsigned *outlen)
{
    Buf b;
    unsigned s = 0, e, i, k;
    int changed = 0;

    b.buf = NULL; b.used = b.cap = 0;
    if (width == 0) width = 1;
    for (;;) {
        e = s;
        while (e < n && t[e] != '\n') e++;
        if (e > s) {                                     /* a non-empty line */
            if (dir > 0) {
                if (use_spaces) { for (k = 0; k < width; k++) if (!put(&b, ' ')) goto fail; }
                else if (!put(&b, '\t')) goto fail;
                changed = 1;
                if (!put_n(&b, t + s, e - s)) goto fail;
            } else {
                i = s;
                if (t[i] == '\t') { i++; changed = 1; }
                else { k = 0; while (i < e && t[i] == ' ' && k < width) { i++; k++; } if (k > 0) changed = 1; }
                if (!put_n(&b, t + i, e - i)) goto fail;
            }
        }
        if (e >= n) break;
        if (!put(&b, '\n')) goto fail;
        s = e + 1;
    }
    if (!changed) { free(b.buf); return 0; }
    *out = b.buf;
    *outlen = b.used;
    return 1;
fail:
    free(b.buf);
    return 0;
}

static unsigned lead(const u16 *t, unsigned s, unsigned e)
{
    unsigned i = s;
    while (i < e && blank(t[i])) i++;
    return i - s;
}

static int starts_with(const u16 *t, unsigned i, unsigned e, const u16 *p, unsigned np)
{
    return i + np <= e && memcmp(t + i, p, np * sizeof(u16)) == 0;
}

int edit_comment_lines(const u16 *t, unsigned n, const u16 *pre, unsigned npre, const u16 *suf, unsigned nsuf, int uncomment,
                       u16 **out, unsigned *outlen)
{
    Buf b;
    unsigned s = 0, e, col = (unsigned)-1, l;
    int changed = 0;

    b.buf = NULL; b.used = b.cap = 0;
    if (npre == 0) return 0;
    if (!uncomment) {                                    /* the least indentation of the non-blank lines */
        for (;;) {
            e = s;
            while (e < n && t[e] != '\n') e++;
            l = lead(t, s, e);
            if (s + l < e && l < col) col = l;
            if (e >= n) break;
            s = e + 1;
        }
        if (col == (unsigned)-1) return 0;
    }
    s = 0;
    for (;;) {
        e = s;
        while (e < n && t[e] != '\n') e++;
        l = lead(t, s, e);
        if (s + l == e) {                                 /* a blank line stays as it is */
            if (!put_n(&b, t + s, e - s)) goto fail;
        } else if (!uncomment) {
            if (!put_n(&b, t + s, col)) goto fail;
            if (!put_n(&b, pre, npre) || !put(&b, ' ')) goto fail;
            if (!put_n(&b, t + s + col, e - s - col)) goto fail;
            if (nsuf > 0) { if (!put(&b, ' ') || !put_n(&b, suf, nsuf)) goto fail; }
            changed = 1;
        } else if (starts_with(t, s + l, e, pre, npre)) {
            unsigned a = s + l + npre, z = e;
            if (a < e && t[a] == ' ') a++;
            if (nsuf > 0) {
                unsigned w = z;
                while (w > a && blank(t[w - 1])) w--;
                if (w >= a + nsuf && starts_with(t, w - nsuf, w, suf, nsuf)) {
                    z = w - nsuf;
                    while (z > a && t[z - 1] == ' ') z--;
                }
            }
            if (!put_n(&b, t + s, l) || !put_n(&b, t + a, z - a)) goto fail;
            changed = 1;
        } else {
            if (!put_n(&b, t + s, e - s)) goto fail;
        }
        if (e >= n) break;
        if (!put(&b, '\n')) goto fail;
        s = e + 1;
    }
    if (!changed) { free(b.buf); return 0; }
    *out = b.buf;
    *outlen = b.used;
    return 1;
fail:
    free(b.buf);
    return 0;
}

unsigned edit_newline_indent(const u16 *before, unsigned n, int smart, int use_spaces, unsigned width, u16 *out, unsigned cap)
{
    unsigned l = lead(before, 0, n), k, used = 0, last = n;

    for (k = 0; k < l && used < cap; k++) out[used++] = before[k];
    while (last > 0 && blank(before[last - 1])) last--;
    if (last > 0 && ((smart == 'b' && before[last - 1] == '{') || (smart == 'c' && before[last - 1] == ':'))) {
        if (use_spaces) { for (k = 0; k < width && used < cap; k++) out[used++] = ' '; }
        else if (used < cap) out[used++] = '\t';
    }
    return used;
}

unsigned edit_outdent_amount(const u16 *before, unsigned n, unsigned width)
{
    unsigned i, k;

    if (n == 0) return 0;
    for (i = 0; i < n; i++) if (!blank(before[i])) return 0;
    if (before[n - 1] == '\t') return 1;
    k = 0;
    while (k < n && k < width && before[n - 1 - k] == ' ') k++;
    return k;
}

unsigned edit_column(const u16 *before, unsigned n)
{
    unsigned i, col = 0;

    for (i = 0; i < n; i++) col = before[i] == '\t' ? (col / 8 + 1) * 8 : col + 1;
    return col;
}
