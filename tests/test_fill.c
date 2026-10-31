#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test.h"
#include "fill.h"
#include "rect.h"

static unsigned widen(const char *s, u16 *out)
{
    unsigned n = 0;
    while (s[n]) { out[n] = (unsigned char)s[n]; n++; }
    return n;
}

static char *narrow(const u16 *u, unsigned n)
{
    static char buf[4][2048];
    static int which;
    char *b = buf[which++ & 3];
    unsigned i;
    for (i = 0; i < n; i++) b[i] = (char)u[i];
    b[n] = '\0';
    return b;
}

static char *fill(const char *text, unsigned width)
{
    u16 t[2048], *out;
    unsigned n = widen(text, t), outlen;
    if (!fill_text(t, n, width, &out, &outlen)) return "UNCHANGED";
    {
        char *r = narrow(out, outlen);
        free(out);
        return r;
    }
}

static char *extract(const char *text, unsigned c0, unsigned c1)
{
    u16 t[2048], *out;
    unsigned n = widen(text, t), outlen;
    char *r;
    rect_extract(t, n, c0, c1, &out, &outlen);
    r = narrow(out, outlen);
    free(out);
    return r;
}

static char *replace(const char *text, unsigned c0, unsigned c1, const char *ins, int per_line)
{
    u16 t[2048], i[512], *out;
    unsigned n = widen(text, t), ni = widen(ins, i), outlen;
    char *r;
    rect_replace(t, n, c0, c1, i, ni, per_line, &out, &outlen);
    r = narrow(out, outlen);
    free(out);
    return r;
}

static int find(const char *text, unsigned pos, unsigned *s, unsigned *e)
{
    u16 t[2048];
    unsigned n = widen(text, t);
    return fill_find_paragraph(t, n, pos, s, e);
}

int main(void)
{
    unsigned s, e;

    /* filling */
    CHECK(strcmp(fill("aaa bbb ccc ddd eee", 10), "aaa bbb\nccc ddd\neee") == 0);
    CHECK(strcmp(fill("aaa bbb\nccc ddd\neee", 80), "aaa bbb ccc ddd eee") == 0);
    CHECK(strcmp(fill("aaa bbb ccc", 80), "UNCHANGED") == 0);
    CHECK(strcmp(fill("one\n\ntwo three four five six", 12), "UNCHANGED") != 0);
    CHECK(strcmp(fill("one\n\ntwo three four five six", 12), "one\n\ntwo three\nfour five\nsix") == 0);
    CHECK(strcmp(fill("  indented text goes on and on\n  and on", 20), "  indented text goes\n  on and on and on") == 0);
    CHECK(strcmp(fill("// a comment that is rather long\n// and more", 20), "// a comment that is\n// rather long and\n// more") == 0);
    CHECK(strcmp(fill("# x  y   z", 80), "# x y z") == 0);
    CHECK(strcmp(fill("averyveryverylongwordindeed and short", 10), "averyveryverylongwordindeed\nand short") == 0);
    CHECK(strcmp(fill("a b c\n//\nd e f\n", 80), "UNCHANGED") == 0);            /* a lone leader separates paragraphs */
    CHECK(strcmp(fill("first line\n    hanging one\n    hanging two", 14), "first line\n    hanging\n    one\n    hanging\n    two") == 0);
    CHECK(strcmp(fill("", 10), "UNCHANGED") == 0);
    CHECK(strcmp(fill("trailing blank \n", 80), "trailing blank\n") == 0);
    /* paragraph search */
    CHECK(find("aa\nbb\n\ncc\ndd\n\nee", 4, &s, &e) && s == 0 && e == 5);
    CHECK(find("aa\nbb\n\ncc\ndd\n\nee", 8, &s, &e) && s == 7 && e == 12);
    CHECK(find("aa\nbb\n\ncc\ndd\n\nee", 15, &s, &e) && s == 14 && e == 16);
    CHECK(!find("aa\n\nbb", 3, &s, &e));
    CHECK(find("aa", 2, &s, &e) && s == 0 && e == 2);

    /* rectangles */
    CHECK(strcmp(extract("abcdef\nghijkl\nmn", 1, 4), "bcd\nhij\nn") == 0);
    CHECK(strcmp(extract("abc\n\nxyzw", 2, 4), "c\n\nzw") == 0);
    CHECK(strcmp(extract("a\tb\nc", 8, 9), "b\n") == 0);
    CHECK(strcmp(extract("a\tb\nc", 0, 1), "a\nc") == 0);
    CHECK(strcmp(replace("abcdef\nghijkl", 1, 3, "", 0), "adef\ngjkl") == 0);
    CHECK(strcmp(replace("abcdef\nghijkl", 1, 3, "XY", 0), "aXYdef\ngXYjkl") == 0);
    CHECK(strcmp(replace("abcdef\nghijkl", 2, 2, "-", 0), "ab-cdef\ngh-ijkl") == 0);
    CHECK(strcmp(replace("abcdef\nx", 3, 3, "-", 0), "abc-def\nx  -") == 0);     /* padded */
    CHECK(strcmp(replace("abcdef\nghijkl", 2, 2, "12\n34", 1), "ab12cdef\ngh34ijkl") == 0);
    CHECK(strcmp(replace("abc\ndef", 1, 1, "1\n2\n3", 1), "a1bc\nd2ef\n 3") == 0);   /* extra lines go below, at the column */
    CHECK(strcmp(replace("abc\ndef\nghi", 1, 1, "1", 1), "a1bc\ndef\nghi") == 0);
    CHECK(strcmp(replace("a\tb", 8, 9, "X", 0), "a\tX") == 0);
    CHECK(strcmp(replace("ab", 5, 5, "", 0), "ab") == 0);
    {
        u16 w[8];
        unsigned wn = widen("a\tb", w);
        CHECK(rect_column_of_index(w, wn, 2) == 8);
    }
    TEST_DONE("fill/rect");
}
