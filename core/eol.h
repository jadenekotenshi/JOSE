#ifndef EOL_H
#define EOL_H

#include <stddef.h>

#define EOL_LF   0
#define EOL_CRLF 1
#define EOL_CR   2

/* Which line ending the text mostly uses (ties go to LF); 'mixed' is set when more than one kind occurs. */
int eol_detect(const char *text, size_t n, int *mixed);

/* Rewrites the text in place so that every line ending is a single LF; NUL bytes become spaces.  Returns the new length. */
size_t eol_normalize(char *text, size_t n);

/* Writes the text with LF turned into the given ending into 'out' (which must hold eol_expanded_size(text, n, eol) bytes);
 * returns the number of bytes written. */
size_t eol_expanded_size(const char *text, size_t n, int eol);
size_t eol_expand(const char *text, size_t n, int eol, char *out);


/* The same four for UTF-16 text (the editor holds text that way). */
#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;
#endif
int eol16_detect(const u16 *text, size_t n, int *mixed);
size_t eol16_normalize(u16 *text, size_t n);                 /* every line ending a single LF; NUL becomes a space */
size_t eol16_expanded_size(const u16 *text, size_t n, int eol);
size_t eol16_expand(const u16 *text, size_t n, int eol, u16 *out);

#endif
