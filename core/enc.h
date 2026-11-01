#ifndef ENC_H
#define ENC_H

/* Text encodings: turning the bytes of a file into UTF-16 (what the editor holds) and back.  Plain C so that it can be tested on the
 * host.  Nothing is ever lost: a byte that is not valid in the encoding becomes the lone surrogate U+DC00+byte ("surrogate escape"), and
 * writing that character back gives the byte again, so a file with a few bad bytes comes out byte for byte as it went in.  Text outside
 * the Basic Multilingual Plane is held as surrogate pairs. */

#include <stddef.h>

#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;
#endif

enum {
    ENC_UTF8 = 0, ENC_UTF8_BOM, ENC_UTF16LE, ENC_UTF16BE,
    ENC_LATIN1, ENC_LATIN2, ENC_ISO8859_5, ENC_ISO8859_7, ENC_ISO8859_9, ENC_LATIN9,
    ENC_CP1250, ENC_CP1251, ENC_CP1252, ENC_KOI8R, ENC_MACROMAN, ENC_NEXTSTEP,
    ENC_SJIS, ENC_EUCJP, ENC_GBK, ENC_BIG5, ENC_EUCKR,
    ENC_COUNT
};

const char *enc_name(int enc);             /* "UTF-8", "ISO-8859-1", "Shift_JIS" ... (the text shown to the user) */
int enc_by_name(const char *name);         /* case-insensitive; -1 if unknown */

/* The encoding a file's bytes are most likely in: a byte order mark decides (UTF-8 with BOM, UTF-16 LE/BE); then text that is plain
 * ASCII or valid UTF-8 is UTF-8; anything else is ISO-8859-1, which can carry every byte.  (The reader can always choose another.) */
int enc_detect(const unsigned char *b, size_t n);

/* Does this look like a binary file rather than text?  (NUL bytes -- unless it is UTF-16 with a byte order mark.) */
int enc_looks_binary(const unsigned char *b, size_t n);

/* The bytes as UTF-16 (malloc'd; the caller frees it; *outn units).  *bad is the number of bytes that were not valid in the encoding
 * and were kept as U+DC00+byte.  NULL only if out of memory.  A byte order mark that belongs to the encoding is dropped. */
u16 *enc_decode(int enc, const unsigned char *b, size_t n, size_t *outn, size_t *bad);

/* UTF-16 as bytes (malloc'd, *outn bytes), with a byte order mark for the encodings that have one.  Characters the encoding cannot
 * hold are written as '?' and counted in *unmappable.  NULL only if out of memory. */
unsigned char *enc_encode(int enc, const u16 *t, size_t n, size_t *outn, size_t *unmappable);

/* How many characters of the text the encoding cannot hold (what enc_encode would call unmappable). */
size_t enc_unmappable(int enc, const u16 *t, size_t n);

/* UTF-8 <-> UTF-16 for strings (paths, messages): the same conversions with the same escapes. */
u16 *enc_utf8_to_utf16(const char *s, size_t n, size_t *outn);
char *enc_utf16_to_utf8(const u16 *t, size_t n, size_t *outn);     /* NUL-terminated; *outn without the NUL */

#endif
