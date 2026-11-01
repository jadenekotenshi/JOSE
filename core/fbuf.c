#include "fbuf.h"
#include <stdlib.h>
#include <string.h>

FBuf *fbuf_new(int w, int h)
{
    FBuf *f = (FBuf *)malloc(sizeof(FBuf));

    if (f == NULL) return NULL;
    f->w = f->h = 0;
    f->px = NULL;
    if (!fbuf_resize(f, w, h)) {
        free(f);
        return NULL;
    }
    return f;
}

int fbuf_resize(FBuf *f, int w, int h)
{
    unsigned char *p;

    if (w < 1) w = 1;
    if (h < 1) h = 1;
    p = (unsigned char *)malloc((size_t)w * (size_t)h * 4);
    if (p == NULL) return 0;
    memset(p, 0xff, (size_t)w * (size_t)h * 4);
    free(f->px);
    f->px = p;
    f->w = w;
    f->h = h;
    return 1;
}

void fbuf_free(FBuf *f)
{
    if (f == NULL) return;
    free(f->px);
    free(f);
}

void fbuf_fill(FBuf *f, int x, int y, int w, int h, unsigned long rgb)
{
    int x1 = x + w, y1 = y + h, i, j;
    unsigned char r = (unsigned char)((rgb >> 16) & 0xff), g = (unsigned char)((rgb >> 8) & 0xff), b = (unsigned char)(rgb & 0xff);

    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x1 > f->w) x1 = f->w;
    if (y1 > f->h) y1 = f->h;
    for (j = y; j < y1; j++) {
        unsigned char *p = f->px + ((size_t)j * (size_t)f->w + (size_t)x) * 4;

        for (i = x; i < x1; i++, p += 4) {
            p[0] = r;
            p[1] = g;
            p[2] = b;
            p[3] = 0xff;
        }
    }
}

void fbuf_blend_a8(FBuf *f, int x, int y, const unsigned char *alpha, int aw, int ah, int stride, unsigned long rgb)
{
    int i, j;
    unsigned int r = (unsigned int)((rgb >> 16) & 0xff), g = (unsigned int)((rgb >> 8) & 0xff), b = (unsigned int)(rgb & 0xff);

    for (j = 0; j < ah; j++) {
        const unsigned char *a = alpha + (size_t)j * (size_t)stride;
        unsigned char *p;

        if (y + j < 0 || y + j >= f->h) continue;
        for (i = 0; i < aw; i++) {
            unsigned int c = a[i];

            if (c == 0 || x + i < 0 || x + i >= f->w) continue;
            p = f->px + ((size_t)(y + j) * (size_t)f->w + (size_t)(x + i)) * 4;
            if (c == 255) {
                p[0] = (unsigned char)r;
                p[1] = (unsigned char)g;
                p[2] = (unsigned char)b;
            } else {
                p[0] = (unsigned char)((r * c + p[0] * (255 - c) + 127) / 255);
                p[1] = (unsigned char)((g * c + p[1] * (255 - c) + 127) / 255);
                p[2] = (unsigned char)((b * c + p[2] * (255 - c) + 127) / 255);
            }
        }
    }
}

unsigned char fbuf_gamma(unsigned char v)
{
    unsigned int c = v;

    return (unsigned char)(((c * c + 127) / 255 + c) / 2);
}

void fbuf_to_display(const FBuf *f, unsigned char *out)
{
    size_t i, n = (size_t)f->w * (size_t)f->h;

    for (i = 0; i < n; i++) {
        out[i * 4 + 0] = fbuf_gamma(f->px[i * 4 + 0]);
        out[i * 4 + 1] = fbuf_gamma(f->px[i * 4 + 1]);
        out[i * 4 + 2] = fbuf_gamma(f->px[i * 4 + 2]);
        out[i * 4 + 3] = 0xff;
    }
}
