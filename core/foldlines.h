#ifndef FOLDLINES_H
#define FOLDLINES_H

/* Which lines can be folded, for the fold margin: one pass over the text that lists the lines where a multi-line block
 * begins (braces, indentation or keyword pairs, as the mode folds) and the lines that hold a fold marker.  Plain C so that
 * it can be tested on the host. */

#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;
#endif

typedef struct {
    unsigned *start;          /* the index of the first character of each such line, ascending */
    unsigned char *collapsed; /* 1 if the line holds a fold marker, 0 if a block begins there */
    unsigned count;
} FoldLines;

/* style: 'b' braces, 'i' indentation, 'w' keyword pairs (word_kind is the WORDS_ value for the mode).  Returns 1 on success
 * (even if there are no lines). */
int foldlines_scan(const u16 *t, unsigned n, int style, int c_aware, int word_kind, FoldLines *out);
void foldlines_free(FoldLines *f);

/* The entry for the line that starts at `line_start`: 0 none, 1 a block begins there, 2 a marker is there. */
int foldlines_state(const FoldLines *f, unsigned line_start);

#endif
