#include <stdlib.h>
#include <string.h>
#include "fold.h"
#include "brace.h"

static unsigned put_number(u16 *out, unsigned v)
{
    char tmp[16];
    unsigned n = 0, i;

    do { tmp[n++] = (char)('0' + v % 10); v /= 10; } while (v > 0 && n < 15);
    for (i = 0; i < n; i++) out[i] = (u16)(unsigned char)tmp[n - 1 - i];
    return n;
}

static unsigned put_text(u16 *out, const char *s)
{
    unsigned n = 0;

    while (s[n]) { out[n] = (u16)(unsigned char)s[n]; n++; }
    return n;
}

unsigned fold_make_token(u16 *out, unsigned lines, unsigned id)
{
    unsigned n = put_text(out, " ... ");

    n += put_number(out + n, lines);
    n += put_text(out + n, " lines ~");
    n += put_number(out + n, id);
    out[n++] = ' ';
    return n;
}

/* Reads decimal digits at t[i]; returns how many (0 if none) and the value. */
static unsigned read_number(const u16 *t, unsigned n, unsigned i, unsigned *value)
{
    unsigned k = 0;
    unsigned long v = 0;

    while (i + k < n && t[i + k] >= '0' && t[i + k] <= '9' && k < 9) { v = v * 10 + (t[i + k] - '0'); k++; }
    *value = (unsigned)v;
    return k;
}

static int match_text(const u16 *t, unsigned n, unsigned i, const char *s)
{
    unsigned k;

    for (k = 0; s[k]; k++) if (i + k >= n || t[i + k] != (u16)(unsigned char)s[k]) return 0;
    return 1;
}

/* A token that starts exactly at i. */
static int token_at(const u16 *t, unsigned n, unsigned i, unsigned *end, unsigned *lines, unsigned *id)
{
    unsigned p = i + 5, k;

    if (!match_text(t, n, i, " ... ")) return 0;
    k = read_number(t, n, p, lines);
    if (k == 0) return 0;
    p += k;
    if (!match_text(t, n, p, " lines ~")) return 0;
    p += 8;
    k = read_number(t, n, p, id);
    if (k == 0) return 0;
    p += k;
    if (p >= n || t[p] != ' ') return 0;
    *end = p + 1;
    return 1;
}

int fold_token_find(const u16 *t, unsigned n, unsigned from, unsigned *start, unsigned *end, unsigned *lines, unsigned *id)
{
    unsigned i;

    for (i = from; i + 5 < n; i++) {
        if (t[i] == ' ' && t[i + 1] == '.' && token_at(t, n, i, end, lines, id)) {
            *start = i;
            return 1;
        }
    }
    return 0;
}

unsigned fold_hidden_lines(const u16 *t, unsigned n, unsigned limit)
{
    unsigned total = 0, i, end, lines, id;

    for (i = 0; i < limit && i + 5 < n; i++) {
        if (t[i] == ' ' && t[i + 1] == '.' && token_at(t, n, i, &end, &lines, &id)) {
            total += lines;
            i = end - 1;
        }
    }
    return total;
}

static int has_newline(const u16 *t, unsigned a, unsigned b)
{
    while (a < b) if (t[a++] == '\n') return 1;
    return 0;
}

int fold_find_block(const u16 *t, unsigned n, unsigned pos, int c_aware, unsigned *open, unsigned *close)
{
    unsigned ls, le, i, m;
    long depth;

    if (pos > n) pos = n;
    ls = pos;
    while (ls > 0 && t[ls - 1] != '\n') ls--;
    le = pos;
    while (le < n && t[le] != '\n') le++;
    /* a block that opens on this line and ends on a later one */
    for (i = ls; i < le; i++) {
        if (t[i] == '{' && brace_match(t, n, i, c_aware, &m) && m > i && has_newline(t, i, m)) {
            *open = i;
            *close = m;
            return 1;
        }
    }
    /* Allman style: this line has no brace, and the next one starts with one */
    for (i = ls; i < le && (t[i] == ' ' || t[i] == '\t' || t[i] == '\r'); i++) ;
    if (i < le && t[i] != '{' && t[i] != '}' && le < n) {
        unsigned j = le + 1;
        int brace_on_line = 0;
        for (i = ls; i < le; i++) if (t[i] == '{' || t[i] == '}') brace_on_line = 1;
        while (j < n && (t[j] == ' ' || t[j] == '\t' || t[j] == '\r')) j++;
        if (!brace_on_line && j < n && t[j] == '{' && brace_match(t, n, j, c_aware, &m) && m > j && has_newline(t, j, m)) {
            *open = j;
            *close = m;
            return 1;
        }
    }
    /* a line that closes a block */
    for (i = ls; i < le; i++) {
        if (t[i] == '}' && brace_match(t, n, i, c_aware, &m) && m < i && has_newline(t, m, i)) {
            *open = m;
            *close = i;
            return 1;
        }
    }
    /* the innermost multi-line block around the line */
    depth = 0;
    for (i = ls; i > 0; i--) {
        u16 c = t[i - 1];
        if (c == '}') depth++;
        else if (c == '{') {
            if (depth > 0) depth--;
            else if (brace_match(t, n, i - 1, c_aware, &m) && m >= le && has_newline(t, i - 1, m)) {
                *open = i - 1;
                *close = m;
                return 1;
            }
        }
    }
    return 0;
}

enum { S_CODE, S_LINE, S_BLOCK, S_STR, S_CHR };

unsigned fold_top_blocks(const u16 *t, unsigned n, int c_aware, unsigned **opens, unsigned **closes)
{
    unsigned count = 0, cap = 0, i, depth = 0, start = 0;
    int state = S_CODE;
    unsigned *o = NULL, *c = NULL;

    *opens = *closes = NULL;
    for (i = 0; i < n; i++) {
        u16 ch = t[i];
        if (c_aware && state == S_LINE) { if (ch == '\n') state = S_CODE; continue; }
        if (c_aware && state == S_BLOCK) { if (ch == '*' && i + 1 < n && t[i + 1] == '/') { state = S_CODE; i++; } continue; }
        if (c_aware && (state == S_STR || state == S_CHR)) {
            if (ch == '\\') i++;
            else if (ch == '\n' || (state == S_STR && ch == '"') || (state == S_CHR && ch == '\'')) state = S_CODE;
            continue;
        }
        if (c_aware) {
            if (ch == '/' && i + 1 < n && t[i + 1] == '/') { state = S_LINE; i++; continue; }
            if (ch == '/' && i + 1 < n && t[i + 1] == '*') { state = S_BLOCK; i++; continue; }
            if (ch == '"') { state = S_STR; continue; }
            if (ch == '\'') { state = S_CHR; continue; }
        }
        if (ch == '{') {
            if (depth == 0) start = i;
            depth++;
        } else if (ch == '}' && depth > 0) {
            depth--;
            if (depth == 0 && has_newline(t, start, i)) {
                if (count == cap) {
                    unsigned nc = cap ? cap * 2 : 32;
                    unsigned *no = (unsigned *)realloc(o, nc * sizeof(unsigned));
                    unsigned *nk = (unsigned *)realloc(c, nc * sizeof(unsigned));
                    if (no) o = no;
                    if (nk) c = nk;
                    if (!no || !nk) { free(o); free(c); return 0; }
                    cap = nc;
                }
                o[count] = start;
                c[count] = i;
                count++;
            }
        }
    }
    *opens = o;
    *closes = c;
    return count;
}
