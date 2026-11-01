#ifndef FBUF_H
#define FBUF_H

/* A software framebuffer for the Unicode view: RGBA, 4 bytes a pixel, rows top to bottom (the layout NSDrawBitmap takes).  Plain C. */

typedef struct {
    int w, h;
    unsigned char *px;
} FBuf;

FBuf *fbuf_new(int w, int h);                         /* NULL if it cannot be allocated */
int fbuf_resize(FBuf *f, int w, int h);               /* keeps nothing; 0 if it cannot be allocated */
void fbuf_free(FBuf *f);

/* rgb is 0xRRGGBB.  Everything clips to the buffer. */
void fbuf_fill(FBuf *f, int x, int y, int w, int h, unsigned long rgb);
void fbuf_blend_a8(FBuf *f, int x, int y, const unsigned char *alpha, int aw, int ah, int stride, unsigned long rgb);   /* coverage bitmap in colour rgb */

/* The pixels as the display wants them: copied to out (w * h * 4 bytes) with the gamma compensation the NeXT screens need (the NetSurf port does the same). */
void fbuf_to_display(const FBuf *f, unsigned char *out);
unsigned char fbuf_gamma(unsigned char v);

#endif
