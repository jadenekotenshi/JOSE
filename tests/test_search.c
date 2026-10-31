#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "test.h"
#include "search.h"

#define MAXU 4096

static unsigned widen(const char *s, u16 *out)
{
    unsigned n = 0;
    while (s[n]) { out[n] = (unsigned char)s[n]; n++; }
    return n;
}

/* Finds `pat` in `text` from `from`; returns the start of the match or -1, and its length through *len_out. */
static int find(const char *pat, int flags, const char *text, unsigned from, int forward, int wrap, int *len_out)
{
    u16 p[MAXU], t[MAXU];
    unsigned np = widen(pat, p), nt = widen(text, t);
    char err[80];
    Search *s = search_new(p, np, flags, err, sizeof err);
    SearchMatch m;
    int r;

    if (s == NULL) return -2;
    r = search_find(s, t, nt, from, forward, wrap, &m);
    search_free(s);
    if (!r) return -1;
    if (len_out) *len_out = (int)(m.end[0] - m.start[0]);
    return (int)m.start[0];
}

/* Whole-text replace; returns the new text (static buffer) for a text where every match is replaced. */
static const char *replace_all(const char *pat, int flags, const char *text, const char *repl, int literal, unsigned *count)
{
    static char result[MAXU];
    u16 p[MAXU], t[MAXU], r[MAXU], *out;
    unsigned np = widen(pat, p), nt = widen(text, t), nr = widen(repl, r), outlen, first, last, i, n = 0;
    char err[80];
    Search *s = search_new(p, np, flags, err, sizeof err);

    if (s == NULL) return "ERR";
    if (!search_replace_all(s, t, nt, 0, nt, r, nr, literal, &out, &outlen, &first, &last, count)) {
        search_free(s);
        strcpy(result, text);
        return result;
    }
    for (i = 0; i < first; i++) result[n++] = (char)t[i];
    for (i = 0; i < outlen; i++) result[n++] = (char)out[i];
    for (i = last; i < nt; i++) result[n++] = (char)t[i];
    result[n] = '\0';
    free(out);
    search_free(s);
    return result;
}

#define R SEARCH_REGEX
#define I SEARCH_ICASE
#define W SEARCH_WORD

