#include <stdlib.h>
#include <string.h>
#include "foldlines.h"
#include "fold.h"
#include "words.h"

typedef struct { unsigned start; unsigned char collapsed; } Entry;

typedef struct { Entry *v; unsigned n, cap; } List;

static int add(List *l, unsigned start, int collapsed)
{
    if (l->n == l->cap) {
        unsigned nc = l->cap ? l->cap * 2 : 128;
        Entry *nv = (Entry *)realloc(l->v, nc * sizeof(Entry));
        if (nv == NULL) return 0;
        l->v = nv;
        l->cap = nc;
    }
    l->v[l->n].start = start;
    l->v[l->n].collapsed = (unsigned char)collapsed;
    l->n++;
    return 1;
}

static unsigned line_start_of(const u16 *t, unsigned i)
{
    while (i > 0 && t[i - 1] != '\n') i--;
    return i;
}

static int cmp_entry(const void *a, const void *b)
{
    const Entry *x = (const Entry *)a, *y = (const Entry *)b;

    if (x->start != y->start) return x->start < y->start ? -1 : 1;
    return (int)x->collapsed - (int)y->collapsed;
}

enum { S_CODE, S_LINE, S_BLOCK, S_STR, S_CHR };

/* braces: every `{` whose `}` is on a later line */
static int scan_braces(const u16 *t, unsigned n, int flags, List *l)
{
    unsigned *stack_start = NULL, *stack_line = NULL, top = 0, cap = 0, i, line = 0;
    int state = S_CODE, ok = 1, c_aware = (flags & FOLD_CAWARE) != 0, brackets = (flags & FOLD_BRACKETS) != 0;

    for (i = 0; i < n && ok; i++) {
        u16 ch = t[i];
        if (ch == '\n') { line++; if (state == S_LINE || state == S_STR || state == S_CHR) state = S_CODE; continue; }
        if (c_aware && state == S_LINE) continue;
        if (c_aware && state == S_BLOCK) { if (ch == '*' && i + 1 < n && t[i + 1] == '/') { state = S_CODE; i++; } continue; }
        if (c_aware && (state == S_STR || state == S_CHR)) {
            if (ch == '\\' && i + 1 < n && t[i + 1] != '\n') i++;
            else if ((state == S_STR && ch == '"') || (state == S_CHR && ch == '\'')) state = S_CODE;
            continue;
        }
        if (c_aware) {
            if (ch == '/' && i + 1 < n && t[i + 1] == '/') { state = S_LINE; i++; continue; }
            if (ch == '/' && i + 1 < n && t[i + 1] == '*') { state = S_BLOCK; i++; continue; }
            if (ch == '"') { state = S_STR; continue; }
            if (ch == '\'') { state = S_CHR; continue; }
        }
        if (ch == '{' || (brackets && ch == '[')) {
            if (top == cap) {
                unsigned nc = cap ? cap * 2 : 64;
                unsigned *a = (unsigned *)realloc(stack_start, nc * sizeof(unsigned));
                unsigned *b = (unsigned *)realloc(stack_line, nc * sizeof(unsigned));
                if (a) stack_start = a;
                if (b) stack_line = b;
                if (!a || !b) { ok = 0; break; }
                cap = nc;
            }
            stack_start[top] = line_start_of(t, i);
            stack_line[top] = line;
            top++;
        } else if ((ch == '}' || (brackets && ch == ']')) && top > 0) {
            top--;
            if (stack_line[top] != line && !add(l, stack_start[top], 0)) ok = 0;
        }
    }
    free(stack_start);
    free(stack_line);
    return ok;
}

/* indentation: a line followed by a line indented more */
static int scan_indent(const u16 *t, unsigned n, List *l)
{
    unsigned ls = 0, le, prev_start = 0;
    int prev_indent = -1;

    for (;;) {
        unsigned i;
        int col = 0, blank = 1;
        for (le = ls; le < n && t[le] != '\n'; le++) ;
        for (i = ls; i < le; i++) {
            if (t[i] == ' ') col++;
            else if (t[i] == '\t') col = (col / 8 + 1) * 8;
            else if (t[i] == '\r') continue;
            else { blank = 0; break; }
        }
        if (!blank) {
            if (prev_indent >= 0 && col > prev_indent && !add(l, prev_start, 0)) return 0;
            prev_start = ls;
            prev_indent = col;
        }
        if (le >= n) break;
        ls = le + 1;
    }
    return 1;
}

static int scan_words(const u16 *t, unsigned n, int kind, List *l)
{
    WordBlocks b;
    unsigned i;
    int ok = 1;

    if (!words_scan(t, n, kind, &b)) return 0;
    for (i = 0; i < b.npairs && ok; i++) {
        unsigned ls = line_start_of(t, b.pairs[i].os), j;
        for (j = b.pairs[i].os; j < b.pairs[i].cs; j++) {
            if (t[j] == '\n') { ok = add(l, ls, 0); break; }
        }
    }
    words_free(&b);
    return ok;
}

int foldlines_scan(const u16 *t, unsigned n, int style, int flags, int word_kind, FoldLines *out)
{
    List l = { 0, 0, 0 };
    unsigned from = 0, st, en, lines, id, i, w;
    int ok;

    memset(out, 0, sizeof *out);
    if (style == 'i') ok = scan_indent(t, n, &l);
    else if (style == 'w') ok = scan_words(t, n, word_kind, &l);
    else ok = scan_braces(t, n, flags, &l);
    while (ok && fold_token_find(t, n, from, &st, &en, &lines, &id)) {
        ok = add(&l, line_start_of(t, st), 1);
        from = en;
    }
    if (!ok) { free(l.v); return 0; }
    if (l.n == 0) { free(l.v); return 1; }
    qsort(l.v, l.n, sizeof(Entry), cmp_entry);
    /* one entry per line; a marker wins over a block beginning */
    out->start = (unsigned *)malloc(l.n * sizeof(unsigned));
    out->collapsed = (unsigned char *)malloc(l.n);
    if (!out->start || !out->collapsed) { free(out->start); free(out->collapsed); memset(out, 0, sizeof *out); free(l.v); return 0; }
    w = 0;
    for (i = 0; i < l.n; i++) {
        if (w > 0 && out->start[w - 1] == l.v[i].start) {
            if (l.v[i].collapsed) out->collapsed[w - 1] = 1;
            continue;
        }
        out->start[w] = l.v[i].start;
        out->collapsed[w] = l.v[i].collapsed;
        w++;
    }
    out->count = w;
    free(l.v);
    return 1;
}

void foldlines_free(FoldLines *f)
{
    free(f->start);
    free(f->collapsed);
    memset(f, 0, sizeof *f);
}

int foldlines_state(const FoldLines *f, unsigned line_start)
{
    unsigned lo = 0, hi = f->count;

    while (lo < hi) {
        unsigned mid = lo + (hi - lo) / 2;
        if (f->start[mid] < line_start) lo = mid + 1;
        else hi = mid;
    }
    if (lo < f->count && f->start[lo] == line_start) return f->collapsed[lo] ? 2 : 1;
    return 0;
}
