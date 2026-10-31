#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test.h"
#include "tags.h"

int main(void)
{
    const char *path = "build/test.tags";
    FILE *fp;
    Tags *t;
    unsigned first, n;
    const Tag *tag;
    char tip[128];

    fp = fopen(path, "w");
    fputs("!_TAG_FILE_FORMAT\t2\t/extended format/\n"
          "zeta\tz.c\t/^void zeta(void)$/;\"\tf\tsignature:(void)\n"
          "alpha\ta.c\t/^int alpha(int a, char *b)$/\n"
          "alpha\tb.c\t42\n"
          "beta\tsub/b.h\t/^#define beta(x)\t((x) + 1)$/;\"\td\n"
          "gamma\tg.c\t?^static long gamma(long g)$?\n"
          "slash\ts.c\t/^char *a\\/b(void)$/\n"
          "delta\td.c\t7;\"\tkind:function\tsignature:(int d)\n"
          "not a tag line\n"
          "broken\tb.c\t/^no end\n", fp);
    fclose(fp);

    CHECK(tags_load("build/nonexistent.tags") == NULL);
    t = tags_load(path);
    CHECK(t != NULL);
    CHECK(tags_count(t) == 7);
    n = tags_find(t, "alpha", &first);
    CHECK(n == 2);
    tag = tags_at(t, first);
    CHECK(strcmp(tag->file, "a.c") == 0 && tag->pattern != NULL && strcmp(tag->pattern, "int alpha(int a, char *b)") == 0 && tag->line == 0);   /* file order kept */
    CHECK(strcmp(tags_at(t, first + 1)->file, "b.c") == 0 && tags_at(t, first + 1)->line == 42 && tags_at(t, first + 1)->pattern == NULL);
    CHECK(tags_tip(tag, tip, sizeof tip) > 0 && strcmp(tip, "int alpha(int a, char *b)") == 0);
    n = tags_find(t, "beta", &first);
    CHECK(n == 1 && strcmp(tags_at(t, first)->file, "sub/b.h") == 0 && strcmp(tags_at(t, first)->pattern, "#define beta(x)\t((x) + 1)") == 0);
    CHECK(tags_at(t, first)->kind != NULL && strcmp(tags_at(t, first)->kind, "d") == 0);
    tags_tip(tags_at(t, first), tip, sizeof tip);
    CHECK(strcmp(tip, "#define beta(x) ((x) + 1)") == 0);                    /* tabs shown as spaces */
    n = tags_find(t, "gamma", &first);
    CHECK(n == 1 && strcmp(tags_at(t, first)->pattern, "static long gamma(long g)") == 0);
    n = tags_find(t, "slash", &first);
    CHECK(n == 1 && strcmp(tags_at(t, first)->pattern, "char *a/b(void)") == 0);
    n = tags_find(t, "zeta", &first);
    CHECK(n == 1 && tags_at(t, first)->signature != NULL && strcmp(tags_at(t, first)->signature, "(void)") == 0);
    n = tags_find(t, "delta", &first);
    CHECK(n == 1 && tags_at(t, first)->line == 7 && strcmp(tags_at(t, first)->kind, "function") == 0);
    tags_tip(tags_at(t, first), tip, sizeof tip);
    CHECK(strcmp(tip, "delta(int d)") == 0);                                  /* no pattern: name and signature */
    CHECK(tags_find(t, "nothing", &first) == 0);
    CHECK(tags_find(t, "", &first) == 0);
    CHECK(tags_tip(tags_at(t, 0), tip, 5) == 4);                              /* cut to fit */
    tags_free(t);
    remove(path);
    TEST_DONE("tags");
}
