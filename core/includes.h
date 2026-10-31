#ifndef INCLUDES_H
#define INCLUDES_H

/* What file does a line of source refer to?  `#include <x.h>` and `#include "x.h"` (C family, also `#import`), Python's
 * `import a.b` and `from a.b import c`, shell's `. file` and `source file`, Perl's `use Foo::Bar;` and `require "x.pl"`, and
 * make's `include file`.  Plain C so that it can be tested on the host. */

#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;
#endif

#define INCLUDE_MAX_NAMES 4
#define INCLUDE_NAME_SIZE 256

/* The names that the line may stand for, best first, as paths relative to a search directory (Python's `a.b` becomes
 * `a/b.py`).  *system is set for `<...>` includes.  Returns how many names (0 if the line refers to nothing). */
unsigned include_parse(const u16 *line, unsigned n, const char *mode, char names[INCLUDE_MAX_NAMES][INCLUDE_NAME_SIZE], int *system);

/* A file name under the insertion point: the run of letters, digits and . / _ - + ~ around index `pos` of the line.  Returns
 * its length (0 if there is none). */
unsigned include_token(const u16 *line, unsigned n, unsigned pos, char *out, unsigned cap);

#endif
