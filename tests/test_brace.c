#include <stdio.h>
#include <string.h>
#include "test.h"
#include "brace.h"

static unsigned widen(const char *s, u16 *out)
{
    unsigned n = 0;
    while (s[n]) { out[n] = (unsigned char)s[n]; n++; }
    return n;
}

/* The partner of the bracket at pos, or -1. */
static int m(const char *text, unsigned pos, int c_aware)
{
    u16 t[512];
    unsigned n = widen(text, t), r;
    return brace_match(t, n, pos, c_aware, &r) ? (int)r : -1;
}

int main(void)
{
    CHECK(m("(a)", 0, 0) == 2 && m("(a)", 2, 0) == 0);
    CHECK(m("f(a(b)c)", 1, 0) == 7 && m("f(a(b)c)", 7, 0) == 1);
    CHECK(m("f(a(b)c)", 3, 0) == 5 && m("f(a(b)c)", 5, 0) == 3);
    CHECK(m("{ [ ( ) ] }", 0, 0) == 10 && m("{ [ ( ) ] }", 2, 0) == 8);
    CHECK(m("(a", 0, 0) == -1 && m("a)", 1, 0) == -1);
    CHECK(m("abc", 1, 0) == -1);                                   /* not a bracket */
    CHECK(m("(]", 0, 0) == -1);                                    /* only its own kind */

    /* C aware: strings, character constants and comments do not count */
    CHECK(m("{ \"}\" }", 0, 1) == 6);
    CHECK(m("{ '}' }", 0, 1) == 6);
    CHECK(m("{ '\\'' }", 0, 1) == 7);
    CHECK(m("{ /* } */ }", 0, 1) == 10);
    CHECK(m("{ // }\n}", 0, 1) == 7);
    CHECK(m("{ \"\\\"}\" }", 0, 1) == 8);                          /* an escaped quote inside a string */
    CHECK(m("{ \"}\" }", 6, 1) == 0);                              /* and backwards */
    CHECK(m("{ { } /* } */ }", 14, 1) == 0);
    CHECK(m("x \"(\" y", 3, 1) == -1);                             /* a bracket in a string with no partner */
    CHECK(m("\"(a)\"", 1, 1) == 3);                                /* a bracket in a string matches its own kind */
    CHECK(m("if (a) { b(); }", 7, 1) == 14);
    CHECK(m("if (a) { b(); }", 14, 1) == 7);
    CHECK(m("(()", 0, 1) == -1);                                   /* unbalanced */
    CHECK(m("())", 2, 1) == -1);
    {
        u16 u[128];
        unsigned pos, op, k;
        const char *cases[] = { "int f() { return (1); }", "}", "a ( b ]", "void f() {\n if (x) {\n}\n", "s = \"{\"; /* ( */ // [\nx", "" };
        int expect[] = { 0, BRACE_STRAY, BRACE_MISMATCH, BRACE_UNCLOSED, 0, 0 };
        unsigned at[] = { 0, 0, 6, 9, 0, 0 };
        int i;

        for (i = 0; i < 6; i++) {
            for (k = 0; cases[i][k]; k++) u[k] = (u16)(unsigned char)cases[i][k];
            CHECK(brace_find_unbalanced(u, k, 1, &pos, &op) == expect[i]);
            if (expect[i]) CHECK(pos == at[i]);
        }
        for (k = 0; "s = \"{\"\n"[k]; k++) u[k] = (u16)(unsigned char)"s = \"{\"\n"[k];
        CHECK(brace_find_unbalanced(u, k, 0, &pos, &op) == BRACE_UNCLOSED && pos == 5);     /* plain text counts it */
        for (k = 0; "a ( b ]"[k]; k++) u[k] = (u16)(unsigned char)"a ( b ]"[k];
        brace_find_unbalanced(u, k, 1, &pos, &op);
        CHECK(op == 2);
    }
    TEST_DONE("brace");
}
