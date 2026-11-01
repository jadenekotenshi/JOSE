#ifndef LANGMODES_H
#define LANGMODES_H

#include <stddef.h>

/* Which language mode (the base name of a .syntax file) a file should open in, from its name and first line.
 * Returns NULL for "plain text".  The name is a string constant; the caller does not free it. */
const char *lang_mode_for(const char *path, const char *first_line);

/* The display name of the mode for a file name alone ("Makefile" -> "GNUmakefile"), or NULL. */
const char *lang_mode_for_name(const char *base_name);

/* How a mode writes a comment: 1 and the opening text (and the closing text, "" for a comment that runs to the end of the
 * line) for modes that have one, else 0. */
int lang_comment_style(const char *mode, const char **open, const char **close);

/* How a new line is indented after a line that opens a block: 'b' (a line ending in a brace), 'c' (ending in a colon), or 0
 * (just copy the indentation). */
int lang_smart_indent(const char *mode);

/* 1 for the modes whose text is C-like (strings, character constants and C comments, for matching brackets). */
int lang_c_like(const char *mode);

/* Which keyword pairs a mode has, for matching and folding (the WORDS_ values of words.h): 1 shell, 2 csh, 3 the C
 * preprocessor (the C family, Imake), 4 Ruby's def/end; 0 none. */
int lang_word_kind(const char *mode);

/* Do `[ ]` blocks fold as well as `{ }` (JSON and JavaScript arrays)? */
int lang_fold_brackets(const char *mode);

/* How code folds in a mode: 'i' by indentation (Python), 'w' by keyword pairs (shell, csh), 'b' by braces. */
int lang_fold_style(const char *mode);

/* Assembly language comes in dialects with the same file names (.s, .S, .asm): the text decides.  Returns "AsmX86", "AsmM68k" or
 * "AsmSparc" if the registers and mnemonics in the text (give its first few thousand bytes) point clearly to one, else NULL. */
const char *lang_sniff_asm(const char *text, size_t n);

/* The mode to use for a file: `mode` as lang_mode_for gave it, except that an assembly mode becomes the dialect the text shows. */
const char *lang_refine_mode(const char *mode, const char *text, size_t n);

#endif
