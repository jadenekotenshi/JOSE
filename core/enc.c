#include "enc.h"
#include "enc_tables.h"
#include "nsenc_tab.h"
#include <stdlib.h>
#include <string.h>

#define ESC_BASE 0xDC00u                       /* a bad byte b is held as ESC_BASE + b (b >= 0x80) */

static const char *const NAMES[ENC_COUNT] = {
    "UTF-8", "UTF-8 with BOM", "UTF-16 LE", "UTF-16 BE",
    "ISO-8859-1", "ISO-8859-2", "ISO-8859-5", "ISO-8859-7", "ISO-8859-9", "ISO-8859-15",
    "Windows-1250", "Windows-1251", "Windows-1252", "KOI8-R", "Mac Roman", "NeXTSTEP",
    "Shift_JIS", "EUC-JP", "GBK", "Big5", "EUC-KR"
};

const char *enc_name(int enc)
{
    return (enc >= 0 && enc < ENC_COUNT) ? NAMES[enc] : "?";
}

static int ci_equal(const char *a, const char *b)
{
    for (; *a != '\0' && *b != '\0'; a++, b++) {
        int x = *a, y = *b;

        if (x >= 'A' && x <= 'Z') x += 32;
        if (y >= 'A' && y <= 'Z') y += 32;
        if (x != y) return 0;
    }
    return *a == *b;
}

int enc_by_name(const char *name)
{
    int i;

    for (i = 0; i < ENC_COUNT; i++) if (ci_equal(NAMES[i], name)) return i;
    if (ci_equal(name, "utf8")) return ENC_UTF8;
    if (ci_equal(name, "latin1") || ci_equal(name, "iso8859-1")) return ENC_LATIN1;
    if (ci_equal(name, "sjis") || ci_equal(name, "shift-jis") || ci_equal(name, "cp932")) return ENC_SJIS;
    if (ci_equal(name, "cp1252")) return ENC_CP1252;
    return -1;
}

/* ---- a growing UTF-16 buffer ---- */

typedef struct { u16 *v; size_t n, cap; int fail; } U16Buf;

static void ub_put(U16Buf *b, unsigned c)
{
    if (b->fail) return;
    if (b->n == b->cap) {
        size_t nc = b->cap ? b->cap * 2 : 1024;
        u16 *nv = (u16 *)realloc(b->v, nc * sizeof(u16));

        if (nv == NULL) { b->fail = 1; return; }
        b->v = nv;
        b->cap = nc;
    }
    b->v[b->n++] = (u16)c;
}

static void ub_put_cp(U16Buf *b, unsigned long cp)
{
    if (cp >= 0x10000UL) {
        cp -= 0x10000UL;
        ub_put(b, 0xD800u + (unsigned)(cp >> 10));
        ub_put(b, 0xDC00u + (unsigned)(cp & 0x3FF));
    } else {
        ub_put(b, (unsigned)cp);
    }
}

/* ---- UTF-8 ---- */

/* The length of the valid UTF-8 sequence at b[i] (1 for ASCII), and its code point; 0 if there is none. */
static size_t utf8_seq(const unsigned char *b, size_t n, size_t i, unsigned long *cp)
{
    unsigned c = b[i];

    if (c < 0x80) { *cp = c; return 1; }
    if (c >= 0xC2 && c <= 0xDF && i + 1 < n && (b[i + 1] & 0xC0) == 0x80) {
        *cp = ((unsigned long)(c & 0x1F) << 6) | (b[i + 1] & 0x3F);
        return 2;
    }
    if (c >= 0xE0 && c <= 0xEF && i + 2 < n && (b[i + 1] & 0xC0) == 0x80 && (b[i + 2] & 0xC0) == 0x80) {
        unsigned long v = ((unsigned long)(c & 0x0F) << 12) | ((unsigned long)(b[i + 1] & 0x3F) << 6) | (b[i + 2] & 0x3F);

        if (v < 0x800 || (v >= 0xD800 && v <= 0xDFFF)) return 0;          /* overlong; a surrogate */
        *cp = v;
        return 3;
    }
    if (c >= 0xF0 && c <= 0xF4 && i + 3 < n && (b[i + 1] & 0xC0) == 0x80 && (b[i + 2] & 0xC0) == 0x80 && (b[i + 3] & 0xC0) == 0x80) {
        unsigned long v = ((unsigned long)(c & 0x07) << 18) | ((unsigned long)(b[i + 1] & 0x3F) << 12) |
                          ((unsigned long)(b[i + 2] & 0x3F) << 6) | (b[i + 3] & 0x3F);

        if (v < 0x10000UL || v > 0x10FFFFUL) return 0;
        *cp = v;
        return 4;
    }
    return 0;
}

