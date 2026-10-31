#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test.h"
#include "edit.h"
#include "langmodes.h"

static unsigned widen(const char *s, u16 *out)
{
    unsigned n = 0;
    while (s[n]) { out[n] = (unsigned char)s[n]; n++; }
    return n;
}

static const char *narrow(const u16 *u, unsigned n)
{
    static char buf[1024];
    unsigned i;
    for (i = 0; i < n; i++) buf[i] = (char)u[i];
    buf[n] = '\0';
    return buf;
}

static const char *shift(const char *text, int dir, int spaces, unsigned width)
{
    u16 t[512], *out;
    unsigned n = widen(text, t), outlen;
    if (!edit_shift_lines(t, n, dir, spaces, width, &out, &outlen)) return "UNCHANGED";
    {
        static char r[1024];
        strcpy(r, narrow(out, outlen));
        free(out);
        return r;
    }
}

static const char *comment(const char *text, const char *pre, const char *suf, int un)
{
    u16 t[512], p[16], s[16], *out;
    unsigned n = widen(text, t), np = widen(pre, p), ns = widen(suf, s), outlen;
    if (!edit_comment_lines(t, n, p, np, s, ns, un, &out, &outlen)) return "UNCHANGED";
    {
        static char r[1024];
        strcpy(r, narrow(out, outlen));
        free(out);
        return r;
    }
}

static const char *indent(const char *before, int smart, int spaces, unsigned width)
{
    u16 t[128], out[64];
    unsigned n = widen(before, t), k = edit_newline_indent(t, n, smart, spaces, width, out, 64);
    return narrow(out, k);
}

int main(void)
{
    u16 t[64];
    const char *o, *c;

    CHECK(strcmp(shift("a\nb", 1, 0, 4), "\ta\n\tb") == 0);
    CHECK(strcmp(shift("a\n\nb\n", 1, 1, 2), "  a\n\n  b\n") == 0);                    /* empty lines stay empty */
    CHECK(strcmp(shift("\ta\n\t\tb", -1, 0, 4), "a\n\tb") == 0);
    CHECK(strcmp(shift("    a\n  b\nc", -1, 1, 4), "a\nb\nc") == 0);
    CHECK(strcmp(shift("      a", -1, 1, 4), "  a") == 0);
    CHECK(strcmp(shift("a\nb", -1, 0, 4), "UNCHANGED") == 0);

    CHECK(strcmp(comment("a\n  b\n\nc", "#", "", 0), "# a\n#   b\n\n# c") == 0);
    CHECK(strcmp(comment("  a\n    b\n\n  c", "#", "", 0), "  # a\n  #   b\n\n  # c") == 0);
    CHECK(strcmp(comment("a\nb", "/*", "*/", 0), "/* a */\n/* b */") == 0);
    CHECK(strcmp(comment("# a\n  # b\nc", "#", "", 1), "a\n  b\nc") == 0);
    CHECK(strcmp(comment("/* a */\n/* b */", "/*", "*/", 1), "a\nb") == 0);
    CHECK(strcmp(comment("#a", "#", "", 1), "a") == 0);
    CHECK(strcmp(comment("a\nb", "#", "", 1), "UNCHANGED") == 0);
    CHECK(strcmp(comment("\n\n", "#", "", 0), "UNCHANGED") == 0);
    CHECK(strcmp(comment("//x\n  // y", "//", "", 1), "x\n  y") == 0);

    CHECK(strcmp(indent("    foo();", 'b', 0, 4), "    ") == 0);
    CHECK(strcmp(indent("\tfoo();", 'b', 0, 4), "\t") == 0);
    CHECK(strcmp(indent("if (x) {", 'b', 0, 4), "\t") == 0);
    CHECK(strcmp(indent("  if (x) {  ", 'b', 1, 4), "      ") == 0);
    CHECK(strcmp(indent("  if (x) {", 0, 1, 4), "  ") == 0);                              /* no smart indent */
    CHECK(strcmp(indent("def f():", 'c', 1, 4), "    ") == 0);
    CHECK(strcmp(indent("x = {", 'c', 1, 4), "") == 0);
    CHECK(strcmp(indent("", 'b', 0, 4), "") == 0);

    CHECK(edit_outdent_amount(t, widen("\t", t), 4) == 1);
    CHECK(edit_outdent_amount(t, widen("      ", t), 4) == 4);
    CHECK(edit_outdent_amount(t, widen("  ", t), 4) == 2);
    CHECK(edit_outdent_amount(t, widen("  x", t), 4) == 0);
    CHECK(edit_outdent_amount(t, 0, 4) == 0);
    CHECK(edit_column(t, widen("a\tb", t)) == 9);

    CHECK(lang_comment_style("C", &o, &c) && strcmp(o, "/*") == 0 && strcmp(c, "*/") == 0);
    CHECK(lang_comment_style("Python", &o, &c) && strcmp(o, "#") == 0 && c[0] == 0);
    CHECK(!lang_comment_style("Generic", &o, &c));
    CHECK(!lang_comment_style(NULL, &o, &c));
    CHECK(lang_smart_indent("Python") == 'c' && lang_smart_indent("C") == 'b' && lang_smart_indent("Plist") == 0);
    CHECK(lang_word_kind("Shell") == 1 && lang_word_kind("Csh") == 2 && lang_word_kind("C") == 3 && lang_word_kind("Python") == 0 && lang_word_kind(NULL) == 0);
    CHECK(lang_fold_style("Python") == 'i' && lang_fold_style("Shell") == 'w' && lang_fold_style("C") == 'b' && lang_fold_style(NULL) == 'b');
    TEST_DONE("edit");
}
