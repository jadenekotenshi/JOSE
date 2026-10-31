#include <stdio.h>
#include <string.h>
#include "test.h"
#include <stdlib.h>
#include "langmodes.h"
#include "eol.h"
#include "undo.h"

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
    CHECK(str_eq(lang_mode_for("tool.py", NULL), "Python"));
    CHECK(str_eq(lang_mode_for("a.sh", NULL), "Shell"));
    CHECK(str_eq(lang_mode_for("/home/me/.profile", NULL), "Shell"));
    CHECK(str_eq(lang_mode_for("run", "#!/bin/ksh"), "Shell"));
    CHECK(str_eq(lang_mode_for("run", "#!/bin/csh -f"), "Csh"));
    CHECK(str_eq(lang_mode_for("/root/.cshrc", NULL), "Csh"));
    CHECK(str_eq(lang_mode_for("t.pl", NULL), "Perl"));
    CHECK(str_eq(lang_mode_for("t", "#!/usr/bin/perl -w"), "Perl"));
    CHECK(str_eq(lang_mode_for("tool", "#!/usr/bin/env python"), "Python"));
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
    {
        Undo *u = undo_new(100, 0);
        UndoStep st;
        u16 a[] = { 'a' }, b[] = { 'b' }, c[] = { 'c' }, xy[] = { 'x', 'y' };
        unsigned long v0, v1, v2;

        CHECK(!undo_can_undo(u) && !undo_can_redo(u) && !undo_undo(u, &st));
        v0 = undo_version(u);
        /* typing "abc" one key at a time at 5, 6, 7 merges into one step */
        undo_record(u, 5, NULL, 0, a, 1, 1000);
        undo_record(u, 6, NULL, 0, b, 1, 1100);
        undo_record(u, 7, NULL, 0, c, 1, 1200);
        v1 = undo_version(u);
        CHECK(v1 != v0 && undo_can_undo(u));
        CHECK(undo_undo(u, &st) && st.pos == 5 && st.ninserted == 3 && st.nremoved == 0);
        CHECK(st.inserted[0] == 'a' && st.inserted[2] == 'c');
        CHECK(undo_version(u) == v0 && undo_can_redo(u) && !undo_can_undo(u));
        CHECK(undo_redo(u, &st) && st.pos == 5 && st.ninserted == 3 && undo_version(u) == v1);
        /* typing somewhere else starts a new step; a long pause does too */
        undo_record(u, 20, NULL, 0, a, 1, 1300);
        undo_record(u, 21, NULL, 0, b, 1, 9000);
        CHECK(undo_undo(u, &st) && st.pos == 21 && st.ninserted == 1);
        CHECK(undo_undo(u, &st) && st.pos == 20 && st.ninserted == 1);
        CHECK(undo_undo(u, &st) && st.pos == 5 && st.ninserted == 3);
        CHECK(!undo_undo(u, &st));
        /* a new edit after an undo throws the redo history away, and gets a version of its own */
        CHECK(undo_can_redo(u));
        undo_record(u, 0, NULL, 0, xy, 2, 20000);
        v2 = undo_version(u);
        CHECK(!undo_can_redo(u) && v2 != v1 && v2 != v0);
        /* backspace merges: deleting 'b' at 6 then 'a' at 5 */
        undo_clear(u);
        undo_record(u, 6, b, 1, NULL, 0, 100);
        undo_record(u, 5, a, 1, NULL, 0, 150);
        CHECK(undo_undo(u, &st) && st.pos == 5 && st.nremoved == 2 && st.removed[0] == 'a' && st.removed[1] == 'b');
        CHECK(!undo_can_undo(u));
        /* forward delete merges the other way */
        undo_clear(u);
        undo_record(u, 5, a, 1, NULL, 0, 100);
        undo_record(u, 5, b, 1, NULL, 0, 120);
        CHECK(undo_undo(u, &st) && st.pos == 5 && st.nremoved == 2 && st.removed[0] == 'a' && st.removed[1] == 'b');
        /* a replacement is a step of its own and breaks merging */
        undo_clear(u);
        undo_record(u, 3, a, 1, b, 1, 100);
        undo_record(u, 4, NULL, 0, c, 1, 110);
        CHECK(undo_undo(u, &st) && st.ninserted == 1 && st.inserted[0] == 'c');
        CHECK(undo_undo(u, &st) && st.nremoved == 1 && st.removed[0] == 'a' && st.ninserted == 1);
        /* undo_break ends a step */
        undo_clear(u);
        undo_record(u, 0, NULL, 0, a, 1, 100);
        undo_break(u);
        undo_record(u, 1, NULL, 0, b, 1, 110);
        CHECK(undo_undo(u, &st) && st.pos == 1);
        CHECK(undo_undo(u, &st) && st.pos == 0);
        undo_free(u);
        /* limits: the oldest steps go first */
        u = undo_new(3, 0);
        {
            int i, n = 0;
            for (i = 0; i < 6; i++) { undo_record(u, (unsigned)(i * 100), NULL, 0, a, 1, 100000UL * (unsigned long)i); }
            while (undo_undo(u, &st)) n++;
            CHECK(n == 3);
        }
        undo_free(u);
        u = undo_new(100, 10);
        {
            u16 big[6] = { 1, 2, 3, 4, 5, 6 };
            int n = 0;
            undo_record(u, 0, NULL, 0, big, 6, 0);
            undo_record(u, 50, NULL, 0, big, 6, 100000);
            while (undo_undo(u, &st)) n++;
            CHECK(n == 1);                                    /* 12 units > 10: the first went */
        }
        undo_free(u);
    }
    TEST_DONE("core");
}
