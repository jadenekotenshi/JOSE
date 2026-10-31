#ifndef MACRO_H
#define MACRO_H

/* The macro language: one command per line.
 *
 *     insert "text"                     typed text (escapes: \\ \" \n \t \r \xHH)
 *     action moveWordForward:           a text-view action (a key such as an arrow, Delete, Return)
 *     command shift-right               a menu command, by name
 *     find fcrwp "pattern"              search: f or b (forward / backward), c case sensitive, r regular expression,
 *                                       w whole word, p wrap around
 *     replace fcr "pattern" "with"      replace the selection if it matches, else find the next
 *     replace-all fcr "pattern" "with"
 *     replace-sel fcr "pattern" "with"  replace all in the selection
 *     filter "sort -r"                  pass the selection through a command
 *     exec "date"                       insert a command's output
 *
 * Blank lines and lines starting with # are comments.  Plain C so that it can be tested on the host. */

enum {
    MOP_NONE = 0,        /* a blank line or a comment */
    MOP_INSERT, MOP_ACTION, MOP_COMMAND, MOP_FIND, MOP_REPLACE, MOP_REPLACE_ALL, MOP_REPLACE_SEL, MOP_FILTER, MOP_EXEC
};

typedef struct {
    int   kind;
    char  word[64];      /* the action, command or flags word */
    char *s1;            /* the first string (malloc'd), or NULL */
    char *s2;            /* the second string, or NULL */
} MacroOp;

/* Parses one line.  Returns 0 (op->kind may be MOP_NONE) or -1 with a message in err. */
int macro_parse_line(const char *line, MacroOp *op, char *err, unsigned errsize);
void macro_op_free(MacroOp *op);

/* The text of `s` as a quoted string for a macro line, escapes and all (malloc'd). */
char *macro_quote(const char *s);

#endif
