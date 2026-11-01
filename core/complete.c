#include "complete.h"
#include <stdlib.h>
#include <string.h>

void comp_init(CompList *l, int icase)
{
    l->v = NULL;
    l->n = l->cap = 0;
    l->icase = icase;
}

void comp_free(CompList *l)
{
    unsigned i;

    for (i = 0; i < l->n; i++) free(l->v[i].w);
    free(l->v);
    l->v = NULL;
    l->n = l->cap = 0;
}

int comp_is_ident(unsigned c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c > 127;
}

unsigned comp_prefix_len(const u16 *t, unsigned n, unsigned pos)
{
    unsigned k = 0, digits = 0;

    if (pos > n) pos = n;
    while (k < pos && comp_is_ident(t[pos - k - 1])) k++;
    for (digits = 0; digits < k && t[pos - k + digits] >= '0' && t[pos - k + digits] <= '9'; digits++) ;
    if (digits == k) return 0;                       /* only digits: a number, not a word */
    return k;
}

static unsigned lower(unsigned c)
{
    return (c >= 'A' && c <= 'Z') ? c + 32 : c;
}

static int same(const u16 *a, const u16 *b, unsigned n, int icase)
{
    unsigned i;

    for (i = 0; i < n; i++)
        if (icase ? lower(a[i]) != lower(b[i]) : a[i] != b[i]) return 0;
    return 1;
}

int comp_add_word(CompList *l, const u16 *prefix, unsigned plen, const u16 *w, unsigned wlen, unsigned max_total)
{
    unsigned i;
    u16 *copy;

    if (l->n >= max_total || wlen <= plen || !same(prefix, w, plen, l->icase)) return 0;
    for (i = 0; i < l->n; i++)
        if (l->v[i].len == wlen && same(l->v[i].w, w, wlen, 0)) return 0;
    if (l->n == l->cap) {
        unsigned nc = l->cap ? l->cap * 2 : 32;
        CompWord *nv = (CompWord *)realloc(l->v, nc * sizeof(CompWord));

        if (nv == NULL) return 0;
        l->v = nv;
        l->cap = nc;
    }
    copy = (u16 *)malloc(wlen * sizeof(u16));
    if (copy == NULL) return 0;
    memcpy(copy, w, wlen * sizeof(u16));
    l->v[l->n].w = copy;
    l->v[l->n].len = wlen;
    l->n++;
    return 1;
}

unsigned comp_add_text_words(CompList *l, const u16 *t, unsigned n, unsigned start, unsigned pos, unsigned max_total)
{
    unsigned added = 0, plen = pos - start, e, s;
    const u16 *prefix = t + start;

    if (plen == 0 || pos > n) return 0;
    e = start;                                       /* backwards: the words that end before the prefix, nearest first */
    while (e > 0) {
        while (e > 0 && !comp_is_ident(t[e - 1])) e--;
        s = e;
        while (s > 0 && comp_is_ident(t[s - 1])) s--;
        if (e > s && !(t[s] >= '0' && t[s] <= '9')) added += (unsigned)comp_add_word(l, prefix, plen, t + s, e - s, max_total);
        e = s;
    }
    s = pos;                                         /* forwards: past the rest of the word the caret is in */
    while (s < n && comp_is_ident(t[s])) s++;
    while (s < n) {
        while (s < n && !comp_is_ident(t[s])) s++;
        e = s;
        while (e < n && comp_is_ident(t[e])) e++;
        if (e > s && !(t[s] >= '0' && t[s] <= '9')) added += (unsigned)comp_add_word(l, prefix, plen, t + s, e - s, max_total);
        s = e;
    }
    return added;
}

unsigned comp_add_words_of(CompList *l, const u16 *t, unsigned n, const u16 *prefix, unsigned plen, unsigned max_total)
{
    unsigned added = 0, s = 0, e;

    while (s < n && l->n < max_total) {
        while (s < n && !comp_is_ident(t[s])) s++;
        e = s;
        while (e < n && comp_is_ident(t[e])) e++;
        if (e > s && !(t[s] >= '0' && t[s] <= '9')) added += (unsigned)comp_add_word(l, prefix, plen, t + s, e - s, max_total);
        s = e;
    }
    return added;
}

unsigned comp_add_syntax_keywords(CompList *l, const char *syntax, const u16 *prefix, unsigned plen, unsigned max_total)
{
    const char *p = syntax;
    unsigned added = 0;

    while ((p = strstr(p, "Pattern = \"<")) != NULL) {
        const char *w;
        u16 buf[64];
        unsigned k = 0;

        p += 12;
        w = p;
        while (*w != '\0' && k < 63 && ((*w >= 'a' && *w <= 'z') || (*w >= 'A' && *w <= 'Z') || (*w >= '0' && *w <= '9') || *w == '_')) buf[k++] = (u16)(unsigned char)*w++;
        if (k > 0 && w[0] == '>' && w[1] == '"') added += (unsigned)comp_add_word(l, prefix, plen, buf, k, max_total);
    }
    return added;
}
