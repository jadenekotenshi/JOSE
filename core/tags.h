#ifndef TAGS_H
#define TAGS_H

/* Reading a ctags file: `name<TAB>file<TAB>address` lines, as written by the BSD/NeXT ctags and by Exuberant/Universal
 * ctags (whose lines go on with `;"<TAB>kind<TAB>field:value ...`).  The address is a line number or a search pattern between
 * slashes (or question marks).  Plain C so that it can be tested on the host. */

typedef struct {
    char *name;
    char *file;          /* as written in the tags file: relative to the folder that holds it */
    char *pattern;       /* the text of the line (without the ^ and $), or NULL if the address is a line number */
    int   line;          /* the line number if there is one, else 0 */
    char *kind;          /* a one-letter or word kind (f, function, ...), or NULL */
    char *signature;     /* "(int a, char *b)" from a signature: field, or NULL */
} Tag;

typedef struct Tags Tags;

/* NULL if the file cannot be read. */
Tags *tags_load(const char *path);
void tags_free(Tags *t);
unsigned tags_count(const Tags *t);

/* The tags named `name`: *first is the index of the first and the result is how many (they are kept together, in file order). */
unsigned tags_find(const Tags *t, const char *name, unsigned *first);
const Tag *tags_at(const Tags *t, unsigned i);

/* One line of text to show for a tag as a call tip: the declaration line from its pattern, else name + signature, trimmed
 * and cut to `cap` - 1 characters.  Returns the length. */
unsigned tags_tip(const Tag *tag, char *out, unsigned cap);

#endif
