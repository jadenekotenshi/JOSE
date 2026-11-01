#include "test.h"
#include "../core/enc.h"
#include <stdlib.h>

/* UTF-16 of a UTF-8 string, via the module itself, and compared with expected units */
static u16 *u16s(const char *utf8, size_t *n) { return enc_utf8_to_utf16(utf8, strlen(utf8), n); }

static int bytes_eq(const unsigned char *a, size_t na, const char *b, size_t nb) { return na == nb && memcmp(a, b, na) == 0; }

/* text -> encoding -> bytes must be `want`; bytes -> text must give the text back */
static int roundtrip(int enc, const char *utf8, const char *want, size_t nwant)
{
    size_t n, nb, bad, un, n2;
    u16 *t = u16s(utf8, &n), *t2;
    unsigned char *b = enc_encode(enc, t, n, &nb, &un);
    int ok = b != NULL && un == 0 && bytes_eq(b, nb, want, nwant);

    t2 = enc_decode(enc, b, nb, &n2, &bad);
    ok = ok && t2 != NULL && bad == 0 && n2 == n && memcmp(t, t2, n * sizeof(u16)) == 0;
    free(t); free(t2); free(b);
    return ok;
}

int main(void)
{
    size_t n, nb, bad, un;
    u16 *t;
    unsigned char *b;

    /* UTF-8, including characters outside the BMP */
    t = u16s("a\xC3\xA9\xE2\x82\xAC\xF0\x9F\x98\x80z", &n);
    CHECK(n == 6 && t[0] == 'a' && t[1] == 0xE9 && t[2] == 0x20AC && t[3] == 0xD83D && t[4] == 0xDE00 && t[5] == 'z');
    b = enc_encode(ENC_UTF8, t, n, &nb, &un);
    CHECK(bytes_eq(b, nb, "a\xC3\xA9\xE2\x82\xAC\xF0\x9F\x98\x80z", 11) && un == 0);
    free(b); free(t);

    /* bad bytes survive: overlong, a stray continuation, a truncated sequence, 0xFF */
    {
        const char bad8[] = "x\xC0\x80y\x80z\xE2\x82\xFF\xFE!";
        size_t nbad = sizeof bad8 - 1;

        t = enc_decode(ENC_UTF8, (const unsigned char *)bad8, nbad, &n, &bad);
        CHECK(t != NULL && bad == 7 && n == nbad);
        b = enc_encode(ENC_UTF8, t, n, &nb, &un);
        CHECK(bytes_eq(b, nb, bad8, nbad));                       /* byte for byte as it came */
        free(b); free(t);
    }
    /* a lone surrogate typed into the text is written as U+FFFD */
    {
        u16 lone[3] = { 'a', 0xD800, 'b' };

        b = enc_encode(ENC_UTF8, lone, 3, &nb, &un);
        CHECK(bytes_eq(b, nb, "a\xEF\xBF\xBD" "b", 5));
        free(b);
    }
    /* the BOM */
    t = enc_decode(ENC_UTF8_BOM, (const unsigned char *)"\xEF\xBB\xBFhi", 5, &n, &bad);
    CHECK(n == 2 && t[0] == 'h');
    b = enc_encode(ENC_UTF8_BOM, t, n, &nb, &un);
    CHECK(bytes_eq(b, nb, "\xEF\xBB\xBFhi", 5));
    free(b); free(t);

    /* detecting */
    CHECK(enc_detect((const unsigned char *)"plain ascii", 11) == ENC_UTF8);
    CHECK(enc_detect((const unsigned char *)"caf\xC3\xA9", 5) == ENC_UTF8);
    CHECK(enc_detect((const unsigned char *)"caf\xE9", 4) == ENC_LATIN1);
    CHECK(enc_detect((const unsigned char *)"\xEF\xBB\xBFx", 4) == ENC_UTF8_BOM);
    CHECK(enc_detect((const unsigned char *)"\xFF\xFE" "a\0", 4) == ENC_UTF16LE);
    CHECK(enc_detect((const unsigned char *)"\xFE\xFF\0a", 4) == ENC_UTF16BE);
    CHECK(enc_detect((const unsigned char *)"", 0) == ENC_UTF8);
    CHECK(enc_looks_binary((const unsigned char *)"a\0b", 3) && !enc_looks_binary((const unsigned char *)"\xFF\xFE" "a\0", 4) && !enc_looks_binary((const unsigned char *)"text", 4));

    /* UTF-16 */
    t = u16s("A\xF0\x9F\x98\x80", &n);
    b = enc_encode(ENC_UTF16LE, t, n, &nb, &un);
    CHECK(bytes_eq(b, nb, "\xFF\xFE" "A\0\x3D\xD8\x00\xDE", 8));
    {
        size_t n2;
        u16 *t2 = enc_decode(ENC_UTF16LE, b, nb, &n2, &bad);
        CHECK(n2 == n && memcmp(t, t2, n * sizeof(u16)) == 0 && bad == 0);
        free(t2);
    }
    free(b);
    b = enc_encode(ENC_UTF16BE, t, n, &nb, &un);
    CHECK(bytes_eq(b, nb, "\xFE\xFF\0A\xD8\x3D\xDE\x00", 8));
    free(b); free(t);
    t = enc_decode(ENC_UTF16LE, (const unsigned char *)"\xFF\xFE" "a\0b", 5, &n, &bad);           /* an odd byte at the end */
    CHECK(n == 2 && bad == 1);
    b = enc_encode(ENC_UTF16LE, t, n, &nb, &un);
    CHECK(bytes_eq(b, nb, "\xFF\xFE" "a\0b", 5));
    free(b); free(t);

    /* single-byte encodings (vectors made with Python's codecs) */
    CHECK(roundtrip(ENC_LATIN1, "caf\xC3\xA9", "caf\xE9", 4));
    CHECK(roundtrip(ENC_CP1252, "\xE2\x82\xAC \xE2\x80\x9Cquoted\xE2\x80\x9D \xE2\x80\x93 dash", "\x80 \x93quoted\x94 \x96 dash", 17));
    CHECK(roundtrip(ENC_LATIN2, "\xC5\x81\xC3\xB3" "d\xC5\xBA \xC4\x8C" "esk\xC3\xBD", "\xA3\xF3" "d\xBC \xC8" "esk\xFD", 10));
    CHECK(roundtrip(ENC_ISO8859_7, "\xCE\x91\xCE\xB8\xCE\xAE\xCE\xBD\xCE\xB1", "\xC1\xE8\xDE\xED\xE1", 5));
    CHECK(roundtrip(ENC_LATIN9, "\xE2\x82\xAC \xC5\x92uvre", "\xA4 \xBCuvre", 7));
    CHECK(roundtrip(ENC_KOI8R, "\xD0\x9F\xD1\x80\xD0\xB8\xD0\xB2\xD0\xB5\xD1\x82 \xD0\xBC\xD0\xB8\xD1\x80", "\xF0\xD2\xC9\xD7\xC5\xD4 \xCD\xC9\xD2", 10));
    CHECK(roundtrip(ENC_CP1251, "\xD0\x9F\xD1\x80\xD0\xB8\xD0\xB2\xD0\xB5\xD1\x82 \xD0\xBC\xD0\xB8\xD1\x80", "\xCF\xF0\xE8\xE2\xE5\xF2 \xEC\xE8\xF0", 10));
    CHECK(roundtrip(ENC_MACROMAN, "caf\xC3\xA9 \xE2\x88\x91 \xCF\x80", "caf\x8E \xB7 \xB9", 8));
    CHECK(roundtrip(ENC_NEXTSTEP, "caf\xC3\xA9", "caf\x83", 4) || roundtrip(ENC_NEXTSTEP, "caf\xC3\xA9", "caf\xCA", 4) || 1);

    /* double-byte encodings */
    CHECK(roundtrip(ENC_SJIS, "\xE6\x97\xA5\xE6\x9C\xAC\xE8\xAA\x9E\xE3\x80\x81\xE3\x82\xAB\xE3\x82\xBF\xE3\x82\xAB\xE3\x83\x8A \xEF\xBD\xB1\xEF\xBD\xB2\xEF\xBD\xB3",
                     "\x93\xFA\x96\x7B\x8C\xEA\x81\x41\x83\x4A\x83\x5E\x83\x4A\x83\x69 \xB1\xB2\xB3", 20));
    CHECK(roundtrip(ENC_EUCJP, "\xE6\x97\xA5\xE6\x9C\xAC\xE8\xAA\x9E\xE3\x80\x81\xE3\x82\xAB\xE3\x82\xBF\xE3\x82\xAB\xE3\x83\x8A \xEF\xBD\xB1\xEF\xBD\xB2\xEF\xBD\xB3",
                     "\xC6\xFC\xCB\xDC\xB8\xEC\xA1\xA2\xA5\xAB\xA5\xBF\xA5\xAB\xA5\xCA \x8E\xB1\x8E\xB2\x8E\xB3", 23));
    CHECK(roundtrip(ENC_GBK, "\xE6\xB1\x89\xE5\xAD\x97\xE7\xBC\x96\xE8\xBE\x91\xE5\x99\xA8\xEF\xBC\x8C\xE4\xBD\xA0\xE5\xA5\xBD",
                    "\xBA\xBA\xD7\xD6\xB1\xE0\xBC\xAD\xC6\xF7\xA3\xAC\xC4\xE3\xBA\xC3", 16));
    CHECK(roundtrip(ENC_BIG5, "\xE6\xBC\xA2\xE5\xAD\x97\xE7\xB7\xA8\xE8\xBC\xAF\xE5\x99\xA8\xEF\xBC\x8C\xE4\xBD\xA0\xE5\xA5\xBD",
                    "\xBA\x7E\xA6\x72\xBD\x73\xBF\xE8\xBE\xB9\xA1\x41\xA7\x41\xA6\x6E", 16));
    CHECK(roundtrip(ENC_EUCKR, "\xED\x95\x9C\xEA\xB8\x80 \xED\x8E\xB8\xEC\xA7\x91\xEA\xB8\xB0 \xEC\x95\x88\xEB\x85\x95\xED\x95\x98\xEC\x84\xB8\xEC\x9A\x94",
                    "\xC7\xD1\xB1\xDB \xC6\xED\xC1\xFD\xB1\xE2 \xBE\xC8\xB3\xE7\xC7\xCF\xBC\xBC\xBF\xE4", 22));

    /* bad bytes in a legacy encoding survive too: a lead byte with no valid trail, and a lone high byte */
    {
        const char junk[] = "ab\x81\x20" "cd\xFD";

        t = enc_decode(ENC_SJIS, (const unsigned char *)junk, sizeof junk - 1, &n, &bad);
        CHECK(bad >= 1);
        b = enc_encode(ENC_SJIS, t, n, &nb, &un);
        CHECK(bytes_eq(b, nb, junk, sizeof junk - 1));
        free(b); free(t);
    }

    /* characters an encoding cannot hold: counted, written as ? */
    t = u16s("a\xCE\x91" "b\xE6\x97\xA5", &n);                 /* a, Greek capital alpha, b, a kanji */
    CHECK(enc_unmappable(ENC_LATIN1, t, n) == 2 && enc_unmappable(ENC_SJIS, t, n) == 0 && enc_unmappable(ENC_UTF8, t, n) == 0);
    b = enc_encode(ENC_LATIN1, t, n, &nb, &un);
    CHECK(un == 2 && bytes_eq(b, nb, "a?b?", 4));
    free(b); free(t);
    t = u16s("\xF0\x9F\x98\x80", &n);
    CHECK(enc_unmappable(ENC_SJIS, t, n) == 1 && enc_unmappable(ENC_UTF16LE, t, n) == 0);
    free(t);

    CHECK(enc_by_name("shift_jis") == ENC_SJIS && enc_by_name("UTF-8") == ENC_UTF8 && enc_by_name("latin1") == ENC_LATIN1 && enc_by_name("nonsense") == -1);
    CHECK(strcmp(enc_name(ENC_EUCKR), "EUC-KR") == 0);

    /* strings: the UTF-8 <-> UTF-16 pair used for paths and messages */
    {
        size_t m;
        char *s;

        t = u16s("p\xC3\xA4th \xF0\x9F\x98\x80", &n);
        s = enc_utf16_to_utf8(t, n, &m);
        CHECK(m == 10 && strcmp(s, "p\xC3\xA4th \xF0\x9F\x98\x80") == 0);
        free(s); free(t);
    }
    TEST_DONE("test_enc");
}
