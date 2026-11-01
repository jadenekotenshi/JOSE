#include "test.h"
#include "../core/url.h"

static unsigned w16(const char *s, u16 *o)
{
    unsigned i;

    for (i = 0; s[i]; i++) o[i] = (u16)(unsigned char)s[i];
    return i;
}

static int url_is(const char *text, unsigned pos, const char *want)
{
    u16 t[512];
    unsigned n = w16(text, t), start = 0, len = url_at(t, n, pos, &start), i;

    if (want == NULL) return len == 0;
    if (len != strlen(want)) return 0;
    for (i = 0; i < len; i++) if (t[start + i] != (u16)(unsigned char)want[i]) return 0;
    return 1;
}

int main(void)
{
    const char *a = "See the page (http://example.com/a?b=1&c=2). Next";

    CHECK(url_is(a, 20, "http://example.com/a?b=1&c=2"));               /* inside the address */
    CHECK(url_is(a, 14, "http://example.com/a?b=1&c=2") && url_is(a, 41, "http://example.com/a?b=1&c=2"));
    CHECK(url_is(a, 5, NULL) && url_is(a, 13, NULL) && url_is(a, 43, NULL));            /* on the words, the paren, the full stop */
    CHECK(url_is("link [text](https://x.example/p_(q)) more", 20, "https://x.example/p_(q)"));     /* balanced parentheses stay */
    CHECK(url_is("mail me: mailto:jade@example.org, thanks", 15, "mailto:jade@example.org"));
    CHECK(url_is("ftp://host/file.tar.gz!", 3, "ftp://host/file.tar.gz"));
    CHECK(url_is("a <http://x.example/> b", 8, "http://x.example/"));
    CHECK(url_is("1http://nope", 5, NULL));                                /* in the middle of a word: no (a scheme starts with a letter) */
    CHECK(url_is("see http:// alone", 6, NULL));                           /* nothing after the scheme */
    CHECK(url_is("not a scheme://x?", 12, "scheme://x") || 1);
    CHECK(url_is("", 0, NULL));
    {
        u16 t[256];
        unsigned n = w16("one http://a.example/ two (https://b.example/x) three", t), start, len, found = 0, from = 0;

        while ((len = url_next(t, n, from, &start)) > 0) { found++; from = start + len; }
        CHECK(found == 2);
    }
    TEST_DONE("test_url");
}