static int utf8_valid(const unsigned char *b, size_t n)
{
    size_t i = 0;
    unsigned long cp;

    while (i < n) {
        size_t l = utf8_seq(b, n, i, &cp);

        if (l == 0) return 0;
        i += l;
    }
    return 1;
}

static u16 *decode_utf8(const unsigned char *b, size_t n, size_t *outn, size_t *bad)
{
    U16Buf u = { NULL, 0, 0, 0 };
    size_t i = 0;
    unsigned long cp;

    *bad = 0;
    while (i < n) {
        size_t l = utf8_seq(b, n, i, &cp);

        if (l == 0) { ub_put(&u, ESC_BASE + b[i]); (*bad)++; i++; }
        else { ub_put_cp(&u, cp); i += l; }
    }
    if (u.fail) { free(u.v); return NULL; }
    if (u.v == NULL) u.v = (u16 *)malloc(sizeof(u16));
    *outn = u.n;
    return u.v;
}

typedef struct { unsigned char *v; size_t n, cap; int fail; } ByteBuf;

static void bb_put(ByteBuf *b, unsigned c)
{
    if (b->fail) return;
    if (b->n == b->cap) {
        size_t nc = b->cap ? b->cap * 2 : 1024;
        unsigned char *nv = (unsigned char *)realloc(b->v, nc);

        if (nv == NULL) { b->fail = 1; return; }
        b->v = nv;
        b->cap = nc;
    }
    b->v[b->n++] = (unsigned char)c;
}

static void bb_utf8(ByteBuf *b, unsigned long cp)
{
    if (cp < 0x80) bb_put(b, (unsigned)cp);
    else if (cp < 0x800) { bb_put(b, 0xC0 | (unsigned)(cp >> 6)); bb_put(b, 0x80 | (unsigned)(cp & 0x3F)); }
    else if (cp < 0x10000UL) { bb_put(b, 0xE0 | (unsigned)(cp >> 12)); bb_put(b, 0x80 | (unsigned)((cp >> 6) & 0x3F)); bb_put(b, 0x80 | (unsigned)(cp & 0x3F)); }
    else {
        bb_put(b, 0xF0 | (unsigned)(cp >> 18));
        bb_put(b, 0x80 | (unsigned)((cp >> 12) & 0x3F));
        bb_put(b, 0x80 | (unsigned)((cp >> 6) & 0x3F));
        bb_put(b, 0x80 | (unsigned)(cp & 0x3F));
    }
}

/* The next character of UTF-16 text: its code point, or an escaped byte (*esc set), or U+FFFD for a lone surrogate.  Returns the units used. */
static size_t next_char(const u16 *t, size_t n, size_t i, unsigned long *cp, int *esc)
{
    unsigned c = t[i];

    *esc = 0;
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < n && t[i + 1] >= 0xDC00 && t[i + 1] <= 0xDFFF) {
        *cp = 0x10000UL + (((unsigned long)(c - 0xD800)) << 10) + (t[i + 1] - 0xDC00);
        return 2;
    }
    if (c >= ESC_BASE + 0x80 && c <= ESC_BASE + 0xFF) { *esc = 1; *cp = c - ESC_BASE; return 1; }
    if (c >= 0xD800 && c <= 0xDFFF) { *cp = 0xFFFD; return 1; }
    *cp = c;
    return 1;
}

/* ---- single-byte tables ---- */

