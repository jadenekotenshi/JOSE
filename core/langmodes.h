#ifndef LANGMODES_H
#define LANGMODES_H

/* Which language mode (the base name of a .syntax file) a file should open in, from its name and first line.
 * Returns NULL for "plain text".  The name is a string constant; the caller does not free it. */
const char *lang_mode_for(const char *path, const char *first_line);

/* The display name of the mode for a file name alone ("Makefile" -> "GNUmakefile"), or NULL. */
const char *lang_mode_for_name(const char *base_name);

#endif
