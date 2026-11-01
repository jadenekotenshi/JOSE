#ifndef COMPLETE_H
#define COMPLETE_H

/* Word completion: the words that could finish the identifier before the insertion point, from the text itself (nearest first, as
 * in Emacs' dynamic abbreviations), from other texts, and from the keyword list of a language mode.  Plain C so that it can be
 * tested on the host. */

#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;
#endif

typedef struct {
    u16     *w;
    unsigned len;
} CompWord;

typedef struct {
    CompWord *v;
    unsigned  n, cap;
    int       icase;               /* ignore case when matching the prefix */
} CompList;

void comp_init(CompList *l, int icase);
void comp_free(CompList *l);

/* Is c a character of an identifier (letters, digits, underscore, and anything outside ASCII)? */
int comp_is_ident(unsigned c);

/* How many identifier characters end at `pos` (0 if none, or if they are only digits). */
unsigned comp_prefix_len(const u16 *t, unsigned n, unsigned pos);

/* Adds one word if it starts with the prefix, is longer than it, and is not in the list already.  Returns 1 if added. */
int comp_add_word(CompList *l, const u16 *prefix, unsigned plen, const u16 *w, unsigned wlen, unsigned max_total);

/* The words of t that start with the prefix t[start, pos), nearest first: backwards from `start`, then forwards from the end of the
 * identifier that holds `pos`.  Returns how many were added. */
unsigned comp_add_text_words(CompList *l, const u16 *t, unsigned n, unsigned start, unsigned pos, unsigned max_total);

/* The words of another text that start with the prefix, in order of appearance. */
unsigned comp_add_words_of(CompList *l, const u16 *t, unsigned n, const u16 *prefix, unsigned plen, unsigned max_total);

/* The keywords of a syntax file: every `Pattern = "<word>";` -- those that start with the prefix. */
unsigned comp_add_syntax_keywords(CompList *l, const char *syntax, const u16 *prefix, unsigned plen, unsigned max_total);

#endif
