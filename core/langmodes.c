#include <string.h>
#include <ctype.h>
#include "langmodes.h"

typedef struct { const char *ext; const char *mode; } ExtMode;
typedef struct { const char *name; const char *mode; } NameMode;

static const ExtMode EXTS[] = {
    { "c", "C" }, { "h", "C-Header" },
    { "cc", "C++" }, { "cpp", "C++" }, { "cxx", "C++" }, { "c++", "C++" }, { "hpp", "C++" }, { "hxx", "C++" }, { "hh", "C++" },
    { "m", "ObjC" }, { "mm", "ObjC++" },
    { "plist", "Plist" }, { "strings", "Strings" },
    { "gsmarkup", "GSmarkup" },
    { "mk", "GNUmakefile" },
    { NULL, NULL }
};

static const NameMode NAMES[] = {
    { "ChangeLog", "ChangeLog" }, { "Changelog", "ChangeLog" },
    { "Makefile", "GNUmakefile" }, { "makefile", "GNUmakefile" }, { "GNUmakefile", "GNUmakefile" },
    { "Makefile.openstep", "GNUmakefile" }, { "Makefile.preamble", "GNUmakefile" }, { "Makefile.postamble", "GNUmakefile" },
    { NULL, NULL }
};

static int ci_equal(const char *a, const char *b)
{
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return 0;
        a++; b++;
    }
    return *a == *b;
}

const char *lang_mode_for_name(const char *base)
{
    int i;
    const char *dot;

    if (base == NULL) return NULL;
    for (i = 0; NAMES[i].name; i++)
        if (strcmp(base, NAMES[i].name) == 0) return NAMES[i].mode;
    dot = strrchr(base, '.');
    if (dot != NULL && dot != base && dot[1] != '\0') {
        for (i = 0; EXTS[i].ext; i++)
            if (ci_equal(dot + 1, EXTS[i].ext)) return EXTS[i].mode;
    }
    return NULL;
}

const char *lang_mode_for(const char *path, const char *first_line)
{
    const char *base = path != NULL ? strrchr(path, '/') : NULL;
    const char *mode;

    base = base != NULL ? base + 1 : path;
    mode = lang_mode_for_name(base);
    if (mode != NULL) return mode;
    if (first_line != NULL && first_line[0] == '#' && first_line[1] == '!') {
        /* No shell or script modes yet: nothing to choose.  (Here is where #!/bin/sh would map.) */
        return NULL;
    }
    return NULL;
}
