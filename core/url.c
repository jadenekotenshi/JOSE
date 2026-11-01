#include "url.h"

static int scheme_char(unsigned c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.';
}

static int stop_char(unsigned c)
{
    return c <= ' ' || c == '"' || c == '<' || c == '>' || c == '\'' || c == '`' || c == '{' || c == '}' || c == '|' || c == '\\' || c == '^' || c >= 127;
}

/* Does an address begin at t[i]?  Returns the index just past its "scheme://" or "mailto:" part, or 0. */
static unsigned scheme_end(const u16 *t, unsigned n, unsigned i)
{
    unsigned j = i;

    if (i > 0 && scheme_char(t[i - 1])) return 0;               /* must not start in the middle of a word */
    if (j >= n || !((t[j] >= 'a' && t[j] <= 'z') || (t[j] >= 'A' && t[j] <= 'Z'))) return 0;
    while (j < n && scheme_char(t[j])) j++;
    if (j + 2 < n && t[j] == ':' && t[j + 1] == '/' && t[j + 2] == '/') return j + 3;
    if (j + 1 < n && t[j] == ':' && j - i == 6 &&
        (t[i] | 32) == 'm' && (t[i + 1] | 32) == 'a' && (t[i + 2] | 32) == 'i' && (t[i + 3] | 32) == 'l' && (t[i + 4] | 32) == 't' && (t[i + 5] | 32) == 'o')
        return j + 1;
    return 0;
}

/* The end of the address that begins at i (whose scheme ends at `after`). */
static unsigned url_end(const u16 *t, unsigned n, unsigned after)
{
    unsigned e = after;
    int depth = 0;

    while (e < n && !stop_char(t[e])) {
        if (t[e] == '(') depth++;
        else if (t[e] == ')') { if (depth == 0) break; depth--; }
        e++;
    }
    while (e > after && (t[e - 1] == '.' || t[e - 1] == ',' || t[e - 1] == ';' || t[e - 1] == ':' || t[e - 1] == '!' || t[e - 1] == '?')) e--;
    return e;
}

unsigned url_next(const u16 *t, unsigned n, unsigned from, unsigned *start)
{
    unsigned i;

    for (i = from; i < n; i++) {
        unsigned after = scheme_end(t, n, i), e;

        if (after == 0) continue;
        e = url_end(t, n, after);
        if (e > after) { *start = i; return e - i; }
        i = after;
    }
    return 0;
}

unsigned url_at(const u16 *t, unsigned n, unsigned pos, unsigned *start)
{
    unsigned s, len;

    if (pos >= n) return 0;
    s = pos;
    while (s > 0 && pos - s < 2000 && !stop_char(t[s - 1])) s--;           /* back to where the run of address characters begins */
    for (; s <= pos; s++) {                                                  /* the address that starts here and reaches pos */
        unsigned after = scheme_end(t, n, s), e;

        if (after == 0) continue;
        e = url_end(t, n, after);
        if (e > after && pos < e) { *start = s; len = e - s; return len; }
    }
    return 0;
}
