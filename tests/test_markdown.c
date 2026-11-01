#include "test.h"
#include "../core/md.h"
#include <stdlib.h>

static char *rtf_of(const char *md, int charset)
{
    MdDoc *d = md_parse(md, strlen(md));
    MdRtfOptions o;
    char *r;

    md_rtf_defaults(&o);
    o.charset = charset;
    r = md_to_rtf(d, &o, NULL);
    md_free(d);
    return r;
}

int main(void)
{
    char *r = rtf_of("# Title\n\nSome *emphasis*, **bold** and `code`.\n\n- one\n- two\n\n```\nint x;\n```\n", MD_CHARSET_CP1252);

    CHECK(r != NULL && strncmp(r, "{\\rtf1", 6) == 0);
    CHECK(strstr(r, "Title") != NULL && strstr(r, "emphasis") != NULL && strstr(r, "int x;") != NULL);
    CHECK(strstr(r, "\\b ") != NULL || strstr(r, "\\b\\") != NULL || strstr(r, "\\b0") != NULL);        /* bold is switched on and off somewhere */
    CHECK(strstr(r, "one") != NULL && strstr(r, "two") != NULL);
    free(r);

    r = rtf_of("caf\xC3\xA9 \xE2\x82\xAC", MD_CHARSET_CP1252);
    CHECK(strstr(r, "\\'e9") != NULL);                                   /* Windows-1252 e-acute */
    free(r);
    r = rtf_of("caf\xC3\xA9", MD_CHARSET_NEXTSTEP);
    CHECK(strstr(r, "\\'e9") == NULL && strstr(r, "\\'") != NULL);       /* NeXTSTEP puts it elsewhere */
    free(r);
    r = rtf_of("caf\xC3\xA9", MD_CHARSET_ASCII);
    CHECK(strstr(r, "\\u233") != NULL);
    free(r);

    r = rtf_of("", MD_CHARSET_CP1252);
    CHECK(r != NULL && strncmp(r, "{\\rtf1", 6) == 0);
    free(r);
    r = rtf_of("[a link](http://x.example/)\n", MD_CHARSET_CP1252);
    CHECK(strstr(r, "a link") != NULL && strstr(r, "http://x.example/") != NULL);       /* shown as: a link (http://x.example/) */
    free(r);
    TEST_DONE("test_markdown");
}
