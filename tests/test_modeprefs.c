#include "test.h"
#include "../core/modeprefs.h"

int main(void)
{
    ModePrefs mp;
    char buf[512];
    unsigned n;

    modeprefs_clear(&mp);
    CHECK(modeprefs_get(&mp, "Python", MP_INDENT) == MP_UNSET);
    CHECK(modeprefs_set(&mp, "Python", MP_INDENT, 4) == 0);
    CHECK(modeprefs_set(&mp, "Python", MP_SPACES, 1) == 0);
    CHECK(modeprefs_set(&mp, "Makefile", MP_SPACES, 0) == 0);
    CHECK(modeprefs_get(&mp, "Python", MP_INDENT) == 4);
    CHECK(modeprefs_get(&mp, "Python", MP_SPACES) == 1);
    CHECK(modeprefs_get(&mp, "Python", MP_WRAP) == MP_UNSET);
    CHECK(modeprefs_get(&mp, "Makefile", MP_SPACES) == 0);
    CHECK(modeprefs_get(&mp, "C", MP_SPACES) == MP_UNSET);

    CHECK(modeprefs_set(&mp, "Python", MP_INDENT, 0) == -1);          /* out of range */
    CHECK(modeprefs_set(&mp, "Python", MP_INDENT, 17) == -1);
    CHECK(modeprefs_set(&mp, "Python", MP_WRAP, 2) == -1);
    CHECK(modeprefs_set(&mp, "Python", 9, 1) == -1);
    CHECK(modeprefs_set(&mp, "", MP_WRAP, 1) == -1);
    CHECK(modeprefs_set(&mp, "A B", MP_WRAP, 1) == -1);
    CHECK(modeprefs_get(&mp, "Python", MP_INDENT) == 4);

    n = modeprefs_format(&mp, buf, sizeof buf);
    CHECK(n == strlen(buf));
    CHECK(strcmp(buf, "Python indent=4 spaces=1\nMakefile spaces=0\n") == 0);
    CHECK(modeprefs_format(&mp, buf, 5) == n);                       /* too small: reports what is needed, does not overrun */

    {
        ModePrefs q;

        modeprefs_format(&mp, buf, sizeof buf);
        modeprefs_parse(&q, buf);
        CHECK(q.n == 2);
        CHECK(modeprefs_get(&q, "Python", MP_INDENT) == 4);
        CHECK(modeprefs_get(&q, "Makefile", MP_SPACES) == 0);
        modeprefs_parse(&q, "Ruby indent=2 wrap=1 junk=3 auto=7\nbad\n\n  Perl   auto=0  \nC indent=99\n");
        CHECK(q.n == 2);                                               /* "bad" and the all-invalid C line add nothing */
        CHECK(modeprefs_get(&q, "Ruby", MP_INDENT) == 2);
        CHECK(modeprefs_get(&q, "Ruby", MP_WRAP) == 1);
        CHECK(modeprefs_get(&q, "Ruby", MP_AUTO) == MP_UNSET);
        CHECK(modeprefs_get(&q, "Perl", MP_AUTO) == 0);
        CHECK(modeprefs_get(&q, "Python", MP_INDENT) == MP_UNSET);     /* parse replaces */
    }

    CHECK(modeprefs_set(&mp, "Python", MP_INDENT, MP_UNSET) == 0);
    CHECK(mp.n == 2);
    CHECK(modeprefs_set(&mp, "Python", MP_SPACES, MP_UNSET) == 0);    /* nothing left: the entry goes */
    CHECK(mp.n == 1);
    CHECK(modeprefs_find(&mp, "Python") == NULL);
    CHECK(modeprefs_get(&mp, "Makefile", MP_SPACES) == 0);
    CHECK(modeprefs_set(&mp, "Nothing", MP_WRAP, MP_UNSET) == 0 && mp.n == 1);
    TEST_DONE("test_modeprefs");
}
