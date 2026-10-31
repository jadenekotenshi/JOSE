#ifndef FILL_H
#define FILL_H

/* Fill Paragraph: re-flows text to a right margin.  Plain C so that it can be tested on the host.
 *
 * A paragraph is a run of lines that are not blank.  Each line may carry a prefix: its leading blanks, and a comment leader
 * (`//`, `#`, `*`, `>`, `;`, `--`, `%`) followed by blanks.  The first line's prefix is kept on the first line and the second
 * line's on all the others (the usual hanging indent); a leader that the lines do not all share is treated as text. */

#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;
#endif

/* The whole lines of the paragraph that contains `pos`: [*start, *end) with *end at the line break (or the end of the text).
 * Returns 0 when the line at `pos` is blank. */
int fill_find_paragraph(const u16 *t, unsigned n, unsigned pos, unsigned *start, unsigned *end);

/* Re-flows every paragraph in t[0, n) (blank lines stay as they are) so that no line is wider than `width` columns, unless
 * a single word is.  A tab counts as the distance to the next multiple of 8.  Returns 1 and a malloc'd result when the text
 * changed, else 0. */
int fill_text(const u16 *t, unsigned n, unsigned width, u16 **out, unsigned *outlen);

#endif
