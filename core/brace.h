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

/* Looks through the whole text for brackets without a partner and returns them, in order of position, as a malloc'd array
 * (free it); the result is the number of problems, 0 if every bracket is paired.  BRACE_STRAY: a closing bracket with nothing
 * open.  BRACE_MISMATCH: a closing bracket that fits no bracket still open (`other` is the innermost open one, which is taken to
 * be what it was meant to close).  BRACE_UNCLOSED: a bracket that is never closed -- also those skipped over when a closing
 * bracket matches one further out, which is where a closing bracket is missing.  c_aware as for brace_match. */
#define BRACE_STRAY    1
#define BRACE_MISMATCH 2
#define BRACE_UNCLOSED 3
typedef struct { unsigned pos; int kind; unsigned other; } BraceProblem;
unsigned brace_scan_problems(const u16 *t, unsigned len, int c_aware, BraceProblem **out);


#endif
