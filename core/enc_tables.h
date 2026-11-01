#ifndef ENC_TABLES_H
#define ENC_TABLES_H

/* The tables behind core/enc.c; core/enc_tables.c is written by tools/gen_enc_tables.py. */

#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;
#endif

#define ENC_N_SINGLE 10

typedef struct { const u16 *hi; } EncSingle;           /* the characters of bytes 0x80..0xFF; 0xFFFF where undefined */
typedef struct { const u16 *hi; } EncHigh;             /* the same, for the single bytes of a double-byte encoding */
typedef struct { unsigned char llo, lhi, tlo, thi; const u16 *map; } EncDouble;   /* indexed (lead - llo) * (thi - tlo + 1) + (trail - tlo); 0 = none */

extern const EncSingle enc_single[ENC_N_SINGLE];       /* ISO-8859-2, -5, -7, -9, -15, Windows-1250, -1251, -1252, KOI8-R, Mac Roman */
extern const EncHigh enc_high_cp932, enc_high_eucjp, enc_high_gbk, enc_high_cp950, enc_high_cp949;
extern const EncDouble enc_db_cp932, enc_db_jis0208, enc_db_gbk, enc_db_cp950, enc_db_cp949, enc_db_jis0212;

#endif
