#ifndef EDIT_H
#define EDIT_H

/* Line-oriented editing helpers: shifting, commenting and the indentation of a new line.  They work on a buffer of whole lines
 * (UTF-16 units, lines separated by '\n', no newline needed at the end) and hand back a malloc'd replacement.  Plain C so
 * that they can be tested on the host. */

#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;
#endif

/* Shifts every non-empty line one indent unit right (dir > 0) or left (dir < 0).  The unit is a tab, or `width` spaces when
 * use_spaces is set; shifting left takes away a tab or up to `width` leading spaces.  Returns 1 and sets the two output arguments when
 * something changed (the caller frees the buffer), else 0. */
int edit_shift_lines(const u16 *t, unsigned n, int dir, int use_spaces, unsigned width, u16 **out, unsigned *outlen);

/* Comments out every non-blank line with `pre` (and `suf` after the text, if there is one), at the indentation of the least
 * indented line; or, with `uncomment`, takes them away again from the lines that have them.  Returns 1 when something changed. */
int edit_comment_lines(const u16 *t, unsigned n, const u16 *pre, unsigned npre, const u16 *suf, unsigned nsuf, int uncomment,
                       u16 **out, unsigned *outlen);

/* The indentation for a new line, given the text of the current line up to the caret: that line's own leading blanks, plus one
 * unit more when `smart` is 'b' and the line ends in '{', or 'c' and it ends in ':' (Python).  Writes at most `cap` units to
 * `out` and returns how many there are. */
unsigned edit_newline_indent(const u16 *before, unsigned n, int smart, int use_spaces, unsigned width, u16 *out, unsigned cap);

/* For a '}' typed after only blanks: how many units of those blanks to delete first (one tab, or up to `width` spaces); 0 if
 * the text before the caret is not all blanks. */
unsigned edit_outdent_amount(const u16 *before, unsigned n, unsigned width);

/* The column (counting a tab as going to the next multiple of 8) at the end of `before`. */
unsigned edit_column(const u16 *before, unsigned n);

#endif