int main(void)
{
    int len = 0;
    unsigned cnt = 0;
    char err[80];
    u16 p[64];

    /* literal */
    CHECK(find("cat", 0, "the cat sat", 0, 1, 0, &len) == 4 && len == 3);
    CHECK(find("cat", 0, "the cat sat", 5, 1, 0, NULL) == -1);
    CHECK(find("cat", 0, "the cat sat", 5, 1, 1, NULL) == 4);                 /* wraps */
    CHECK(find("CAT", 0, "the cat sat", 0, 1, 0, NULL) == -1);
    CHECK(find("CAT", I, "the cat sat", 0, 1, 0, NULL) == 4);
    CHECK(find("a.c", 0, "abc a.c", 0, 1, 0, NULL) == 4);                     /* a dot is a dot */
    CHECK(find("at", 0, "cat at hat", 9, 0, 0, NULL) == 8);                   /* backwards: last start before 9 */
    CHECK(find("at", 0, "cat at hat", 5, 0, 0, NULL) == 4);
    CHECK(find("at", 0, "cat at hat", 1, 0, 0, NULL) == -1);
    CHECK(find("at", 0, "cat at hat", 1, 0, 1, NULL) == 8);                   /* backwards, wrapped */
    CHECK(find("cat", W, "concat cat", 0, 1, 0, NULL) == 7);                  /* whole word */
    CHECK(find("->", W, "a->b", 0, 1, 0, NULL) == 1);
    CHECK(find("", 0, "abc", 0, 1, 0, NULL) == -2);                           /* empty pattern */

    /* regex basics */
    CHECK(find("c.t", R, "cart cat", 0, 1, 0, NULL) == 5);
    CHECK(find("ab*c", R, "xacx abbbc", 0, 1, 0, &len) == 1 && len == 2);
    CHECK(find("ab+c", R, "xacx abbbc", 0, 1, 0, &len) == 5 && len == 5);
    CHECK(find("colou?r", R, "color colour", 0, 1, 0, &len) == 0 && len == 5);
    CHECK(find("^foo", R, "a\nfoo\nfoo", 0, 1, 0, NULL) == 2);
    CHECK(find("foo$", R, "foo bar\nfoo", 0, 1, 0, NULL) == 8);
    CHECK(find("a|b|cd", R, "xxcd", 0, 1, 0, &len) == 2 && len == 2);
    CHECK(find("(ab)+", R, "xababab", 0, 1, 0, &len) == 1 && len == 6);
    CHECK(find("[a-c]+", R, "xxbcaxx", 0, 1, 0, &len) == 2 && len == 3);
    CHECK(find("[^a-c ]+", R, "ab xyz c", 0, 1, 0, &len) == 3 && len == 3);
    CHECK(find("[]x]+", R, "a]x]b", 0, 1, 0, &len) == 1 && len == 3);
    CHECK(find("\\d+", R, "abc 1234 x", 0, 1, 0, &len) == 4 && len == 4);
    CHECK(find("\\w+", R, "  hello_1 ", 0, 1, 0, &len) == 2 && len == 7);
    CHECK(find("\\s+", R, "ab \t cd", 0, 1, 0, &len) == 2 && len == 3);
    CHECK(find("\\<cat\\>", R, "concat cat", 0, 1, 0, NULL) == 7);
    CHECK(find("\\bcat", R, "concat cat", 0, 1, 0, NULL) == 7);
    CHECK(find("a\\.b", R, "axb a.b", 0, 1, 0, NULL) == 4);
    CHECK(find("a{2}", R, "a aa aaa", 0, 1, 0, &len) == 2 && len == 2);
    CHECK(find("a{2,}", R, "a aa aaa", 5, 1, 0, &len) == 5 && len == 3);
    CHECK(find("a{1,2}", R, "aaaa", 0, 1, 0, &len) == 0 && len == 2);
    CHECK(find("x{", R, "ax{b", 0, 1, 0, &len) == 1 && len == 2);             /* a brace that is not a repeat */
    CHECK(find("{", R, "int f() { }", 0, 1, 0, NULL) == 8);
    CHECK(find("a.*b", R, "a1b2b3", 0, 1, 0, &len) == 0 && len == 5);          /* greedy */
    CHECK(find("a.*?b", R, "a1b2b3", 0, 1, 0, &len) == 0 && len == 3);         /* lazy */
    CHECK(find("a.c", R, "a\nc", 0, 1, 0, NULL) == -1);                       /* dot stops at a newline */
    CHECK(find("a[^x]c", R, "a\nc", 0, 1, 0, NULL) == 0);
    CHECK(find("a\\nb", R, "xa\nb", 0, 1, 0, NULL) == 1);
    CHECK(find("HELLO", R | I, "say hello", 0, 1, 0, NULL) == 4);
    CHECK(find("[a-c]+", R | I, "xxBCAxx", 0, 1, 0, &len) == 2 && len == 3);
    CHECK(find("cat", R | W, "concat cat", 0, 1, 0, NULL) == 7);
    CHECK(find("(a*)*b", R, "aaab", 0, 1, 0, &len) == 0 && len == 4);          /* empty loop bodies terminate */
    CHECK(find("(a|)+b", R, "aab", 0, 1, 0, NULL) == 0);
    CHECK(find("(a+)+$", R, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!", 0, 1, 0, NULL) == -1);   /* does not hang */
    CHECK(find("(\\w+) \\1", R, "say the the cat", 0, 1, 0, &len) == 4 && len == 7);     /* back-reference */
    CHECK(find("(?:ab)+c", R, "ababc", 0, 1, 0, &len) == 0 && len == 5);

    /* errors */
    CHECK(search_new(p, widen("(ab", p), R, err, sizeof err) == NULL && strlen(err) > 0);
    CHECK(search_new(p, widen("ab)", p), R, err, sizeof err) == NULL);
    CHECK(search_new(p, widen("[ab", p), R, err, sizeof err) == NULL);
    CHECK(search_new(p, widen("*a", p), R, err, sizeof err) == NULL);
    CHECK(search_new(p, widen("a\\", p), R, err, sizeof err) == NULL);
    CHECK(search_new(p, widen("[z-a]", p), R, err, sizeof err) == NULL);

    /* replace */
    CHECK(strcmp(replace_all("cat", 0, "cat concat cat", "dog", 1, &cnt), "dog condog dog") == 0 && cnt == 3);
    CHECK(strcmp(replace_all("cat", W, "cat concat cat", "dog", 1, &cnt), "dog concat dog") == 0 && cnt == 2);
    CHECK(strcmp(replace_all("(\\w+)@(\\w+)", R, "me@host you@box", "\\2:\\1", 0, &cnt), "host:me box:you") == 0 && cnt == 2);
    CHECK(strcmp(replace_all("a", R, "banana", "\\\\", 0, &cnt), "b\\n\\n\\") == 0);                 /* \\ is a backslash */
    CHECK(strcmp(replace_all("a", R, "banana", "[\\0]", 0, &cnt), "b[a]n[a]n[a]") == 0);
    CHECK(strcmp(replace_all(",", R, "a,b", "\\n", 0, &cnt), "a\nb") == 0);                          /* \n is a newline */
    CHECK(strcmp(replace_all(",", 0, "a,b", "\\n", 1, &cnt), "a\\nb") == 0);                         /* literal mode */
    CHECK(strcmp(replace_all("x*", R, "abc", "-", 0, &cnt), "-a-b-c-") == 0 && cnt == 4);            /* empty matches */
    CHECK(strcmp(replace_all("zzz", R, "abc", "-", 0, &cnt), "abc") == 0 && cnt == 0);
    CHECK(strcmp(replace_all("^", R, "a\nb\nc", "> ", 0, &cnt), "> a\n> b\n> c") == 0 && cnt == 3);  /* quote lines */
    CHECK(strcmp(replace_all("[ \\t]+$", R, "a  \nb \n", "", 0, &cnt), "a\nb\n") == 0 && cnt == 2);     /* trailing blanks */

    /* a long haystack: the explicit stack copes with a long run */
    {
        static u16 big[200000];
        unsigned i;
        SearchMatch m;
        Search *s;
        for (i = 0; i < 200000; i++) big[i] = 'a';
        big[199999] = 'b';
        s = search_new(p, widen("a*b", p), R, err, sizeof err);
        CHECK(s != NULL && search_find(s, big, 200000, 0, 1, 0, &m) && m.start[0] == 0 && m.end[0] == 200000);
        search_free(s);
    }
    TEST_DONE("search");
}
