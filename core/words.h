#ifndef WORDS_H
#define WORDS_H

/* Block keywords that go in pairs, for matching and folding: shell `if`/`fi`, `case`/`esac`, `while`/`for`/`until`/`select` and
 * `done` (with `then`, `elif`, `else` and `do` in between); csh `if (...) then`/`endif`, `foreach`/`while`/`end`,
 * `switch`/`endsw`; Ruby `def`/`class`/`module`/`if`/`do`... with `end`; and the C preprocessor `#if`, `#ifdef`, `#ifndef` and `#endif` (with `#else`, `#elif`).  A word only counts
 * where a command could start (after a newline, `;`, `|`, `&`, `(`, `{`, or a keyword like `then`), so `echo if` is left
 * alone, and comments and quoted text are skipped.  Plain C so that it can be tested on the host. */

#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;
#endif

#define WORDS_NONE 0
#define WORDS_SH   1
#define WORDS_CSH  2
#define WORDS_CPP  3
#define WORDS_RUBY 4

typedef struct { unsigned os, oe, cs, ce; } WordPair;        /* the opening and closing words: [os, oe) and [cs, ce) */
typedef struct { unsigned s, e; unsigned pair; } WordMid;    /* `else` and its like, and the pair that they belong to */

/* A block word with no partner: an opener never closed, a closer with nothing open, or an `else` and its like outside a block. */
#define WORD_LONE_OPEN  1
#define WORD_LONE_CLOSE 2
#define WORD_LONE_MID   3
typedef struct { unsigned s, e; int type; } WordLone;

typedef struct {
    WordLone *lone;
    unsigned nlone;
    WordPair *pairs;
    unsigned npairs;
    WordMid *mids;
    unsigned nmids;
} WordBlocks;

/* Finds all the pairs in t[0, n) (which may hold fold markers, which count as the end of a command).  Returns 1 on success. */
int words_scan(const u16 *t, unsigned n, int kind, WordBlocks *out);
void words_free(WordBlocks *b);

/* The block word that `pos` is in or touches: ws and we are its extent, ms and me the extent of the word that goes with it (for an
 * `else`, the closing word).  Returns 0 if there is none. */
int words_match(const WordBlocks *b, unsigned pos, unsigned *ws, unsigned *we, unsigned *ms, unsigned *me);

/* Folding: the text to hide for the block at `pos` as [*hs, *he) -- from the end of the opening word's line to the start of
 * the closing word -- for the block that opens on pos's line, else the one that closes on it, else the innermost around it.
 * Only blocks that span several lines.  Returns 0 if there is none. */
int words_fold_block(const WordBlocks *b, const u16 *t, unsigned n, unsigned pos, unsigned *hs, unsigned *he);

/* The outermost multi-line blocks, as ranges to hide (malloc'd arrays; free them).  Returns how many. */
unsigned words_fold_top(const WordBlocks *b, const u16 *t, unsigned n, unsigned **hs, unsigned **he);

#endif
