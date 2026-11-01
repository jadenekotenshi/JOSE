#include "cliphist.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void clip_init(ClipRing *r)
{
    r->n = 0;
}

void clip_free(ClipRing *r)
{
    int i;

    for (i = 0; i < r->n; i++) free(r->item[i].text);
    r->n = 0;
}

void clip_remove(ClipRing *r, int i)
{
    if (i < 0 || i >= r->n) return;
    free(r->item[i].text);
    for (; i + 1 < r->n; i++) r->item[i] = r->item[i + 1];
    r->n--;
}

int clip_add(ClipRing *r, const char *text, unsigned len, int rect)
{
    ClipItem it;
    int i;

    if (len == 0 || len > CLIP_MAX_BYTES) return 0;
    for (i = 0; i < r->n; i++)                                       /* the same text again: move it to the front */
        if (r->item[i].len == len && memcmp(r->item[i].text, text, len) == 0) {
            it = r->item[i];
            it.rect = rect;
            for (; i > 0; i--) r->item[i] = r->item[i - 1];
            r->item[0] = it;
            return 1;
        }
    it.text = (char *)malloc(len + 1);
    if (it.text == NULL) return 0;
    memcpy(it.text, text, len);
    it.text[len] = '\0';
    it.len = len;
    it.rect = rect;
    if (r->n == CLIP_MAX) { free(r->item[CLIP_MAX - 1].text); r->n--; }      /* the oldest goes */
    for (i = r->n; i > 0; i--) r->item[i] = r->item[i - 1];
    r->item[0] = it;
    r->n++;
    return 1;
}

void clip_preview(const ClipRing *r, int i, char *out, unsigned cap, unsigned maxchars)
{
    const char *t;
    unsigned len, k = 0, o = 0, chars = 0, lines = 1;
    int space = 0, started = 0, cut = 0;

    if (cap == 0) return;
    out[0] = '\0';
    if (i < 0 || i >= r->n) return;
    t = r->item[i].text;
    len = r->item[i].len;
    for (k = 0; k < len; k++) if (t[k] == '\n' && k + 1 < len) lines++;
    for (k = 0; k < len; k++) {
        unsigned char c = (unsigned char)t[k];
        unsigned seq = 1, q;

        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { if (started) space = 1; continue; }
        if (c >= 0xF0) seq = 4; else if (c >= 0xE0) seq = 3; else if (c >= 0xC0) seq = 2;
        if (k + seq > len) seq = len - k;
        if (chars >= maxchars) { cut = 1; break; }
        if (space) {
            if (o + 1 + 1 >= cap) { cut = 1; break; }
            out[o++] = ' ';
            chars++;
            space = 0;
            if (chars >= maxchars) { cut = 1; break; }
        }
        if (o + seq + 1 >= cap) { cut = 1; break; }
        for (q = 0; q < seq; q++) out[o++] = t[k + q];
        chars++;
        started = 1;
        k += seq - 1;
    }
    out[o] = '\0';
    if (cut && o + 4 < cap) { strcpy(out + o, "..."); o += 3; }
    if (lines > 1 && o + 20 < cap) sprintf(out + o, "  (%u lines)", lines);
}
