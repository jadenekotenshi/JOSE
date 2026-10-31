#include "test.h"
#include "../core/grep.h"
#include <stdlib.h>

static unsigned to16(const char *s, u16 *o)
{
    unsigned i = 0;

    for (; s[i]; i++) o[i] = (u16)(unsigned char)s[i];
    return i;
}

static int eq16(const u16 *a, unsigned n, const char *s)
{
    unsigned i;

    if (n != strlen(s)) return 0;
    for (i = 0; i < n; i++) if (a[i] != (u16)(unsigned char)s[i]) return 0;
    return 1;
}

int main(void)
{
    u16 pat[64], txt[512], rep[64], *out;
    unsigned np, nt, nr, olen, k;
    char err[80];
    Search *s;
    GrepHits h = { NULL, 0, 0 };

    CHECK(glob_match_any("*.c", "main.c"));
    CHECK(!glob_match_any("*.c", "main.h"));
    CHECK(glob_match_any("*.c *.h", "main.h"));
    CHECK(glob_match_any("*.c, *.h", "x.h"));
    CHECK(glob_match_any("", "anything"));
    CHECK(glob_match_any("  ,  ", "anything"));
    CHECK(glob_match_any("Makefile*", "Makefile.openstep"));
    CHECK(!glob_match_any("Makefile*", "GNUMakefile"));
    CHECK(glob_match_any("?.c", "a.c"));
    CHECK(!glob_match_any("?.c", "ab.c"));
    CHECK(glob_match_any("a*b*c", "aXXbYYc"));
    CHECK(!glob_match_any("a*b*c", "aXXbYY"));
    CHECK(glob_match_any("*", ""));
    CHECK(!glob_match_any("*.C", "main.c"));

    nt = to16("one foo\ntwo\nfoo foo three\n\nlast foo", txt);
    np = to16("foo", pat);
    s = search_new(pat, np, 0, err, sizeof err);
    CHECK(s != NULL);
    k = grep_text(s, txt, nt, &h, 100);
    CHECK(k == 3 && h.n == 3);
    CHECK(h.hit[0].line == 1 && h.hit[0].lstart == 0 && h.hit[0].lend == 7 && h.hit[0].mstart == 4);
    CHECK(h.hit[1].line == 3 && h.hit[1].lstart == 12 && h.hit[1].mstart == 12);
    CHECK(h.hit[2].line == 5 && h.hit[2].lend == nt);
    grep_free(&h);
    k = grep_text(s, txt, nt, &h, 2);
    CHECK(k == 2 && h.n == 2);
    grep_free(&h);

    nr = to16("[\\0]", rep);
    CHECK(grep_replace(s, txt, nt, rep, nr, 1, &out, &olen) == 4);
    CHECK(eq16(out, olen, "one [\\0]\ntwo\n[\\0] [\\0] three\n\nlast [\\0]"));
    free(out);
    CHECK(grep_replace(s, txt, nt, rep, nr, 0, &out, &olen) == 4);
    CHECK(eq16(out, olen, "one [foo]\ntwo\n[foo] [foo] three\n\nlast [foo]"));
    free(out);
    nr = to16("", rep);
    CHECK(grep_replace(s, txt, nt, rep, nr, 0, &out, &olen) == 4);
    CHECK(eq16(out, olen, "one \ntwo\n  three\n\nlast "));
    free(out);
    search_free(s);

    np = to16("zzz", pat);
    s = search_new(pat, np, 0, err, sizeof err);
    CHECK(grep_text(s, txt, nt, &h, 10) == 0 && h.n == 0);
    CHECK(grep_replace(s, txt, nt, rep, nr, 0, &out, &olen) == 0 && out == NULL);
    search_free(s);

    np = to16("^", pat);                                     /* an empty match at every line: one hit per line, no loop */
    s = search_new(pat, np, SEARCH_REGEX, err, sizeof err);
    k = grep_text(s, txt, nt, &h, 100);
    CHECK(k == 5);
    grep_free(&h);
    search_free(s);

    CHECK(grep_bytes_are_text((const unsigned char *)"plain ascii\n", 12));
    CHECK(grep_bytes_are_text((const unsigned char *)"", 0));
    CHECK(grep_bytes_are_text((const unsigned char *)"caf\xC3\xA9", 5));
    CHECK(grep_bytes_are_text((const unsigned char *)"\xE2\x82\xAC", 3));
    CHECK(!grep_bytes_are_text((const unsigned char *)"caf\xE9", 4));          /* Latin-1 */
    CHECK(!grep_bytes_are_text((const unsigned char *)"a\0b", 3));
    CHECK(!grep_bytes_are_text((const unsigned char *)"\xE2\x82", 2));         /* cut short */
    CHECK(!grep_bytes_are_text((const unsigned char *)"\xC0\x80", 2));
    CHECK(!grep_bytes_are_text((const unsigned char *)"\xFF", 1));
    TEST_DONE("test_grep");
}
