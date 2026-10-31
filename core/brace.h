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

#endif