static const u16 *single_hi(int enc)
{
    switch (enc) {
    case ENC_LATIN2: return enc_single[0].hi;
    case ENC_ISO8859_5: return enc_single[1].hi;
    case ENC_ISO8859_7: return enc_single[2].hi;
    case ENC_ISO8859_9: return enc_single[3].hi;
    case ENC_LATIN9: return enc_single[4].hi;
    case ENC_CP1250: return enc_single[5].hi;
    case ENC_CP1251: return enc_single[6].hi;
    case ENC_CP1252: return enc_single[7].hi;
    case ENC_KOI8R: return enc_single[8].hi;
    case ENC_MACROMAN: return enc_single[9].hi;
    default: return NULL;
    }
}

static int is_single(int enc)
{
    return enc == ENC_LATIN1 || enc == ENC_NEXTSTEP || single_hi(enc) != NULL;
}

/* The character of a high byte (0x80..0xFF) in a single-byte encoding; 0xFFFF if none. */
static unsigned single_char(int enc, unsigned b)
{
    const u16 *hi;

    if (enc == ENC_LATIN1) return b;
    if (enc == ENC_NEXTSTEP) return NS_TO_UNI[b - 0x80] == 0xFFFD ? 0xFFFFu : NS_TO_UNI[b - 0x80];
    hi = single_hi(enc);
    return hi[b - 0x80];
}

static u16 *decode_single(int enc, const unsigned char *b, size_t n, size_t *outn, size_t *bad)
{
    u16 *out = (u16 *)malloc((n + 1) * sizeof(u16));
    size_t i;

    if (out == NULL) return NULL;
    *bad = 0;
    for (i = 0; i < n; i++) {
        if (b[i] < 0x80) out[i] = b[i];
        else {
            unsigned c = single_char(enc, b[i]);

            if (c == 0xFFFF) { out[i] = (u16)(ESC_BASE + b[i]); (*bad)++; }
            else out[i] = (u16)c;
        }
    }
    *outn = n;
    return out;
}

/* ---- the reverse tables (character -> bytes), made the first time an encoding is written ---- */

typedef struct { unsigned short cp; unsigned short code; unsigned char len; } Rev;       /* code: 1 or 2 bytes (or the low 16 bits of 3) */
typedef struct { Rev *v; size_t n; int ready; } RevTable;

static RevTable revs[ENC_COUNT];

static int rev_cmp(const void *a, const void *b)
{
    const Rev *x = (const Rev *)a, *y = (const Rev *)b;

    if (x->cp != y->cp) return x->cp < y->cp ? -1 : 1;
    return x->code < y->code ? -1 : (x->code > y->code ? 1 : 0);
}

static void rev_add(Rev *v, size_t *n, unsigned cp, unsigned code, unsigned len)
{
    v[*n].cp = (unsigned short)cp;
    v[*n].code = (unsigned short)code;
    v[*n].len = (unsigned char)len;
    (*n)++;
}

static void add_double(Rev *v, size_t *n, const EncDouble *t, unsigned prefix)
{
    unsigned lead, trail, w = (unsigned)t->thi - t->tlo + 1;

    for (lead = t->llo; lead <= t->lhi; lead++)
        for (trail = t->tlo; trail <= t->thi; trail++) {
            unsigned c = t->map[(lead - t->llo) * w + (trail - t->tlo)];

            if (c != 0) rev_add(v, n, c, (lead << 8) | trail, prefix ? 3 : 2);
        }
}

static void add_high(Rev *v, size_t *n, const EncHigh *h)
{
    unsigned b;

    for (b = 0x80; b <= 0xFF; b++) if (h->hi[b - 0x80] != 0xFFFF) rev_add(v, n, h->hi[b - 0x80], b, 1);
}

