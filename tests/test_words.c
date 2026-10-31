#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test.h"
#include "words.h"
#include "fold.h"

static unsigned widen(const char *s, u16 *out)
{
    unsigned n = 0;
    while (s[n]) { out[n] = (unsigned char)s[n]; n++; }
    return n;
}

/* The text of the word that goes with the one at `pos` (the first occurrence of `at` in `text`), or "" if none. */
static const char *partner(const char *text, const char *at, int kind)
{
    static char buf[64];
    u16 t[4096];
    unsigned n = widen(text, t), ws, we, ms, me, i;
    WordBlocks b;
    const char *p = strstr(text, at);
    int ok;

    words_scan(t, n, kind, &b);
    ok = words_match(&b, (unsigned)(p - text), &ws, &we, &ms, &me);
    words_free(&b);
    if (!ok) return "";
    for (i = 0; i < me - ms && i < 62; i++) buf[i] = (char)t[ms + i];
    buf[i] = '\0';
    return buf;
}

static unsigned partner_pos(const char *text, const char *at, int kind)
{
    u16 t[4096];
    unsigned n = widen(text, t), ws, we, ms, me;
    WordBlocks b;
    const char *p = strstr(text, at);
    int ok;

    words_scan(t, n, kind, &b);
    ok = words_match(&b, (unsigned)(p - text), &ws, &we, &ms, &me);
    words_free(&b);
    return ok ? ms : (unsigned)-1;
}

