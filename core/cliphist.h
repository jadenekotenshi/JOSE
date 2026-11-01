#ifndef CLIPHIST_H
#define CLIPHIST_H

/* The clipboard history: the last few things cut or copied, newest first, as UTF-8 text.  A thing that is copied again moves to the
 * front rather than being stored twice.  Plain C so that it can be tested on the host. */

#define CLIP_MAX 30
#define CLIP_MAX_BYTES 400000UL        /* a bigger piece of text is not kept */

typedef struct {
    char    *text;                     /* NUL-terminated */
    unsigned len;
    int      rect;                     /* it came from a rectangular selection */
} ClipItem;

typedef struct {
    ClipItem item[CLIP_MAX];
    int      n;
} ClipRing;

void clip_init(ClipRing *r);
void clip_free(ClipRing *r);                                               /* frees the texts; the ring is empty again */
int  clip_add(ClipRing *r, const char *text, unsigned len, int rect);      /* 1 if kept; 0 if empty, too big or out of memory */
void clip_remove(ClipRing *r, int i);
/* One line to choose by: leading blanks dropped, runs of white space made one blank, cut to `maxchars` characters (never in the
 * middle of a UTF-8 sequence) with "..." after, and "  (N lines)" when the text spans several. */
void clip_preview(const ClipRing *r, int i, char *out, unsigned cap, unsigned maxchars);

#endif