static RevTable *rev_for(int enc)
{
    RevTable *r = &revs[enc];
    Rev *v;
    size_t n = 0;

    if (r->ready) return r;
    v = (Rev *)malloc(70000 * sizeof(Rev));
    if (v == NULL) return NULL;
    switch (enc) {
    case ENC_SJIS: add_high(v, &n, &enc_high_cp932); add_double(v, &n, &enc_db_cp932, 0); break;
    case ENC_EUCJP: {
        unsigned b;
        add_double(v, &n, &enc_db_jis0208, 0);
        add_double(v, &n, &enc_db_jis0212, 1);
        for (b = 0xA1; b <= 0xDF; b++) rev_add(v, &n, 0xFF61u + (b - 0xA1), 0x8E00u | b, 2);        /* half-width katakana: 8E xx */
        break;
    }
    case ENC_GBK: add_high(v, &n, &enc_high_gbk); add_double(v, &n, &enc_db_gbk, 0); break;
    case ENC_BIG5: add_high(v, &n, &enc_high_cp950); add_double(v, &n, &enc_db_cp950, 0); break;
    case ENC_EUCKR: add_high(v, &n, &enc_high_cp949); add_double(v, &n, &enc_db_cp949, 0); break;
    default: break;
    }
    qsort(v, n, sizeof(Rev), rev_cmp);
    r->v = v;
    r->n = n;
    r->ready = 1;
    return r;
}

static const Rev *rev_find(const RevTable *r, unsigned cp)
{
    size_t lo = 0, hi = r->n;

    while (lo < hi) {
        size_t mid = (lo + hi) / 2;

        if (r->v[mid].cp < cp) lo = mid + 1; else hi = mid;
    }
    return (lo < r->n && r->v[lo].cp == cp) ? &r->v[lo] : NULL;       /* the first (lowest code) of those that have it */
}

/* ---- the multi-byte decoders ---- */

static u16 *decode_multi(int enc, const unsigned char *b, size_t n, size_t *outn, size_t *bad)
{
    U16Buf u = { NULL, 0, 0, 0 };
    const EncDouble *db;
    const EncHigh *hi;
    size_t i = 0;

    *bad = 0;
    switch (enc) {
    case ENC_SJIS: db = &enc_db_cp932; hi = &enc_high_cp932; break;
    case ENC_EUCJP: db = &enc_db_jis0208; hi = &enc_high_eucjp; break;
    case ENC_GBK: db = &enc_db_gbk; hi = &enc_high_gbk; break;
    case ENC_BIG5: db = &enc_db_cp950; hi = &enc_high_cp950; break;
    default: db = &enc_db_cp949; hi = &enc_high_cp949; break;
    }
    while (i < n) {
        unsigned c = b[i];

        if (c < 0x80) { ub_put(&u, c); i++; continue; }
        if (enc == ENC_EUCJP && c == 0x8E && i + 1 < n && b[i + 1] >= 0xA1 && b[i + 1] <= 0xDF) {
            ub_put(&u, 0xFF61u + (b[i + 1] - 0xA1));
            i += 2;
            continue;
        }
        if (enc == ENC_EUCJP && c == 0x8F && i + 2 < n && b[i + 1] >= 0xA1 && b[i + 2] >= 0xA1) {
            const EncDouble *d2 = &enc_db_jis0212;
            unsigned v = d2->map[(b[i + 1] - d2->llo) * ((unsigned)d2->thi - d2->tlo + 1) + (b[i + 2] - d2->tlo)];

            if (v != 0) { ub_put(&u, v); i += 3; continue; }
        }
        if (c >= db->llo && c <= db->lhi && i + 1 < n && b[i + 1] >= db->tlo && b[i + 1] <= db->thi) {
            unsigned v = db->map[(c - db->llo) * ((unsigned)db->thi - db->tlo + 1) + (b[i + 1] - db->tlo)];

            if (v != 0) { ub_put(&u, v); i += 2; continue; }
        }
        if (enc != ENC_EUCJP && hi->hi[c - 0x80] != 0xFFFF) { ub_put(&u, hi->hi[c - 0x80]); i++; continue; }      /* a single high byte */
        ub_put(&u, ESC_BASE + c);
        (*bad)++;
        i++;
    }
    if (u.fail) { free(u.v); return NULL; }
    if (u.v == NULL) u.v = (u16 *)malloc(sizeof(u16));
    *outn = u.n;
    return u.v;
}

