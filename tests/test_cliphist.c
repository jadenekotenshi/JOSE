#include "test.h"
#include "../core/cliphist.h"
#include <stdio.h>
#include <stdlib.h>

static int add(ClipRing *r, const char *s, int rect) { return clip_add(r, s, (unsigned)strlen(s), rect); }

int main(void)
{
    ClipRing r;
    char buf[200];
    int i;

    clip_init(&r);
    CHECK(add(&r, "one", 0) && add(&r, "two", 1) && add(&r, "three", 0));
    CHECK(r.n == 3 && strcmp(r.item[0].text, "three") == 0 && strcmp(r.item[2].text, "one") == 0 && r.item[1].rect == 1);
    CHECK(add(&r, "one", 1));                                    /* again: to the front, not twice */
    CHECK(r.n == 3 && strcmp(r.item[0].text, "one") == 0 && r.item[0].rect == 1 && strcmp(r.item[1].text, "three") == 0 && strcmp(r.item[2].text, "two") == 0);
    CHECK(!clip_add(&r, "", 0, 0));
    CHECK(!clip_add(&r, "x", (unsigned)(CLIP_MAX_BYTES + 1), 0));    /* too big (never read) */
    CHECK(r.n == 3);
    clip_remove(&r, 1);
    CHECK(r.n == 2 && strcmp(r.item[0].text, "one") == 0 && strcmp(r.item[1].text, "two") == 0);
    clip_remove(&r, 5);
    clip_remove(&r, -1);
    CHECK(r.n == 2);
    clip_free(&r);
    CHECK(r.n == 0);

    for (i = 0; i < CLIP_MAX + 5; i++) { sprintf(buf, "item %d", i); add(&r, buf, 0); }
    CHECK(r.n == CLIP_MAX && strcmp(r.item[0].text, "item 34") == 0 && strcmp(r.item[CLIP_MAX - 1].text, "item 5") == 0);   /* the oldest went */

    clip_free(&r);
    add(&r, "  \n\tint   main(void)\n{\n    return 0;\n}\n", 0);
    clip_preview(&r, 0, buf, sizeof buf, 40);
    CHECK(strcmp(buf, "int main(void) { return 0; }  (5 lines)") == 0);
    clip_free(&r);
    add(&r, "short", 0);
    clip_preview(&r, 0, buf, sizeof buf, 40);
    CHECK(strcmp(buf, "short") == 0);
    clip_free(&r);
    add(&r, "abcdefghijklmnopqrstuvwxyz", 0);
    clip_preview(&r, 0, buf, sizeof buf, 10);
    CHECK(strcmp(buf, "abcdefghij...") == 0);
    clip_free(&r);
    add(&r, "caf\xC3\xA9 \xE2\x82\xAC\xE2\x82\xAC\xE2\x82\xAC", 0);            /* é and three euro signs */
    clip_preview(&r, 0, buf, sizeof buf, 7);
    CHECK(strcmp(buf, "caf\xC3\xA9 \xE2\x82\xAC\xE2\x82\xAC...") == 0);         /* cut between characters, not inside one */
    clip_free(&r);
    add(&r, "x\n", 0);
    clip_preview(&r, 0, buf, sizeof buf, 10);
    CHECK(strcmp(buf, "x") == 0);                                              /* one line with its newline */
    clip_preview(&r, 3, buf, sizeof buf, 10);
    CHECK(buf[0] == '\0');
    clip_preview(&r, 0, buf, 6, 40);
    CHECK(strlen(buf) < 6);
    clip_free(&r);
    TEST_DONE("test_cliphist");
}
