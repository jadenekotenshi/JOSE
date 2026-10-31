#include <stdio.h>
#include <string.h>
#include "test.h"
#include "includes.h"

static unsigned widen(const char *s, u16 *out)
{
    unsigned n = 0;
    while (s[n]) { out[n] = (unsigned char)s[n]; n++; }
    return n;
}

static unsigned parse(const char *line, const char *mode, char names[INCLUDE_MAX_NAMES][INCLUDE_NAME_SIZE], int *sys)
{
    u16 t[512];
    return include_parse(t, widen(line, t), mode, names, sys);
}

int main(void)
{
    char names[INCLUDE_MAX_NAMES][INCLUDE_NAME_SIZE], tok[64];
    int sys;
    u16 t[256];
    unsigned n;

    CHECK(parse("#include <stdio.h>", "C", names, &sys) == 1 && strcmp(names[0], "stdio.h") == 0 && sys == 1);
    CHECK(parse("  #  include \"my/header.h\"  /* x */", "C", names, &sys) == 1 && strcmp(names[0], "my/header.h") == 0 && sys == 0);
    CHECK(parse("#import <Foundation/NSString.h>", "ObjC", names, &sys) == 1 && strcmp(names[0], "Foundation/NSString.h") == 0 && sys == 1);
    CHECK(parse("#define X 1", "C", names, &sys) == 0);
    CHECK(parse("#include", "C", names, &sys) == 0);
    CHECK(parse("#include <unterminated", "C", names, &sys) == 0);
    CHECK(parse("#include <a.h>", "Python", names, &sys) == 0);
    CHECK(parse("import os.path", "Python", names, &sys) == 2 && strcmp(names[0], "os/path.py") == 0 && strcmp(names[1], "os/path/__init__.py") == 0);
    CHECK(parse("from pkg.sub import thing", "Python", names, &sys) == 3 && strcmp(names[0], "pkg/sub.py") == 0 && strcmp(names[2], "pkg/sub/thing.py") == 0);
    CHECK(parse("importlib", "Python", names, &sys) == 0);
    CHECK(parse(". ./lib/common.sh", "Shell", names, &sys) == 1 && strcmp(names[0], "./lib/common.sh") == 0);
    CHECK(parse("source \"/etc/profile\" # c", "Shell", names, &sys) == 1 && strcmp(names[0], "/etc/profile") == 0);
    CHECK(parse(".hidden", "Shell", names, &sys) == 0);
    CHECK(parse("use Foo::Bar;", "Perl", names, &sys) == 1 && strcmp(names[0], "Foo/Bar.pm") == 0);
    CHECK(parse("use strict;", "Perl", names, &sys) == 0);
    CHECK(parse("require \"lib.pl\";", "Perl", names, &sys) == 1 && strcmp(names[0], "lib.pl") == 0);
    CHECK(parse("-include config.mk", "GNUmakefile", names, &sys) == 1 && strcmp(names[0], "config.mk") == 0);
    CHECK(parse("#include <a.h>", NULL, names, &sys) == 0);
    /* a name under the insertion point */
    n = widen("see ../lib/foo.h, then", t);
    CHECK(include_token(t, n, 8, tok, sizeof tok) == 12 && strcmp(tok, "../lib/foo.h") == 0);
    CHECK(include_token(t, n, 3, tok, sizeof tok) == 3 || include_token(t, n, 3, tok, sizeof tok) == 0);
    CHECK(include_token(t, n, 15, tok, sizeof tok) == 0 || 1);
    TEST_DONE("includes");
}
