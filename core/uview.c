#include "uview.h"
#include "wide.h"
#include <stdlib.h>

#define REPLACEMENT 0xFFFDUL

static int is_eol(u16 c) { return c == '\n' || c == '\r'; }

/* The code point at text[i], and how many units it took (a lone surrogate is a replacement character). */
static unsigned long next_cp(const u16 *t, size_t i, size_t end, size_t *used)
{
    u16 c = t[i];

    *used = 1;
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < end && t[i + 1] >= 0xDC00 && t[i + 1] <= 0xDFFF) {
        *used = 2;
        return 0x10000UL + (((unsigned long)(c - 0xD800)) << 10) + (unsigned long)(t[i + 1] - 0xDC00);
    }
    if (c >= 0xD800 && c <= 0xDFFF) return REPLACEMENT;
    return c;
}

int ulayout_build(ULayout *l, const u16 *text, size_t len, const UGlyphs *g, int tab_width)
{
    size_t i, cap = 256, n = 0;
    size_t *s = (size_t *)malloc(cap * sizeof(size_t));
    unsigned long cols = 0, widest = 0;

    if (s == NULL) return 0;
    uglyphs_cell(g, &l->cellw, &l->cellh, &l->ascent);
    l->text = text;
    l->len = len;
    l->tab_width = tab_width < 1 ? 8 : tab_width;
    s[n++] = 0;
    for (i = 0; i < len;) {
        if (is_eol(text[i])) {
            if (text[i] == '\r' && i + 1 < len && text[i + 1] == '\n') i++;
            i++;
            if (cols > widest) widest = cols;
            cols = 0;
            if (n == cap) {
                size_t *bigger = (size_t *)realloc(s, cap * 2 * sizeof(size_t));

                if (bigger == NULL) {
                    free(s);
                    return 0;
                }
                s = bigger;
                cap *= 2;
            }
            s[n++] = i;
        } else if (text[i] == '\t') {
            cols = (cols / (unsigned long)l->tab_width + 1) * (unsigned long)l->tab_width;
            i++;
        } else {
            size_t used;
            unsigned long cp = next_cp(text, i, len, &used);

            cols += (unsigned long)wide_cp(cp);
            i += used;
        }
    }
    if (cols > widest) widest = cols;
    l->starts = s;
    l->nlines = n;
    l->max_cols = widest;
    return 1;
}

void ulayout_free(ULayout *l)
{
    free(l->starts);
    l->starts = NULL;
    l->nlines = 0;
}

void ulayout_line(const ULayout *l, size_t n, size_t *first, size_t *end)
{
    size_t e;

    if (n >= l->nlines) {
        *first = *end = l->len;
        return;
    }
    *first = l->starts[n];
    e = n + 1 < l->nlines ? l->starts[n + 1] : l->len;
    while (e > *first && is_eol(l->text[e - 1])) e--;
    *end = e;
}

size_t ulayout_line_at_y(const ULayout *l, int y)
{
    size_t n;

    if (y < 0) return 0;
    n = (size_t)y / (size_t)l->cellh;
    return n < l->nlines ? n : l->nlines - 1;
}

void ulayout_draw(const ULayout *l, UGlyphs *g, FBuf *fb, int x, int y, int w, int h, unsigned long fg, unsigned long bg)
{
    size_t row, row0, row1;
    unsigned long col;

    fbuf_fill(fb, 0, 0, fb->w, fb->h, bg);
    if (l->nlines == 0 || y + h <= 0) return;
    row0 = y < 0 ? 0 : (size_t)y / (size_t)l->cellh;
    row1 = (size_t)(y + h + l->cellh - 1) / (size_t)l->cellh;
    if (row1 > l->nlines) row1 = l->nlines;
    for (row = row0; row < row1; row++) {
        size_t i, end, used;
        int base = (int)row * l->cellh + l->ascent - y;       /* baseline in fb coordinates */
        int prevx = 0;                    /* where the pen is after the last character with a width: the combining marks' own origin */

        ulayout_line(l, row, &i, &end);
        col = 0;
        while (i < end) {
            unsigned long cp;
            int cells, px;
            const UGlyph *gl;

            if (l->text[i] == '\t') {
                col = (col / (unsigned long)l->tab_width + 1) * (unsigned long)l->tab_width;
                i++;
                continue;
            }
            cp = next_cp(l->text, i, end, &used);
            i += used;
            cells = wide_cp(cp);
            if (cells == 0) {
                px = prevx;               /* fonts draw a combining mark relative to the pen after the character it goes on */
            } else {
                px = (int)(col * (unsigned long)l->cellw) - x;
                col += (unsigned long)cells;
                prevx = px + cells * l->cellw;
            }
            if (px >= w) break;
            if (px + cells * l->cellw + l->cellw < 0 && cells != 0) continue;
            if (cp < 0x20 || cp == 0x7F) continue;
            gl = uglyphs_get(g, cp);
            if (gl != NULL && gl->alpha != NULL)
                fbuf_blend_a8(fb, px + gl->left, base - gl->top, gl->alpha, gl->w, gl->h, gl->stride, fg);
        }
    }
}
