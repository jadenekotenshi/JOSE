#ifndef SEARCH_H
#define SEARCH_H

/* Text search for the editor: literal or regular-expression patterns over UTF-16 text (NSString's unichar).  Plain C so that
 * it can be tested on the host; it does not depend on any system regex library (OPENSTEP 4.2 has no reliable one).
 *
 * Regular expressions are NEdit-flavoured: . [set] [^set] * + ? {n} {n,} {n,m} (lazy with a trailing ?), | ( ) (?: ),
 * ^ and $ at line boundaries, \< \> (word start/end), \b \B, \d \D \w \W \s \S, \n \t \r \f, \1..\9 back-references, and
 * a backslash before any other character takes it literally.  `.` does not match a newline; [^x] does.  Matching is by
 * backtracking with an explicit stack, so a long line cannot overflow the C stack. */

#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;
#endif

#define SEARCH_REGEX  1       /* the pattern is a regular expression (otherwise it is literal text) */
#define SEARCH_ICASE  2       /* ignore case (ASCII and Latin-1 letters) */
#define SEARCH_WORD   4       /* the match must be a whole word */

#define SEARCH_NGROUPS 10     /* groups 0 (the whole match) to 9 */
#define SEARCH_NONE ((unsigned)-1)

typedef struct Search Search;

typedef struct {
    unsigned start[SEARCH_NGROUPS];     /* SEARCH_NONE for a group that did not take part */
    unsigned end[SEARCH_NGROUPS];
} SearchMatch;

/* NULL (with a message in err) if the pattern is not valid. */
Search *search_new(const u16 *pat, unsigned npat, int flags, char *err, unsigned errsize);
void search_free(Search *s);

/* Looks for a match.  Forward: the first match that starts at `from` or later (when wrap is set, then one that starts
 * before `from`).  Backward: the last match that starts before `from` (then, with wrap, one at or after it).
 * Returns 1 and fills `m`, or 0. */
int search_find(Search *s, const u16 *text, unsigned len, unsigned from, int forward, int wrap, SearchMatch *m);

/* A match that starts exactly at `pos`. */
int search_match_at(Search *s, const u16 *text, unsigned len, unsigned pos, SearchMatch *m);

/* Builds the replacement text for a match into `out` (at most `cap` units) and returns how many units the whole
 * replacement needs, so a call with cap 0 sizes the buffer.  With `literal` the replacement is used as it stands;
 * otherwise \0..\9 insert the whole match or a group, \n and \t are a newline and a tab, and \\ is a backslash. */
unsigned search_expand(const SearchMatch *m, const u16 *text, const u16 *repl, unsigned nrepl, int literal,
                       u16 *out, unsigned cap);

/* Replaces every match inside [lo, hi) of `text`.  On success *out is a malloc'd copy of the text from the first match's
 * start to the last match's end, replaced, and *first / *last give the span of the original that it stands for (so a
 * caller can make that one edit); *count is the number of matches.  Returns 0 and leaves *out NULL when there is no
 * match. */
int search_replace_all(Search *s, const u16 *text, unsigned len, unsigned lo, unsigned hi, const u16 *repl, unsigned nrepl,
                       int literal, u16 **out, unsigned *outlen, unsigned *first, unsigned *last, unsigned *count);

#endif
