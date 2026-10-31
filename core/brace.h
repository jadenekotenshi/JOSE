#ifndef BRACE_H
#define BRACE_H

/* Finding the bracket that matches another: ( ) [ ] { }.  Plain C so that it can be tested on the host. */

#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;

#endif

/* Is `c` one of the six bracket characters? */
int brace_is_bracket(unsigned c);

/* For the bracket at index `pos`, finds the one that goes with it and returns 1 with its index in *match; 0 if `pos` is not a
 * bracket or it has no partner.  With c_aware, brackets inside strings, character constants and comments (C style) are not
 * counted.  A bracket that itself sits inside such a thing is matched by plain counting of its own kind. */
int brace_match(const u16 *t, unsigned len, unsigned pos, int c_aware, unsigned *match);

/* Looks through the whole text for a bracket without a partner.  Returns 0 if every bracket is paired; otherwise the first
 * problem found, reading from the top, with its index in *pos: BRACE_STRAY (a closing bracket with nothing open), BRACE_MISMATCH
 * (a closing bracket that does not fit the innermost open one, whose index goes in *opener) or BRACE_UNCLOSED (a bracket still
 * open at the end: the innermost one).  c_aware as for brace_match. */
#define BRACE_STRAY    1
#define BRACE_MISMATCH 2
#define BRACE_UNCLOSED 3
int brace_find_unbalanced(const u16 *t, unsigned len, int c_aware, unsigned *pos, unsigned *opener);

#endif
