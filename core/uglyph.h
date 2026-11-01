#ifndef UGLYPH_H
#define UGLYPH_H

/* Glyphs from FreeType for the Unicode view: a list of font files (the first is the main font, the rest are tried in turn for
 * characters it lacks), rendered as 8-bit coverage bitmaps and cached.  The only file that needs FreeType; built with FT=1. */

typedef struct {
    int left, top;             /* the bitmap's position relative to the pen: left of the origin, top above the baseline */
    int w, h, stride;
    int advance;               /* pixels */
    unsigned char *alpha;      /* h rows of stride bytes; NULL when the glyph is blank */
    int found;                 /* 0: no font had the character and this is the main font's "missing" glyph */
} UGlyph;

typedef struct UGlyphs UGlyphs;

UGlyphs *uglyphs_new(int pixel_size);
void uglyphs_free(UGlyphs *g);
int uglyphs_add_face(UGlyphs *g, const char *path, long index);     /* 1 if the file is a usable font; collections take the face index */
int uglyphs_count(const UGlyphs *g);

/* The cell of the main font: width of "M" (all text is laid out on this grid), line height, and the baseline's distance from the top. */
void uglyphs_cell(const UGlyphs *g, int *width, int *height, int *ascent);
const UGlyph *uglyphs_get(UGlyphs *g, unsigned long cp);            /* NULL only if there is no font at all */

#endif
