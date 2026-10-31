#ifndef GREP_H
#define GREP_H

/* Searching and replacing across files: file-name patterns, listing the lines of a text that match, replacing in a whole text
 * and deciding whether a file is one to touch.  Plain C over the UTF-16 search engine, tested on the host; the folder walking
 * and the panel are in app/FilesController. */

#include "search.h"

/* Does `name` match one of the patterns?  Patterns are separated by spaces or commas; * matches any run of characters
 * (including none) and ? any one; the rest is literal, and case counts.  No patterns at all match every name. */
int glob_match_any(const char *patterns, const char *name);

typedef struct {
    unsigned line;                     /* 1-based */
    unsigned lstart, lend;             /* the line's text [lstart, lend), without its newline */
    unsigned mstart;                   /* where the first match on it starts */
} GrepHit;

typedef struct {
    GrepHit *hit;
    unsigned n, cap;
} GrepHits;

void grep_free(GrepHits *h);
/* The lines of `text` that hold a match (one hit per line, in order), at most `max` of them.  Returns how many were added. */
unsigned grep_text(Search *s, const u16 *text, unsigned len, GrepHits *out, unsigned max);

/* Replaces every match in the text.  On success returns the number of matches (more than 0) and *out is a malloc'd copy of
 * the whole text, replaced; with no match it returns 0 and *out is NULL. */
unsigned grep_replace(Search *s, const u16 *text, unsigned len, const u16 *repl, unsigned nrepl, int literal,
                      u16 **out, unsigned *outlen);

/* A file's bytes: 1 if they are text we may rewrite (no NUL, valid UTF-8 -- plain ASCII included), 0 if not. */
int grep_bytes_are_text(const unsigned char *b, unsigned n);

#endif
