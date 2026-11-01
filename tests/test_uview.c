#include "test.h"
#include "../core/uview.h"
#include <stdio.h>
#include <stdlib.h>

/* A font with Latin and CJK glyphs: $PILCROW_TEST_FONT, else the first of a few common places. */
static const char *find_font(void)
{
    static const char *const cands[] = {
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        NULL
    };
    const char *env = getenv("PILCROW_TEST_FONT");
    int i;

    if (env != NULL && env[0] != 0) return env;
    for (i = 0; cands[i] != NULL; i++) {
        FILE *f = fopen(cands[i], "rb");

        if (f != NULL) {
            fclose(f);
            return cands[i];
        }
    }
    return NULL;
}

static int dark_pixels(const FBuf *f, int x0, int y0, int x1, int y1)
{
    int x, y, n = 0;

    for (y = y0; y < y1 && y < f->h; y++)
        for (x = x0; x < x1 && x < f->w; x++)
            if (f->px[((size_t)y * (size_t)f->w + (size_t)x) * 4] < 128) n++;
    return n;
}

static size_t to16(const char *ascii, u16 *out)
{
    size_t n = 0;

    while (*ascii) out[n++] = (u16)(unsigned char)*ascii++;
    return n;
}

int main(void)
{
    const char *path = find_font();
    UGlyphs *g;
    ULayout l;
    u16 t[64];
    size_t n, a, b;
    int cw, ch, asc;
    FBuf *fb;

    if (path == NULL) {
        printf("test_uview: no font found (set PILCROW_TEST_FONT); skipped\n");
        return 0;
    }
    g = uglyphs_new(16);
    CHECK(g != NULL);
    CHECK(uglyphs_add_face(g, path, 0));
    CHECK(!uglyphs_add_face(g, "/nonexistent/font.ttf", 0));
    CHECK(uglyphs_count(g) == 1);
    uglyphs_cell(g, &cw, &ch, &asc);
    CHECK(cw > 3 && ch >= 16 && asc > 0 && asc <= ch);

    /* lines: LF, CRLF, CR, and a last line without an ending; CJK takes two cells */
    n = to16("ab\ncd", t);
    t[n++] = 0x65E5; t[n++] = 0x672C;               /* nihon */
    t[n++] = '\r'; t[n++] = '\n';
    n += to16("x\ry", t + n);
    CHECK(ulayout_build(&l, t, n, g, 8));
    CHECK(l.nlines == 4);
    ulayout_line(&l, 1, &a, &b);
    CHECK(a == 3 && b == 7);
    ulayout_line(&l, 3, &a, &b);
    CHECK(b - a == 1 && t[a] == 'y');
    CHECK(l.max_cols == 6);
    CHECK(ulayout_line_at_y(&l, 0) == 0 && ulayout_line_at_y(&l, ch) == 1 && ulayout_line_at_y(&l, 100000) == 3);
    ulayout_free(&l);

    /* tabs go to the next multiple of the tab width */
    n = to16("a\tb", t);
    CHECK(ulayout_build(&l, t, n, g, 4));
    CHECK(l.max_cols == 5);
    ulayout_free(&l);

    /* drawing: text makes dark pixels where it is and none where it is not */
    n = to16("HHHH", t);
    t[n++] = '\n';
    t[n++] = 0x65E5; t[n++] = 0x672C; t[n++] = 0x8A9E;
    CHECK(ulayout_build(&l, t, n, g, 8));
    fb = fbuf_new(cw * 8, ch * 2);
    CHECK(fb != NULL);
    ulayout_draw(&l, g, fb, 0, 0, fb->w, fb->h, 0x000000, 0xFFFFFF);
    CHECK(dark_pixels(fb, 0, 0, cw * 4, ch) > 20);                 /* the Latin line */
    CHECK(dark_pixels(fb, cw * 4, 0, fb->w, ch) == 0);              /* nothing right of it */
    if (uglyphs_get(g, 0x65E5)->found) {
        CHECK(dark_pixels(fb, 0, ch, cw * 6, ch * 2) > 20);        /* the CJK line, in the six cells it takes */
        CHECK(dark_pixels(fb, cw * 6, ch, fb->w, ch * 2) == 0);
    } else {
        printf("  (the font has no CJK glyphs; CJK drawing not checked)\n");
    }
    /* scrolled right by one cell: the same text, one cell to the left */
    {
        FBuf *fb2 = fbuf_new(cw * 8, ch * 2);

        ulayout_draw(&l, g, fb2, cw, 0, fb2->w, fb2->h, 0x000000, 0xFFFFFF);
        CHECK(dark_pixels(fb2, cw * 3, 0, cw * 4, ch) == 0);       /* the fourth H is gone from cell 3 (it is now cell 2 at most) */
        CHECK(dark_pixels(fb2, 0, 0, cw * 3, ch) > 20);
        fbuf_free(fb2);
    }
    /* a window below the text is only background */
    ulayout_draw(&l, g, fb, 0, ch * 5, fb->w, fb->h, 0x000000, 0xFFFFFF);
    CHECK(dark_pixels(fb, 0, 0, fb->w, fb->h) == 0);
    fbuf_free(fb);
    ulayout_free(&l);

    /* a lone surrogate and a surrogate pair do not crash and take a cell each way */
    t[0] = 0xD800; t[1] = 'a'; t[2] = 0xD83D; t[3] = 0xDE00; t[4] = 0xDC00;
    CHECK(ulayout_build(&l, t, 5, g, 8));
    CHECK(l.max_cols == 1 + 1 + 2 + 1);
    fb = fbuf_new(cw * 8, ch);
    ulayout_draw(&l, g, fb, 0, 0, fb->w, fb->h, 0x000000, 0xFFFFFF);
    fbuf_free(fb);
    ulayout_free(&l);

    /* the display copy applies the gamma curve and keeps white and black */
    CHECK(fbuf_gamma(0) == 0 && fbuf_gamma(255) == 255 && fbuf_gamma(128) > 90 && fbuf_gamma(128) < 128);

    uglyphs_free(g);
    TEST_DONE("test_uview");
}