/* ---- UTF-16 ---- */

static u16 *decode_utf16(int enc, const unsigned char *b, size_t n, size_t *outn, size_t *bad)
{
    size_t i = 0, o = 0;
    u16 *out;
    int le = enc == ENC_UTF16LE;

    *bad = 0;
    if (n >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) i = 2;
    out = (u16 *)malloc((n / 2 + 2) * sizeof(u16));
    if (out == NULL) return NULL;
    for (; i + 1 < n; i += 2) out[o++] = le ? (u16)(b[i] | (b[i + 1] << 8)) : (u16)((b[i] << 8) | b[i + 1]);
    if (i < n) { out[o++] = (u16)(ESC_BASE + b[i]); (*bad)++; }          /* a half unit at the end: kept (as a bad byte) */
    *outn = o;
    return out;
}

/* ---- the public decode and encode ---- */

u16 *enc_decode(int enc, const unsigned char *b, size_t n, size_t *outn, size_t *bad)
{
    size_t dummy_bad;

    if (bad == NULL) bad = &dummy_bad;
    *outn = 0;
    *bad = 0;
    switch (enc) {
    case ENC_UTF8:
        return decode_utf8(b, n, outn, bad);
    case ENC_UTF8_BOM:
        if (n >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) { b += 3; n -= 3; }
        return decode_utf8(b, n, outn, bad);
    case ENC_UTF16LE:
    case ENC_UTF16BE:
        return decode_utf16(enc, b, n, outn, bad);
    default:
        if (is_single(enc)) return decode_single(enc, b, n, outn, bad);
        if (enc >= ENC_SJIS && enc <= ENC_EUCKR) return decode_multi(enc, b, n, outn, bad);
        return NULL;
    }
}

static unsigned char *encode_utf8(const u16 *t, size_t n, size_t *outn, int bom)
{
    ByteBuf o = { NULL, 0, 0, 0 };
    size_t i = 0;
    unsigned long cp;
    int esc;

    if (bom) { bb_put(&o, 0xEF); bb_put(&o, 0xBB); bb_put(&o, 0xBF); }
    while (i < n) {
        i += next_char(t, n, i, &cp, &esc);
        if (esc) bb_put(&o, (unsigned)cp);                     /* a byte that was not valid when read goes back as it was */
        else bb_utf8(&o, cp);
    }
    if (o.fail) { free(o.v); return NULL; }
    if (o.v == NULL) o.v = (unsigned char *)malloc(1);
    *outn = o.n;
    return o.v;
}

static unsigned char *encode_utf16(int enc, const u16 *t, size_t n, size_t *outn)
{
    unsigned char *o = (unsigned char *)malloc(n * 2 + 3);
    size_t i, k = 0;
    int le = enc == ENC_UTF16LE;

    if (o == NULL) return NULL;
    o[k++] = le ? 0xFF : 0xFE;
    o[k++] = le ? 0xFE : 0xFF;
    for (i = 0; i < n; i++) {
        unsigned c = t[i];

        if (c >= ESC_BASE && c <= ESC_BASE + 0xFF && i + 1 == n && !(i > 0 && t[i - 1] >= 0xD800 && t[i - 1] <= 0xDBFF)) { o[k++] = (unsigned char)(c - ESC_BASE); continue; }     /* the half unit read */
        o[k++] = le ? (unsigned char)(c & 0xFF) : (unsigned char)(c >> 8);
        o[k++] = le ? (unsigned char)(c >> 8) : (unsigned char)(c & 0xFF);
    }
    *outn = k;
    return o;
}

