#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test.h"
#include "foldlines.h"
#include "fold.h"
#include "words.h"

static unsigned widen(const char *s, u16 *out)
{
    unsigned n = 0;
    while (s[n]) { out[n] = (unsigned char)s[n]; n++; }
    return n;
}

static int state_at(const FoldLines *f, const char *text, const char *needle)
{
    const char *p = strstr(text, needle);
    unsigned ls = (unsigned)(p - text);
    while (ls > 0 && text[ls - 1] != '\n') ls--;
    return foldlines_state(f, ls);
}

int main(void)
{
    u16 t[4096], tok[FOLD_MAX_TOKEN];
    FoldLines f;
    unsigned n, tn;
    const char *c = "int f(void)\n{\n  if (x) {\n    a;\n  }\n  g(\"{\\n\");  /* { */\n}\nint h() { return 1; }\nstruct S {\n  int a;\n};\n";
    const char *py = "import os\n\ndef f(x):\n    a = 1\n    if x:\n        b = 2\n    return a\n\nclass K:\n    pass\nprint(1)\n";
    const char *sh = "if true; then\n  for i in a; do\n    echo $i\n  done\nfi\necho end\n";
    char folded[256];

    n = widen(c, t);
    CHECK(foldlines_scan(t, n, 'b', 1, 0, &f));
    CHECK(f.count == 3);
    CHECK(state_at(&f, c, "{\n  if") == 1);                  /* the lone brace line (Allman style) */
    CHECK(state_at(&f, c, "  if (x)") == 1);                 /* the inner block */
    CHECK(state_at(&f, c, "struct S") == 1);
    CHECK(state_at(&f, c, "int f(void)") == 0);
    CHECK(state_at(&f, c, "int h()") == 0);                  /* one line */
    CHECK(state_at(&f, c, "  g(") == 0);                     /* a brace in a string and in a comment */
    foldlines_free(&f);

    n = widen(py, t);
    CHECK(foldlines_scan(t, n, 'i', 0, 0, &f));
    CHECK(state_at(&f, py, "def f") == 1 && state_at(&f, py, "    if x") == 1 && state_at(&f, py, "class K") == 1);
    CHECK(state_at(&f, py, "import") == 0 && state_at(&f, py, "print") == 0 && state_at(&f, py, "    a = 1") == 0);
    CHECK(f.count == 3);
    foldlines_free(&f);

    n = widen(sh, t);
    CHECK(foldlines_scan(t, n, 'w', 0, WORDS_SH, &f));
    CHECK(f.count == 2 && state_at(&f, sh, "if true") == 1 && state_at(&f, sh, "  for") == 1);
    foldlines_free(&f);

    /* a marker makes its line a "+" */
    tn = fold_make_token(tok, 5, 3);
    sprintf(folded, "void f() {");
    n = widen(folded, t);
    memcpy(t + n, tok, tn * sizeof(u16));
    n += tn;
    t[n++] = '}';
    t[n++] = '\n';
    n += widen("int x;\n", t + n);
    CHECK(foldlines_scan(t, n, 'b', 1, 0, &f));
    CHECK(f.count == 1 && f.start[0] == 0 && f.collapsed[0] == 1 && foldlines_state(&f, 0) == 2);
    foldlines_free(&f);

    n = widen("", t);
    CHECK(foldlines_scan(t, n, 'b', 1, 0, &f) && f.count == 0 && foldlines_state(&f, 0) == 0);
    foldlines_free(&f);
    TEST_DONE("foldlines");
}
