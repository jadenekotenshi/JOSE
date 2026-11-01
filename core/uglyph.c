#include "uglyph.h"
#include <ft2build.h>
#include FT_FREETYPE_H
#include <stdlib.h>
#include <string.h>

#define MAX_FACES 8
#define BUCKETS 1024

typedef struct Entry {
    unsigned long cp;
    UGlyph g;
    struct Entry *next;
} Entry;

struct UGlyphs {
    FT_Library lib;
    FT_Face faces[MAX_FACES];
    int nfaces;
    int px;
    int cellw, cellh, ascent;
    Entry *table[BUCKETS];
};

UGlyphs *uglyphs_new(int pixel_size)
{
    UGlyphs *g = (UGlyphs *)calloc(1, sizeof(UGlyphs));

    if (g == NULL) return NULL;
    if (FT_Init_FreeType(&g->lib) != 0) {
        free(g);
        return NULL;
    }
    g->px = pixel_size < 6 ? 6 : pixel_size;
    return g;
}

void uglyphs_free(UGlyphs *g)
{
    int i;
    Entry *e, *n;

    if (g == NULL) return;
    for (i = 0; i < BUCKETS; i++)
        for (e = g->table[i]; e != NULL; e = n) {
            n = e->next;
            free(e->g.alpha);
            free(e);
        }
    for (i = 0; i < g->nfaces; i++) FT_Done_Face(g->faces[i]);
    FT_Done_FreeType(g->lib);
    free(g);
}

int uglyphs_add_face(UGlyphs *g, const char *path, long index)
{
    FT_Face face;

    if (g->nfaces >= MAX_FACES) return 0;
    if (FT_New_Face(g->lib, path, index, &face) != 0) return 0;
    if (FT_Set_Pixel_Sizes(face, 0, (FT_UInt)g->px) != 0) {
        FT_Done_Face(face);
        return 0;
    }
    g->faces[g->nfaces++] = face;
    if (g->nfaces == 1) {
        FT_UInt gi = FT_Get_Char_Index(face, 'M');

        g->cellh = (int)((face->size->metrics.height + 63) >> 6);
        g->ascent = (int)((face->size->metrics.ascender + 63) >> 6);
        g->cellw = 0;
        if (gi != 0 && FT_Load_Glyph(face, gi, FT_LOAD_DEFAULT) == 0) g->cellw = (int)((face->glyph->advance.x + 32) >> 6);
        if (g->cellw < 1) g->cellw = g->px / 2 + 1;
        if (g->cellh < g->px) g->cellh = g->px + 2;
        if (g->ascent < 1 || g->ascent > g->cellh) g->ascent = g->cellh - g->cellh / 4;
    }
    return 1;
}

int uglyphs_count(const UGlyphs *g) { return g->nfaces; }

void uglyphs_cell(const UGlyphs *g, int *width, int *height, int *ascent)
{
    if (width != NULL) *width = g->cellw;
    if (height != NULL) *height = g->cellh;
    if (ascent != NULL) *ascent = g->ascent;
}

/* Renders glyph index gi of face into e->g; the bitmap is copied out of FreeType's slot. */
static int render(FT_Face face, FT_UInt gi, UGlyph *out)
{
    FT_GlyphSlot slot;
    FT_Bitmap *bm;
    int x, y;

    if (FT_Load_Glyph(face, gi, FT_LOAD_RENDER) != 0) return 0;
    slot = face->glyph;
    bm = &slot->bitmap;
    out->left = slot->bitmap_left;
    out->top = slot->bitmap_top;
    out->w = (int)bm->width;
    out->h = (int)bm->rows;
    out->stride = out->w;
    out->advance = (int)((slot->advance.x + 32) >> 6);
    out->alpha = NULL;
    if (out->w > 0 && out->h > 0) {
        out->alpha = (unsigned char *)malloc((size_t)out->w * (size_t)out->h);
        if (out->alpha == NULL) return 0;
        for (y = 0; y < out->h; y++) {
            const unsigned char *row = bm->buffer + (long)y * bm->pitch;

            for (x = 0; x < out->w; x++) {
                if (bm->pixel_mode == FT_PIXEL_MODE_MONO) out->alpha[y * out->w + x] = (row[x >> 3] & (0x80 >> (x & 7))) ? 255 : 0;
                else out->alpha[y * out->w + x] = row[x];
            }
        }
    }
    return 1;
}

const UGlyph *uglyphs_get(UGlyphs *g, unsigned long cp)
{
    unsigned int h = (unsigned int)(cp % BUCKETS);
    Entry *e;
    int i;

    if (g->nfaces == 0) return NULL;
    for (e = g->table[h]; e != NULL; e = e->next)
        if (e->cp == cp) return &e->g;
    e = (Entry *)calloc(1, sizeof(Entry));
    if (e == NULL) return NULL;
    e->cp = cp;
    for (i = 0; i < g->nfaces; i++) {
        FT_UInt gi = FT_Get_Char_Index(g->faces[i], (FT_ULong)cp);

        if (gi != 0 && render(g->faces[i], gi, &e->g)) {
            e->g.found = 1;
            break;
        }
    }
    if (!e->g.found) {
        memset(&e->g, 0, sizeof(e->g));
        render(g->faces[0], 0, &e->g);        /* the main font's own "missing" glyph (usually a box) */
    }
    e->next = g->table[h];
    g->table[h] = e;
    return &e->g;
}
