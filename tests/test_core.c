#include <stdio.h>
#include <string.h>
#include "test.h"
#include <stdlib.h>
#include "langmodes.h"
#include "eol.h"

static int str_eq(const char *a, const char *b)
{
    if (a == NULL || b == NULL) return a == b;
    return strcmp(a, b) == 0;
}

int main(void)
{
    CHECK(str_eq(lang_mode_for("/home/me/main.c", NULL), "C"));
    CHECK(str_eq(lang_mode_for("foo.H", NULL), "C-Header"));
    CHECK(str_eq(lang_mode_for("/a.b/x.cpp", NULL), "C++"));
    CHECK(str_eq(lang_mode_for("Thing.m", NULL), "ObjC"));
    CHECK(str_eq(lang_mode_for("Thing.mm", NULL), "ObjC++"));
    CHECK(str_eq(lang_mode_for("/usr/src/Makefile", NULL), "GNUmakefile"));
    CHECK(str_eq(lang_mode_for("Makefile.openstep", NULL), "GNUmakefile"));
    CHECK(str_eq(lang_mode_for("ChangeLog", NULL), "ChangeLog"));
    CHECK(str_eq(lang_mode_for("Info.plist", NULL), "Plist"));
    CHECK(str_eq(lang_mode_for("README", NULL), NULL));
    CHECK(str_eq(lang_mode_for(".c", NULL), NULL));          /* a hidden file, not an extension */
    CHECK(str_eq(lang_mode_for("name.", NULL), NULL));
    CHECK(str_eq(lang_mode_for(NULL, NULL), NULL));
    {
        char a[] = "one\r\ntwo\r\nthree";
        char b[] = "x\ry\rz\r";
        char c[] = "a\nb\r\nc\rd";
        char d[] = "p\0q\n";
        char out[64];
        int mixed = 0;
        size_t n;

        CHECK(eol_detect(a, strlen(a), &mixed) == EOL_CRLF && !mixed);
        CHECK(eol_detect(b, strlen(b), &mixed) == EOL_CR && !mixed);
        CHECK(eol_detect(c, strlen(c), &mixed) == EOL_LF && mixed);
        CHECK(eol_detect("", 0, &mixed) == EOL_LF && !mixed);
        n = eol_normalize(a, strlen(a));
        CHECK(n == 13 && memcmp(a, "one\ntwo\nthree", 13) == 0);
        n = eol_normalize(b, strlen(b));
        CHECK(n == 6 && memcmp(b, "x\ny\nz\n", 6) == 0);
        n = eol_normalize(c, strlen(c));
        CHECK(n == 7 && memcmp(c, "a\nb\nc\nd", 7) == 0);
        n = eol_normalize(d, 4);
        CHECK(n == 4 && memcmp(d, "p q\n", 4) == 0);
        CHECK(eol_expanded_size("a\nb\n", 4, EOL_CRLF) == 6 && eol_expanded_size("a\nb\n", 4, EOL_CR) == 4);
        n = eol_expand("a\nb\n", 4, EOL_CRLF, out);
        CHECK(n == 6 && memcmp(out, "a\r\nb\r\n", 6) == 0);
        n = eol_expand("a\nb\n", 4, EOL_CR, out);
        CHECK(n == 4 && memcmp(out, "a\rb\r", 4) == 0);
    }
    TEST_DONE("core");
}
