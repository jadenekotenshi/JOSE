#ifndef FOLD_H
#define FOLD_H

/* Code folding.  A folded block is replaced in the text by a token, ` ... 12 lines ~7 `, which stands for the text it hides
 * (kept by the editor under number 7).  Because the token is ordinary text, undo, redo and the line numbers need no special
 * knowledge of folds beyond recognising it.  Plain C so that it can be tested on the host. */

#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;
#endif

#define FOLD_MAX_TOKEN 48              /* room that fold_make_token needs */

/* Writes the token for a block that hides `lines` line breaks, standing for number `id`; returns its length. */
unsigned fold_make_token(u16 *out, unsigned lines, unsigned id);

/* The first token that starts at `from` or later: its start and end (one past) in *start / *end, the line breaks it hides
 * and its number.  0 if there is none. */
int fold_token_find(const u16 *t, unsigned n, unsigned from, unsigned *start, unsigned *end, unsigned *lines, unsigned *id);

/* The line breaks hidden by the tokens that start before `limit` in t[0, n) (n may be a little past limit so that a token
 * that starts just before it is whole). */
unsigned fold_hidden_lines(const u16 *t, unsigned n, unsigned limit);

/* The block to fold for the insertion point at `pos`: the first `{` on its line whose `}` is on a later line, else the block
 * that the line's `}` closes, else the innermost block around `pos` that spans several lines.  *open and *close are the
 * indexes of the two braces.  Returns 0 if there is none. */
int fold_find_block(const u16 *t, unsigned n, unsigned pos, int c_aware, unsigned *open, unsigned *close);

/* Every outermost `{ ... }` that spans several lines, in order (malloc'd arrays of the brace indexes; free them).  Returns how
 * many. */
unsigned fold_top_blocks(const u16 *t, unsigned n, int c_aware, unsigned **opens, unsigned **closes);

#endif
