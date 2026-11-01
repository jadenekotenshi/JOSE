#include <stdio.h>
#include <string.h>
#include "test.h"
#include "../core/wide.h"
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
    CHECK(str_eq(lang_mode_for("a/b.json", NULL), "JSON"));
    CHECK(str_eq(lang_mode_for("app.js", NULL), "JavaScript") && str_eq(lang_mode_for("a.MJS", NULL), "JavaScript"));
    CHECK(str_eq(lang_mode_for("x.rb", NULL), "Ruby") && str_eq(lang_mode_for("/p/Rakefile", NULL), "Ruby") && str_eq(lang_mode_for("Gemfile", NULL), "Ruby"));
    CHECK(str_eq(lang_mode_for("t", "#!/usr/bin/env ruby"), "Ruby") && str_eq(lang_mode_for("t", "#!/usr/bin/env node"), "JavaScript"));
    CHECK(str_eq(lang_mode_for("t.zsh", NULL), "Zsh") && str_eq(lang_mode_for("/home/u/.zshrc", NULL), "Zsh"));
    CHECK(str_eq(lang_mode_for("t", "#!/bin/zsh"), "Zsh") && str_eq(lang_mode_for("t", "#!/bin/sh"), "Shell"));
    CHECK(str_eq(lang_mode_for("notes.md", NULL), "Markdown") && str_eq(lang_mode_for("README.markdown", NULL), "Markdown"));
    CHECK(str_eq(lang_mode_for("Imakefile", NULL), "Imakefile") && str_eq(lang_mode_for("Motif.tmpl", NULL), "Imakefile"));
    CHECK(str_eq(lang_mode_for("BSDmakefile", NULL), "BSDMakefile") && str_eq(lang_mode_for("/usr/share/mk/bsd.prog.mk", NULL), "BSDMakefile"));
    CHECK(str_eq(lang_mode_for("first", "# Pilcrow macro\n"), "PilcrowMacro") && str_eq(lang_mode_for("a.pmacro", NULL), "PilcrowMacro"));
    CHECK(str_eq(lang_mode_for("first", "# JOSE macro\n"), "PilcrowMacro") && str_eq(lang_mode_for("a.jmacro", NULL), "PilcrowMacro"));      /* from before the rename */
    CHECK(str_eq(lang_mode_for("config.mk", NULL), "GNUmakefile") && lang_mode_for("bsd.mk", NULL) != NULL);
    CHECK(str_eq(lang_mode_for("tool", "#!/usr/bin/env python"), "Python"));
    CHECK(str_eq(lang_mode_for("Thing.mm", NULL), "ObjC++"));
    CHECK(str_eq(lang_mode_for("/usr/src/Makefile", NULL), "BSDMakefile") && str_eq(lang_mode_for("makefile", NULL), "BSDMakefile"));   /* OPENSTEP's make is BSD make */
    CHECK(str_eq(lang_mode_for("GNUmakefile", NULL), "GNUmakefile"));
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
    {   /* more modes: INI, HTML, CSS, XML and three assemblers */
        const char *o, *c;
        const char *x86 = "\t.globl _main\n_main:\n\tpushl %ebp\n\tmovl %esp, %ebp\n\tmovl $0, %eax\n\tleave\n\tret\n";
        const char *sparc = "\t.global main\nmain:\n\tsave %sp, -96, %sp\n\tmov 0, %i0\n\tret\n\trestore\n";
        const char *m68k = "_main:\n\tlink a6,#0\n\tmoveq #0,d0\n\tunlk a6\n\trts\n";

        CHECK(str_eq(lang_mode_for("php.ini", NULL), "INI") && str_eq(lang_mode_for("setup.cfg", NULL), "INI") && str_eq(lang_mode_for(".gitconfig", NULL), "INI"));
        CHECK(str_eq(lang_mode_for("index.html", NULL), "HTML") && str_eq(lang_mode_for("a.HTM", NULL), "HTML") && str_eq(lang_mode_for("s.css", NULL), "CSS"));
        CHECK(str_eq(lang_mode_for("a.xml", NULL), "XML") && str_eq(lang_mode_for("logo.svg", NULL), "XML") && str_eq(lang_mode_for("t.xsl", NULL), "XML"));
        CHECK(str_eq(lang_mode_for("noext", "<?xml version=\"1.0\"?>\n"), "XML") && str_eq(lang_mode_for("noext", "<!DOCTYPE html>\n"), "HTML") && str_eq(lang_mode_for("noext", "<HTML>\n"), "HTML"));
        CHECK(str_eq(lang_mode_for("a.s", NULL), "AsmX86") && str_eq(lang_mode_for("a.S", NULL), "AsmX86") && str_eq(lang_mode_for("a.asm", NULL), "AsmX86"));
        CHECK(str_eq(lang_sniff_asm(x86, strlen(x86)), "AsmX86") && str_eq(lang_sniff_asm(sparc, strlen(sparc)), "AsmSparc") && str_eq(lang_sniff_asm(m68k, strlen(m68k)), "AsmM68k"));
        CHECK(lang_sniff_asm(".data\nfoo: .long 1\n", 20) == NULL);
        CHECK(str_eq(lang_refine_mode("AsmX86", sparc, strlen(sparc)), "AsmSparc") && str_eq(lang_refine_mode("AsmX86", m68k, strlen(m68k)), "AsmM68k"));
        CHECK(str_eq(lang_refine_mode("AsmX86", ".data\n", 6), "AsmX86") && str_eq(lang_refine_mode("C", sparc, strlen(sparc)), "C") && lang_refine_mode(NULL, sparc, 4) == NULL);
        CHECK(lang_comment_style("AsmX86", &o, &c) && o[0] == '#' && lang_comment_style("AsmM68k", &o, &c) && o[0] == '|' && lang_comment_style("AsmSparc", &o, &c) && o[0] == '!');
        CHECK(lang_comment_style("HTML", &o, &c) && strcmp(o, "<!--") == 0 && strcmp(c, "-->") == 0 && lang_comment_style("CSS", &o, &c) && strcmp(o, "/*") == 0);
        CHECK(lang_comment_style("INI", &o, &c) && o[0] == ';' && lang_c_like("CSS") && !lang_c_like("HTML") && lang_smart_indent("CSS") == 'b');
    }
    {   /* UTF-16 line endings, and character widths */
        u16 a[8] = { 'a', '\r', '\n', 'b', '\r', 0, 'c', '\n' }, o[16];
        int mixed = 0;
        size_t n;

        CHECK(eol16_detect(a, 8, &mixed) == EOL_LF && mixed == 1);
        n = eol16_normalize(a, 8);
        CHECK(n == 7 && a[1] == '\n' && a[2] == 'b' && a[3] == '\n' && a[4] == ' ' && a[5] == 'c' && a[6] == '\n');
        CHECK(eol16_expanded_size(a, n, EOL_CRLF) == 10 && eol16_expanded_size(a, n, EOL_LF) == 7);
        CHECK(eol16_expand(a, n, EOL_CRLF, o) == 10 && o[1] == '\r' && o[2] == '\n' && o[3] == 'b');
        CHECK(eol16_expand(a, n, EOL_CR, o) == 7 && o[1] == '\r');
        CHECK(wide_cp('a') == 1 && wide_cp(0x3042) == 2 && wide_cp(0x4E2D) == 2 && wide_cp(0xAC00) == 2 && wide_cp(0xFF21) == 2);
        CHECK(wide_cp(0x0301) == 0 && wide_cp(0x200B) == 0 && wide_cp(0xFF71) == 1 && wide_cp(0x20AC) == 1 && wide_cp(0x20000) == 2);
        CHECK(wide_unit(0xD83D) == 2 && wide_unit(0xDE00) == 0 && wide_unit('x') == 1);
    }
    TEST_DONE("core");
}
