#include "test.h"
#include "../core/complete.h"
#include <stdlib.h>

static unsigned w16(const char *s, u16 *o)
{
    unsigned i;

    for (i = 0; s[i]; i++) o[i] = (u16)(unsigned char)s[i];
    return i;
}

static int is(const CompList *l, unsigned i, const char *s)
{
    unsigned k;

    if (i >= l->n || l->v[i].len != strlen(s)) return 0;
    for (k = 0; s[k]; k++) if (l->v[i].w[k] != (u16)(unsigned char)s[k]) return 0;
    return 1;
}

int main(void)
{
    u16 t[256], pre[32];
    CompList l;
    unsigned n, plen;

    n = w16("foo foobar foo_baz x foobar fo", t);
    CHECK(comp_prefix_len(t, n, n) == 2);
    CHECK(comp_prefix_len(t, n, 3) == 3);                        /* "foo" */
    CHECK(comp_prefix_len(t, n, 4) == 0);                        /* after the space */
    comp_init(&l, 0);
    plen = comp_prefix_len(t, n, n);
    CHECK(comp_add_text_words(&l, t, n, n - plen, n, 50) == 3);
    CHECK(is(&l, 0, "foobar") && is(&l, 1, "foo_baz") && is(&l, 2, "foo"));        /* nearest first, no repeats */
    comp_free(&l);

    n = w16("fo x foobar y foo", t);                           /* forwards too, after the backward ones */
    comp_init(&l, 0);
    comp_add_text_words(&l, t, n, 0, 2, 50);                      /* the caret after "fo" at the start */
    CHECK(l.n == 2 && is(&l, 0, "foobar") && is(&l, 1, "foo"));
    comp_free(&l);

    n = w16("ab|ar abcd abbar", t);
    comp_init(&l, 0);
    n = w16("abar xx abcd abbar", t);                            /* caret inside "abar", after "ab": the rest of that word is skipped */
    comp_add_text_words(&l, t, n, 0, 2, 50);
    CHECK(l.n == 2 && is(&l, 0, "abcd") && is(&l, 1, "abbar"));
    comp_free(&l);

    n = w16("12 123abc 12x", t);                                 /* words that start with a digit are numbers */
    comp_init(&l, 0);
    w16("1", pre);
    comp_add_words_of(&l, t, n, pre, 1, 50);
    CHECK(l.n == 0);
    CHECK(comp_prefix_len(t, 2, 2) == 0);
    comp_free(&l);

    comp_init(&l, 1);                                            /* ignoring case */
    n = w16("Foo fOOd foo", t);
    w16("fo", pre);
    comp_add_words_of(&l, t, n, pre, 2, 50);
    CHECK(l.n == 3 && is(&l, 0, "Foo") && is(&l, 1, "fOOd") && is(&l, 2, "foo"));      /* spelt differently: all kept */
    comp_free(&l);

    comp_init(&l, 0);
    w16("wh", pre);
    CHECK(comp_add_syntax_keywords(&l, "Pattern = \"{\";\n Pattern = \"<while>\";\n Pattern = \"<while>\";\n Pattern = \"<what>\";\n Pattern = \"<(a|b)>\";\n Pattern = \"<if>\";", pre, 2, 50) == 2);
    CHECK(is(&l, 0, "while") && is(&l, 1, "what"));
    comp_free(&l);

    comp_init(&l, 0);                                            /* the limit */
    n = w16("aa1 aa2 aa3 aa4 aa5 a", t);
    w16("a", pre);
    comp_add_words_of(&l, t, n, pre, 1, 3);
    CHECK(l.n == 3);
    comp_free(&l);
    TEST_DONE("test_complete");
}
