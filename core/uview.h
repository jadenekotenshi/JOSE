#ifndef UVIEW_H
#define UVIEW_H

#include <stddef.h>
#include "fbuf.h"
#include "uglyph.h"

/* The Unicode view's layout and drawing: UTF-16 text on a grid of character cells (a wide character takes two, a combining mark none,
 * a tab goes to the next multiple of tab_width), drawn through FreeType into a framebuffer.  No wrapping.  Plain C apart from uglyph. */

typedef unsigned short u16;

typedef struct {
    const u16 *text;           /* not copied; must outlive the layout */
    size_t len;
    size_t *starts;            /* offset of each line's first unit */
    size_t nlines;
    int cellw, cellh, ascent;
    int tab_width;
    unsigned long max_cols;    /* width of the widest line, in cells */
} ULayout;

int ulayout_build(ULayout *l, const u16 *text, size_t len, const UGlyphs *g, int tab_width);   /* 0 if out of memory */
void ulayout_free(ULayout *l);

/* [first,end) of line n without its line ending */
void ulayout_line(const ULayout *l, size_t n, size_t *first, size_t *end);
size_t ulayout_line_at_y(const ULayout *l, int y);

/* Draws the part of the text in the rectangle (x, y, w, h) -- in the text's own pixel coordinates -- into fb, whose pixel (0,0) is (x, y). */
void ulayout_draw(const ULayout *l, UGlyphs *g, FBuf *fb, int x, int y, int w, int h, unsigned long fg, unsigned long bg);

#endif