/* The bytes of one character in a legacy encoding: returns how many (0 if it cannot be written), stored in out[]. */
static int legacy_bytes(int enc, unsigned long cp, unsigned char *out)
{
    unsigned c;

    if (cp < 0x80) { out[0] = (unsigned char)cp; return 1; }
    if (is_single(enc)) {
        for (c = 0x80; c <= 0xFF; c++) if (single_char(enc, c) == cp) { out[0] = (unsigned char)c; return 1; }
        return 0;
    }
    if (cp > 0xFFFF) return 0;
    {
        RevTable *r = rev_for(enc);
        const Rev *e;

        if (r == NULL) return 0;
        e = rev_find(r, (unsigned)cp);
        if (e == NULL) return 0;
        if (e->len == 1) { out[0] = (unsigned char)e->code; return 1; }
        if (e->len == 3) { out[0] = 0x8F; out[1] = (unsigned char)(e->code >> 8); out[2] = (unsigned char)(e->code & 0xFF); return 3; }
        out[0] = (unsigned char)(e->code >> 8);
        out[1] = (unsigned char)(e->code & 0xFF);
        return 2;
    }
}

unsigned char *enc_encode(int enc, const u16 *t, size_t n, size_t *outn, size_t *unmappable)
{
    ByteBuf o = { NULL, 0, 0, 0 };
    size_t i = 0, dummy;
    unsigned long cp;
    int esc;
    unsigned char tmp[4];

    if (unmappable == NULL) unmappable = &dummy;
    *unmappable = 0;
    *outn = 0;
    if (enc == ENC_UTF8) return encode_utf8(t, n, outn, 0);
    if (enc == ENC_UTF8_BOM) return encode_utf8(t, n, outn, 1);
    if (enc == ENC_UTF16LE || enc == ENC_UTF16BE) return encode_utf16(enc, t, n, outn);
    while (i < n) {
        int k, j;

        i += next_char(t, n, i, &cp, &esc);
        if (esc) { bb_put(&o, (unsigned)cp); continue; }
        k = legacy_bytes(enc, cp, tmp);
        if (k == 0) { bb_put(&o, '?'); (*unmappable)++; continue; }
        for (j = 0; j < k; j++) bb_put(&o, tmp[j]);
    }
    if (o.fail) { free(o.v); return NULL; }
    if (o.v == NULL) o.v = (unsigned char *)malloc(1);
    *outn = o.n;
    return o.v;
}

size_t enc_unmappable(int enc, const u16 *t, size_t n)
{
    size_t i = 0, bad = 0;
    unsigned long cp;
    int esc;
    unsigned char tmp[4];

    if (enc == ENC_UTF8 || enc == ENC_UTF8_BOM || enc == ENC_UTF16LE || enc == ENC_UTF16BE) return 0;
    while (i < n) {
        i += next_char(t, n, i, &cp, &esc);
        if (!esc && legacy_bytes(enc, cp, tmp) == 0) bad++;
    }
    return bad;
}

/* ---- detecting ---- */

int enc_detect(const unsigned char *b, size_t n)
{
    size_t i;
    int ascii = 1;

    if (n >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) return ENC_UTF8_BOM;
    if (n >= 2 && b[0] == 0xFF && b[1] == 0xFE) return ENC_UTF16LE;
    if (n >= 2 && b[0] == 0xFE && b[1] == 0xFF) return ENC_UTF16BE;
    for (i = 0; i < n; i++) if (b[i] >= 0x80) { ascii = 0; break; }
    if (ascii || utf8_valid(b, n)) return ENC_UTF8;
    return ENC_LATIN1;
}

int enc_looks_binary(const unsigned char *b, size_t n)
{
    size_t i;

    if (n >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) return 0;
    for (i = 0; i < n; i++) if (b[i] == 0) return 1;
    return 0;
}

/* ---- strings ---- */

u16 *enc_utf8_to_utf16(const char *s, size_t n, size_t *outn)
{
    size_t bad;

    return decode_utf8((const unsigned char *)s, n, outn, &bad);
}

char *enc_utf16_to_utf8(const u16 *t, size_t n, size_t *outn)
{
    size_t k;
    unsigned char *o = encode_utf8(t, n, &k, 0);
    char *r;

    if (o == NULL) return NULL;
    r = (char *)realloc(o, k + 1);
    if (r == NULL) r = (char *)o;
    r[k] = '\0';
    *outn = k;
    return r;
}
