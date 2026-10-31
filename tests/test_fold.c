#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test.h"
#include "fold.h"

static unsigned widen(const char *s, u16 *out)
{
    unsigned n = 0;
    while (s[n]) { out[n] = (unsigned char)s[n]; n++; }
    return n;
}

static int block(const char *text, unsigned pos, unsigned *o, unsigned *c)
{
    u16 t[2048];
    return fold_find_block(t, widen(text, t), pos, 1, o, c);
}

int main(void)
{
    u16 t[512], tok[FOLD_MAX_TOKEN];
    unsigned n, tn, st, en, lines, id, o, c, *os, *cs, k;
    const char *src = "int f(void)\n{\n  if (x) {\n    a;\n  }\n  return 0;\n}\nint g() { return 1; }\n";

    /* tokens */
    tn = fold_make_token(tok, 12, 7);
    CHECK(tn == 18 || tn == 17 || tn > 10);
    memcpy(t, tok, tn * sizeof(u16));
    CHECK(fold_token_find(t, tn, 0, &st, &en, &lines, &id) && st == 0 && en == tn && lines == 12 && id == 7);
    n = widen("a {", t);
    memcpy(t + n, tok, tn * sizeof(u16));
    n += tn;
    t[n++] = '}';
    CHECK(fold_token_find(t, n, 0, &st, &en, &lines, &id) && st == 3 && en == n - 1 && lines == 12 && id == 7);
    CHECK(!fold_token_find(t, n, 4, &st, &en, &lines, &id));
    CHECK(fold_hidden_lines(t, n, n) == 12);
    CHECK(fold_hidden_lines(t, n, 3) == 0);
    CHECK(fold_hidden_lines(t, n, 4) == 12);                   /* it starts before the limit, even if it ends after it */
    n = widen("x ... 3 lines ~ y", t);
    CHECK(!fold_token_find(t, n, 0, &st, &en, &lines, &id));    /* no number after the tilde */
    n = widen("x ... 3 lines 4 ", t);
    CHECK(!fold_token_find(t, n, 0, &st, &en, &lines, &id));
    n = widen(" ... 3 lines ~4 ", t);
    CHECK(fold_token_find(t, n, 0, &st, &en, &lines, &id) && lines == 3 && id == 4 && en == n);
    CHECK(fold_make_token(tok, 123456, 99) < FOLD_MAX_TOKEN);

    /* finding the block */
    {
        const char *p = strstr(src, "if (x) {");
        unsigned f_open = (unsigned)(strchr(src, '{') - src);                 /* the lone "{" on the second line */
        unsigned f_close = (unsigned)(strstr(src, "}\nint g") - src);
        unsigned want_open = (unsigned)(p - src) + 7;
        CHECK(block(src, 0, &o, &c) && o == f_open && c == f_close);          /* "int f(void)": Allman style, the brace is on the next line */
        CHECK(block(src, f_open, &o, &c) && o == f_open && c == f_close);     /* on the lone "{" */
        CHECK(block(src, (unsigned)(p - src), &o, &c) && o == want_open && src[c] == '}');
        CHECK(block(src, (unsigned)(strstr(src, "a;") - src), &o, &c) && o == want_open);     /* inside: the innermost */
        CHECK(block(src, (unsigned)(strstr(src, "return 0") - src), &o, &c) && o == f_open);   /* after the inner block: the outer */
        CHECK(block(src, f_close, &o, &c) && o == f_open && c == f_close);                      /* on the closing line */
        n = widen(src, t);
        k = fold_top_blocks(t, n, 1, &os, &cs);
        CHECK(k == 1 && os[0] == f_open && cs[0] == f_close);                  /* g's block is on one line */
        free(os); free(cs);
    }
    CHECK(!block("int g() { return 1; }\n", 5, &o, &c));                    /* one line: nothing to fold */
    CHECK(!block("no braces\n", 3, &o, &c));
    CHECK(block("a { // }\n  b;\n}\n", 0, &o, &c) && o == 2 && c == 14);        /* a brace in a comment is not counted */

    /* the top-level blocks */
    n = widen("a {\n}\nb {\n x {\n }\n}\nc { \"}\" /* } */\n}\n", t);
    k = fold_top_blocks(t, n, 1, &os, &cs);
    CHECK(k == 3 && t[os[0]] == '{' && t[cs[2]] == '}');
    free(os); free(cs);
    n = widen("", t);
    CHECK(fold_top_blocks(t, n, 1, &os, &cs) == 0);
    /* JSON arrays fold too, with the bracket flag */
    {
        const char *js = "{\n  \"a\": [\n    1,\n    2\n  ],\n  \"b\": \"]\"\n}\n";
        unsigned o2, c2, *os2, *cs2, kk;
        n = widen(js, t);
        CHECK(fold_find_block(t, n, (unsigned)(strstr(js, "\"a\"") - js), FOLD_CAWARE | FOLD_BRACKETS, &o2, &c2) && js[o2] == '[' && js[c2] == ']');
        CHECK(fold_find_block(t, n, (unsigned)(strstr(js, "\"a\"") - js), FOLD_CAWARE, &o2, &c2) && js[o2] == '{' && o2 == 0);       /* without it: the enclosing brace */
        CHECK(fold_find_block(t, n, (unsigned)(strstr(js, "    1") - js), FOLD_CAWARE | FOLD_BRACKETS, &o2, &c2) && js[o2] == '[');
        kk = fold_top_blocks(t, n, FOLD_CAWARE | FOLD_BRACKETS, &os2, &cs2);
        CHECK(kk == 1 && os2[0] == 0 && js[cs2[0]] == '}');
        free(os2); free(cs2);
    }
    /* folding by indentation */
    {
        const char *py = "import os\n\ndef f(x):\n    a = 1\n\n    if x:\n        b = 2\n        c = 3\n    return a\n\nclass K:\n    def m(self):\n        pass\n\nprint(1)\n";
        unsigned h1, h2, *hs2, *he2, cnt;
        const char *p;
        n = widen(py, t);
        p = strstr(py, "def f");
        CHECK(fold_indent_block(t, n, (unsigned)(p - py), &h1, &h2) && t[h1] == '\n' && h1 == (unsigned)(strstr(py, "\n    a = 1") - py));
        CHECK(h2 == (unsigned)(strstr(py, "\n\nclass") - py));                          /* up to the end of "return a", not the blank lines after it */
        CHECK(fold_indent_block(t, n, (unsigned)(strstr(py, "b = 2") - py), &h1, &h2) && h1 == (unsigned)(strstr(py, "\n        b") - py));   /* inside: the nearest header above */
        CHECK(h2 == (unsigned)(strstr(py, "\n    return") - py));
        CHECK(fold_indent_block(t, n, (unsigned)(strstr(py, "if x") - py), &h1, &h2) && h1 == (unsigned)(strstr(py, "\n        b") - py));
        CHECK(!fold_indent_block(t, n, 0, &h1, &h2));                                      /* "import os": no block, nothing above */
        CHECK(!fold_indent_block(t, n, (unsigned)(strstr(py, "print") - py), &h1, &h2));
        CHECK(fold_indent_block(t, n, (unsigned)(strstr(py, "\n\n    if") - py) + 1, &h1, &h2));   /* a blank line inside a block: that block */
        cnt = fold_indent_top(t, n, &hs2, &he2);
        CHECK(cnt == 2 && hs2[0] < he2[0] && hs2[1] > he2[0]);
        free(hs2); free(he2);
        n = widen("", t);
        CHECK(fold_indent_top(t, n, &hs2, &he2) == 0);
        n = widen("a:\n\tb\n\tc\nd\n", t);
        CHECK(fold_indent_block(t, n, 0, &h1, &h2) && h1 == 2 && h2 == 8);                  /* tabs */
    }
    TEST_DONE("fold");
}