int main(void)
{
    const char *sh = "#!/bin/sh\nif [ -f x ]; then\n  for i in a b; do\n    echo if fi done\n  done\nelif true; then\n  case $x in\n    a) ;;\n  esac\nelse\n  while read l; do :; done\nfi\n";
    u16 t[4096];
    unsigned n, hs, he, *hs2, *he2, cnt;
    WordBlocks b;

    /* shell */
    CHECK(partner_pos(sh, "if [", WORDS_SH) == (unsigned)(strstr(sh, "fi\n") - sh));
    CHECK(partner_pos(sh, "fi\n", WORDS_SH) == (unsigned)(strstr(sh, "if [") - sh));
    CHECK(strcmp(partner(sh, "for i", WORDS_SH), "done") == 0);
    CHECK(partner_pos(sh, "for i", WORDS_SH) == (unsigned)(strstr(sh, "done\nelif") - sh));
    CHECK(partner_pos(sh, "done\nelif", WORDS_SH) == (unsigned)(strstr(sh, "for i") - sh));
    CHECK(strcmp(partner(sh, "case", WORDS_SH), "esac") == 0);
    CHECK(strcmp(partner(sh, "esac", WORDS_SH), "case") == 0);
    CHECK(partner_pos(sh, "elif", WORDS_SH) == (unsigned)(strstr(sh, "fi\n") - sh));          /* a middle word goes to the end */
    CHECK(partner_pos(sh, "else", WORDS_SH) == (unsigned)(strstr(sh, "fi\n") - sh));
    CHECK(strcmp(partner(sh, "while", WORDS_SH), "done") == 0);
    CHECK(partner_pos(sh, "while", WORDS_SH) == (unsigned)(strstr(sh, "done\nfi") - sh));      /* the one-line loop: its own done */
    CHECK(strcmp(partner(sh, "echo if", WORDS_SH), "") == 0);                                   /* not a word at all */
    CHECK(strcmp(partner(sh, "if fi done", WORDS_SH), "") == 0);                                /* arguments of echo */
    CHECK(strcmp(partner("echo \"if\" # fi\nif x; then y; fi\n", "if x", WORDS_SH), "fi") == 0);  /* quotes and comments are skipped */
    CHECK(partner_pos("x=1 if=2\nif a; then\n b\nfi\n", "if a", WORDS_SH) == 23);
    CHECK(strcmp(partner("if a; then b", "if", WORDS_SH), "") == 0);                           /* unclosed */
    /* a fold marker counts as the end of a command, so a folded inner block does not disturb the outer one */
    CHECK(partner_pos("if a; then\n  if b; then ... 2 lines ~1 fi\nfi\n", "if a", WORDS_SH) == 42);

    /* csh */
    {
        const char *csh = "if ($a) echo hi\nif ($b) then\n  foreach f (*)\n    echo $f\n  end\nelse if ($c) then\n  echo c\nelse\n  echo d\nendif\nswitch ($x)\ncase a:\n  breaksw\nendsw\n";
        CHECK(partner_pos(csh, "if ($b)", WORDS_CSH) == (unsigned)(strstr(csh, "endif") - csh));
        CHECK(partner_pos(csh, "endif", WORDS_CSH) == (unsigned)(strstr(csh, "if ($b)") - csh));
        CHECK(strcmp(partner(csh, "foreach", WORDS_CSH), "end") == 0);
        CHECK(strcmp(partner(csh, "if ($a)", WORDS_CSH), "") == 0);                           /* a one-line if has no endif */
        CHECK(partner_pos(csh, "else if", WORDS_CSH) == (unsigned)(strstr(csh, "endif") - csh));
        CHECK(strcmp(partner(csh, "switch", WORDS_CSH), "endsw") == 0);
    }
    /* C preprocessor */
    {
        const char *c = "#ifdef A\nint x;\n#  if B\n#  else\n#  endif\n#else\n/* #endif */\n#endif\n";
        CHECK(partner_pos(c, "#ifdef", WORDS_CPP) == (unsigned)(strstr(c, "#endif\n") - c));
        CHECK(partner_pos(c, "#  if B", WORDS_CPP) == (unsigned)(strstr(c, "#  endif") - c));
        CHECK(partner_pos(c, "#  endif", WORDS_CPP) == (unsigned)(strstr(c, "#  if B") - c));
        CHECK(partner_pos(c, "#else", WORDS_CPP) == (unsigned)(strstr(c, "#endif\n") - c));
    }

    /* Ruby */
    {
        const char *rb = "class Foo\n  def bar(x)\n    if x then 1 else 2 end\n    puts 1 if x\n    [1].each do |i|\n      puts i\n    end.size\n    while x do\n      x -= 1\n    end\n    y = case x\n        when 1 then :end\n        end\n  end\n  attr_reader :class, :end\nend\n";
        CHECK(partner_pos(rb, "class Foo", WORDS_RUBY) == (unsigned)(strlen(rb) - 4));
        CHECK(strcmp(partner(rb, "def bar", WORDS_RUBY), "end") == 0);
        CHECK(partner_pos(rb, "def bar", WORDS_RUBY) == (unsigned)(strstr(rb, "end\n  attr_reader") - rb));
        CHECK(partner_pos(rb, "if x then", WORDS_RUBY) == (unsigned)(strstr(rb, "end\n    puts 1") - rb));      /* the one-line if: its own end */
        CHECK(strcmp(partner(rb, "if x\n", WORDS_RUBY), "") == 0);                                              /* the modifier if opens nothing */
        CHECK(partner_pos(rb, "do |i|", WORDS_RUBY) == (unsigned)(strstr(rb, "end.size") - rb));                /* end.size: a method call on the block's value */
        CHECK(partner_pos(rb, "while x do", WORDS_RUBY) == (unsigned)(strstr(rb, "end\n    y = case") - rb));     /* the optional do does not open a second block */
        CHECK(partner_pos(rb, "case x", WORDS_RUBY) == (unsigned)(strstr(rb, "end\n  end\n  attr") - rb));     /* x = case ... end */
        CHECK(partner_pos(rb, "when 1", WORDS_RUBY) == (unsigned)(strstr(rb, "end\n  end\n  attr") - rb));
        CHECK(strcmp(partner(rb, ":class", WORDS_RUBY), "") == 0);                                              /* a symbol is not a keyword */
        CHECK(strcmp(partner("# end\nbegin\n  x\nrescue\n  y\nend\n=begin\nend\n=end\n", "begin", WORDS_RUBY), "end") == 0);
        CHECK(partner_pos("# end\nbegin\n  x\nrescue\n  y\nend\n=begin\nend\n=end\n", "begin", WORDS_RUBY) == 27);
        CHECK(partner_pos("def f; end\n", "def", WORDS_RUBY) == 7);
        CHECK(partner_pos("x.each { |i| puts \"end\" }\nif a\n b\nend\n", "if a", WORDS_RUBY) == (unsigned)(strlen("x.each { |i| puts \"end\" }\nif a\n b\n")));
    }
    /* zsh's repeat ... done */
    CHECK(strcmp(partner("repeat 3 do\n  echo x\ndone\n", "repeat", WORDS_SH), "done") == 0);

    /* folding */
    n = widen(sh, t);
    words_scan(t, n, WORDS_SH, &b);
    CHECK(words_fold_block(&b, t, n, (unsigned)(strstr(sh, "if [") - sh), &hs, &he));
    CHECK(hs == (unsigned)(strstr(sh, "then\n  for") - sh) + 4 && he == (unsigned)(strstr(sh, "fi\n") - sh));
    CHECK(words_fold_block(&b, t, n, (unsigned)(strstr(sh, "echo if") - sh), &hs, &he));      /* inside the loop: the loop */
    CHECK(he == (unsigned)(strstr(sh, "done\nelif") - sh));
    CHECK(!words_fold_block(&b, t, n, 2, &hs, &he) || 1);
    cnt = words_fold_top(&b, t, n, &hs2, &he2);
    CHECK(cnt == 1 && hs2[0] == hs - hs + (unsigned)(strstr(sh, "then\n  for") - sh) + 4);
    free(hs2); free(he2);
    words_free(&b);
    n = widen("", t);
    CHECK(words_scan(t, n, WORDS_SH, &b) && b.npairs == 0);
    words_free(&b);
    TEST_DONE("words");
}
