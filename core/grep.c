#include "grep.h"
#include <stdlib.h>
#include <string.h>

static int glob_one(const char *p, const char *n)
{
    for (;;) {
        if (*p == '*') {
            while (*p == '*') p++;
            if (*p == '\0') return 1;
            for (; *n != '\0'; n++)
                if (glob_one(p, n)) return 1;
            return 0;
        }
        if (*p == '\0') return *n == '\0';
        if (*n == '\0') return 0;
        if (*p != '?' && *p != *n) return 0;
        p++;
        n++;
    }
}

int glob_match_any(const char *patterns, const char *name)
{
    const char *p = patterns;
    int any = 0;

    while (*p != '\0') {
        char one[256];
        unsigned l = 0;

        while (*p == ' ' || *p == ',' || *p == '\t') p++;
        while (*p != '\0' && *p != ' ' && *p != ',' && *p != '\t') { if (l < sizeof one - 1) one[l++] = *p; p++; }
        one[l] = '\0';
        if (l == 0) continue;
        any = 1;
        if (glob_one(one, name)) return 1;
    }
    return !any;
}

void grep_free(GrepHits *h)
{
    free(h->hit);
    h->hit = NULL;
    h->n = h->cap = 0;
}

static int hits_add(GrepHits *h, const GrepHit *x)
{
    if (h->n == h->cap) {
        unsigned nc = h->cap ? h->cap * 2 : 16;
        GrepHit *nh = (GrepHit *)realloc(h->hit, nc * sizeof(GrepHit));

        if (nh == NULL) return 0;
        h->hit = nh;
        h->cap = nc;
    }
    h->hit[h->n++] = *x;
    return 1;
}

unsigned grep_text(Search *s, const u16 *text, unsigned len, GrepHits *out, unsigned max)
{
    unsigned pos = 0, added = 0, line = 1, linepos = 0;     /* `line` is the number of the line starting at linepos */
    SearchMatch m;

    while (added < max && pos <= len && search_find(s, text, len, pos, 1, 0, &m)) {
        GrepHit x;
        unsigned ls = m.start[0], le;

        while (ls > 0 && text[ls - 1] != '\n') ls--;
        for (; linepos < ls; linepos++) if (text[linepos] == '\n') line++;
        le = m.start[0];
        while (le < len && text[le] != '\n') le++;
        x.line = line;
        x.lstart = ls;
        x.lend = le;
        x.mstart = m.start[0];
        if (!hits_add(out, &x)) break;
        added++;
        pos = le + 1;                         /* the rest of this line is not looked at again */
    }
    return added;
}

unsigned grep_replace(Search *s, const u16 *text, unsigned len, const u16 *repl, unsigned nrepl, int literal,
                      u16 **out, unsigned *outlen)
{
    u16 *mid = NULL, *res;
    unsigned midlen = 0, first = 0, last = 0, count = 0;

    *out = NULL;
    *outlen = 0;
    if (!search_replace_all(s, text, len, 0, len, repl, nrepl, literal, &mid, &midlen, &first, &last, &count) || count == 0) {
        free(mid);
        return 0;
    }
    res = (u16 *)malloc((first + midlen + (len - last) + 1) * sizeof(u16));
    if (res == NULL) { free(mid); return 0; }
    if (first > 0) memcpy(res, text, first * sizeof(u16));
    if (midlen > 0) memcpy(res + first, mid, midlen * sizeof(u16));
    if (len > last) memcpy(res + first + midlen, text + last, (len - last) * sizeof(u16));
    *out = res;
    *outlen = first + midlen + (len - last);
    free(mid);
    return count;
}

int grep_bytes_are_text(const unsigned char *b, unsigned n)
{
    unsigned i = 0;

    while (i < n) {
        unsigned c = b[i], need, j;

        if (c == 0) return 0;
        if (c < 0x80) { i++; continue; }
        if (c >= 0xC2 && c <= 0xDF) need = 1;
        else if (c >= 0xE0 && c <= 0xEF) need = 2;
        else if (c >= 0xF0 && c <= 0xF4) need = 3;
        else return 0;
        for (j = 1; j <= need; j++)
            if (i + j >= n || (b[i + j] & 0xC0) != 0x80) return 0;
        i += need + 1;
    }
    return 1;
}
