#ifndef RECT_H
#define RECT_H

/* Rectangular (column) selections: the text that a rectangle of columns covers across whole lines, and edits to it.  A
 * buffer is a run of whole lines separated by '\n' (UTF-16 units; no newline needed at the end).  A column is a screen
 * column, a tab going to the next multiple of 8, so the rectangle lines up for a fixed-pitch font.  A character belongs to
 * the rectangle when it starts in [c0, c1). */

#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;
#endif

/* The index of the first character of the line t[0, n) that starts at column `col` or later (n if there is none).  If the
 * line ends before that column, *short_by is how many columns it is short (else 0). */
unsigned rect_index_at_column(const u16 *t, unsigned n, unsigned col, unsigned *short_by);

/* The column at which character `index` of the line t[0, n) starts. */
unsigned rect_column_of_index(const u16 *t, unsigned n, unsigned index);

/* The rectangle's text, one line per line of the buffer (a line that ends before c0 gives an empty line).  *out is malloc'd. */
int rect_extract(const u16 *t, unsigned n, unsigned c0, unsigned c1, u16 **out, unsigned *outlen);

/* Replaces the rectangle's text.  With `per_line` set, `ins` is lines separated by '\n': line k replaces what line k of the
 * buffer has in the rectangle, and more lines than the buffer has are added at the end.  Without it, `ins` goes in on every
 * line.  A line shorter than c0 is padded with blanks when something goes in.  Returns 1 and a malloc'd buffer. */
int rect_replace(const u16 *t, unsigned n, unsigned c0, unsigned c1, const u16 *ins, unsigned nins, int per_line,
                 u16 **out, unsigned *outlen);

#endif
