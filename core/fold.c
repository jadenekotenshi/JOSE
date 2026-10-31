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
int fold_token_at(const u16 *t, unsigned n, unsigned i, unsigned *end, unsigned *lines, unsigned *id)
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
        if (t[i] == ' ' && t[i + 1] == '.' && fold_token_at(t, n, i, end, lines, id)) {
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
        if (t[i] == ' ' && t[i + 1] == '.' && fold_token_at(t, n, i, &end, &lines, &id)) {
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

static int is_opener(u16 c, int brackets) { return c == '{' || (brackets && c == '['); }
static int is_closer(u16 c, int brackets) { return c == '}' || (brackets && c == ']'); }

int fold_find_block(const u16 *t, unsigned n, unsigned pos, int flags, unsigned *open, unsigned *close)
{
    unsigned ls, le, i, m;
    long depth;
    int c_aware = (flags & FOLD_CAWARE) != 0, brackets = (flags & FOLD_BRACKETS) != 0;

    if (pos > n) pos = n;
    ls = pos;
    while (ls > 0 && t[ls - 1] != '\n') ls--;
    le = pos;
    while (le < n && t[le] != '\n') le++;
    /* a block that opens on this line and ends on a later one */
    for (i = ls; i < le; i++) {
        if (is_opener(t[i], brackets) && brace_match(t, n, i, c_aware, &m) && m > i && has_newline(t, i, m)) {
            *open = i;
            *close = m;
            return 1;
        }
    }
    /* Allman style: this line has no brace, and the next one starts with one */
    for (i = ls; i < le && (t[i] == ' ' || t[i] == '\t' || t[i] == '\r'); i++) ;
    if (i < le && !is_opener(t[i], brackets) && !is_closer(t[i], brackets) && le < n) {
        unsigned j = le + 1;
        int brace_on_line = 0;
        for (i = ls; i < le; i++) if (is_opener(t[i], brackets) || is_closer(t[i], brackets)) brace_on_line = 1;
        while (j < n && (t[j] == ' ' || t[j] == '\t' || t[j] == '\r')) j++;
        if (!brace_on_line && j < n && is_opener(t[j], brackets) && brace_match(t, n, j, c_aware, &m) && m > j && has_newline(t, j, m)) {
            *open = j;
            *close = m;
            return 1;
        }
    }
    /* a line that closes a block */
    for (i = ls; i < le; i++) {
        if (is_closer(t[i], brackets) && brace_match(t, n, i, c_aware, &m) && m < i && has_newline(t, m, i)) {
            *open = m;
            *close = i;
            return 1;
        }
    }
    /* the innermost multi-line block around the line */
    depth = 0;
    for (i = ls; i > 0; i--) {
        u16 c = t[i - 1];
        if (is_closer(c, brackets)) depth++;
        else if (is_opener(c, brackets)) {
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

unsigned fold_top_blocks(const u16 *t, unsigned n, int flags, unsigned **opens, unsigned **closes)
{
    unsigned count = 0, cap = 0, i, depth = 0, start = 0;
    int state = S_CODE, c_aware = (flags & FOLD_CAWARE) != 0, brackets = (flags & FOLD_BRACKETS) != 0;
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
        if (is_opener(ch, brackets)) {
            if (depth == 0) start = i;
            depth++;
        } else if (is_closer(ch, brackets) && depth > 0) {
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

/* ---- folding by indentation ---- */

/* The indentation of the line t[a, b) in columns (a tab going to the next multiple of 8), -1 if it is blank. */
static int line_indent(const u16 *t, unsigned a, unsigned b)
{
    unsigned i;
    int col = 0;

    for (i = a; i < b; i++) {
        if (t[i] == ' ') col++;
        else if (t[i] == '\t') col = (col / 8 + 1) * 8;
        else if (t[i] == '\r') continue;
        else return col;
    }
    return -1;
}

static unsigned eol_from(const u16 *t, unsigned n, unsigned i)
{
    while (i < n && t[i] != '\n') i++;
    return i;
}

/* The end of the block under the header line whose end is `he_line`: the end of the last line indented more than `indent`
 * (blank lines at the end do not count).  Returns he_line if the block is empty. */
static unsigned block_end(const u16 *t, unsigned n, unsigned he_line, int indent)
{
    unsigned last = he_line, ls = he_line + 1, le;

    while (he_line < n && ls <= n) {
        int ind;
        le = eol_from(t, n, ls);
        ind = line_indent(t, ls, le);
        if (ind >= 0) {
            if (ind <= indent) break;
            last = le;
        }
        if (le >= n) break;
        ls = le + 1;
    }
    return last;
}

/* The indentation of the next non-blank line after the one that ends at `le`, -1 if there is none. */
static int next_indent(const u16 *t, unsigned n, unsigned le)
{
    unsigned ls, e;
    int ind;

    while (le < n) {
        ls = le + 1;
        e = eol_from(t, n, ls);
        ind = line_indent(t, ls, e);
        if (ind >= 0) return ind;
        le = e;
    }
    return -1;
}

int fold_indent_block(const u16 *t, unsigned n, unsigned pos, unsigned *hs, unsigned *he)
{
    unsigned ls, le, hls, hle;
    int ind;

    if (pos > n) pos = n;
    ls = pos;
    while (ls > 0 && t[ls - 1] != '\n') ls--;
    le = eol_from(t, n, pos);
    /* a blank line: use the nearest non-blank one above */
    while (line_indent(t, ls, le) < 0) {
        if (ls == 0) return 0;
        le = ls - 1;
        ls = le;
        while (ls > 0 && t[ls - 1] != '\n') ls--;
    }
    ind = line_indent(t, ls, le);
    hls = ls;
    hle = le;
    if (next_indent(t, n, le) <= ind) {              /* no block under this line: the header is the nearest line above that is indented less */
        unsigned cl = ls;
        int found = 0;
        while (cl > 0) {
            unsigned pe = cl - 1, ps = pe;
            int pi;
            while (ps > 0 && t[ps - 1] != '\n') ps--;
            pi = line_indent(t, ps, pe);
            if (pi >= 0 && pi < ind) { hls = ps; hle = pe; ind = pi; found = 1; break; }
            cl = ps;
        }
        if (!found) return 0;
    }
    {
        unsigned end = block_end(t, n, hle, line_indent(t, hls, hle));
        if (end <= hle) return 0;
        *hs = hle;
        *he = end;
        return 1;
    }
}

unsigned fold_indent_top(const u16 *t, unsigned n, unsigned **hs, unsigned **he)
{
    unsigned ls = 0, count = 0, cap = 0, le, skip_to = 0;
    int base = -1;
    unsigned *a = NULL, *b = NULL;

    *hs = *he = NULL;
    for (le = 0; ls <= n; ls = le + 1) {                    /* the least indentation of any line */
        int ind;
        le = eol_from(t, n, ls);
        ind = line_indent(t, ls, le);
        if (ind >= 0 && (base < 0 || ind < base)) base = ind;
        if (le >= n) break;
    }
    if (base < 0) return 0;
    for (ls = 0; ls <= n; ls = le + 1) {
        int ind;
        le = eol_from(t, n, ls);
        ind = line_indent(t, ls, le);
        if (ind == base && ls >= skip_to) {
            unsigned end = block_end(t, n, le, ind);
            if (end > le) {
                if (count == cap) {
                    unsigned nc = cap ? cap * 2 : 32;
                    unsigned *na = (unsigned *)realloc(a, nc * sizeof(unsigned));
                    unsigned *nb = (unsigned *)realloc(b, nc * sizeof(unsigned));
                    if (na) a = na;
                    if (nb) b = nb;
                    if (!na || !nb) { free(a); free(b); return 0; }
                    cap = nc;
                }
                a[count] = le;
                b[count] = end;
                count++;
                skip_to = end;
            }
        }
        if (le >= n) break;
    }
    *hs = a;
    *he = b;
    return count;
}
