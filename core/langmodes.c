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
    { "py", "Python" }, { "pyw", "Python" },
    { "sh", "Shell" }, { "ksh", "Shell" }, { "bash", "Shell" },
    { "csh", "Csh" }, { "tcsh", "Csh" },
    { "pl", "Perl" }, { "pm", "Perl" }, { "pod", "Perl" },
    { "json", "JSON" }, { "js", "JavaScript" }, { "mjs", "JavaScript" }, { "cjs", "JavaScript" },
    { "rb", "Ruby" }, { "rake", "Ruby" }, { "gemspec", "Ruby" }, { "ru", "Ruby" },
    { "zsh", "Zsh" },
    { "jmacro", "JOSEMacro" },
    { "tmpl", "Imakefile" }, { "rules", "Imakefile" },
    { NULL, NULL }
};

static const NameMode NAMES[] = {
    { "ChangeLog", "ChangeLog" }, { "Changelog", "ChangeLog" },
    { "Makefile", "BSDMakefile" }, { "makefile", "BSDMakefile" }, { "GNUmakefile", "GNUmakefile" },
    { ".profile", "Shell" }, { ".kshrc", "Shell" }, { ".bashrc", "Shell" }, { ".bash_profile", "Shell" }, { ".xinitrc", "Shell" },
    { ".cshrc", "Csh" }, { ".tcshrc", "Csh" }, { ".login", "Csh" }, { ".logout", "Csh" },
    { "Imakefile", "Imakefile" }, { "BSDmakefile", "BSDMakefile" },
    { "Rakefile", "Ruby" }, { "Gemfile", "Ruby" }, { "Guardfile", "Ruby" }, { "Capfile", "Ruby" }, { "Vagrantfile", "Ruby" },
    { ".zshrc", "Zsh" }, { ".zshenv", "Zsh" }, { ".zprofile", "Zsh" }, { ".zlogin", "Zsh" }, { ".zlogout", "Zsh" },
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
    if (strncmp(base, "bsd.", 4) == 0 && strlen(base) > 7 && strcmp(base + strlen(base) - 3, ".mk") == 0) return "BSDMakefile";
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
    if (first_line != NULL && strncmp(first_line, "# JOSE macro", 12) == 0) return "JOSEMacro";
    if (first_line != NULL && first_line[0] == '#' && first_line[1] == '!') {
        if (strstr(first_line, "python") != NULL) return "Python";
        if (strstr(first_line, "perl") != NULL) return "Perl";
        if (strstr(first_line, "ruby") != NULL) return "Ruby";
        if (strstr(first_line, "node") != NULL) return "JavaScript";
        if (strstr(first_line, "zsh") != NULL) return "Zsh";           /* before the "sh" test */
        if (strstr(first_line, "csh") != NULL) return "Csh";            /* csh and tcsh, before the "sh" test */
        if (strstr(first_line, "sh") != NULL) return "Shell";           /* sh, ksh, bash, zsh */
        return NULL;
    }
    return NULL;
}

int lang_comment_style(const char *mode, const char **open, const char **close)
{
    static const struct { const char *mode; const char *open; const char *close; } T[] = {
        { "C", "/*", "*/" }, { "C-Header", "/*", "*/" }, { "ObjC", "/*", "*/" },
        { "C++", "//", "" }, { "ObjC++", "//", "" },
        { "JOSEMacro", "#", "" }, { "JavaScript", "//", "" }, { "Ruby", "#", "" }, { "Zsh", "#", "" }, { "BSDMakefile", "#", "" }, { "Imakefile", "XCOMM", "" },
        { "Python", "#", "" }, { "Shell", "#", "" }, { "Csh", "#", "" }, { "Perl", "#", "" }, { "GNUmakefile", "#", "" },
        { "Plist", "/*", "*/" }, { "Strings", "/*", "*/" }, { "GSmarkup", "<!--", "-->" },
        { NULL, NULL, NULL }
    };
    int i;

    if (mode == NULL) return 0;
    for (i = 0; T[i].mode; i++)
        if (strcmp(mode, T[i].mode) == 0) { *open = T[i].open; *close = T[i].close; return 1; }
    return 0;
}

int lang_smart_indent(const char *mode)
{
    if (mode == NULL) return 0;
    if (strcmp(mode, "Python") == 0) return 'c';
    if (strcmp(mode, "C") == 0 || strcmp(mode, "C-Header") == 0 || strcmp(mode, "C++") == 0 || strcmp(mode, "ObjC") == 0 ||
        strcmp(mode, "ObjC++") == 0 || strcmp(mode, "Perl") == 0 || strcmp(mode, "Shell") == 0 || strcmp(mode, "Csh") == 0 ||
        strcmp(mode, "Zsh") == 0 || strcmp(mode, "JavaScript") == 0 || strcmp(mode, "JSON") == 0)
        return 'b';
    return 0;
}

int lang_c_like(const char *mode)
{
    if (mode == NULL) return 0;
    return strcmp(mode, "C") == 0 || strcmp(mode, "C-Header") == 0 || strcmp(mode, "C++") == 0 || strcmp(mode, "ObjC") == 0 ||
           strcmp(mode, "ObjC++") == 0 || strcmp(mode, "JavaScript") == 0 || strcmp(mode, "JSON") == 0;
}

int lang_word_kind(const char *mode)
{
    if (mode == NULL) return 0;
    if (strcmp(mode, "Shell") == 0 || strcmp(mode, "Zsh") == 0) return 1;
    if (strcmp(mode, "Csh") == 0) return 2;
    if (strcmp(mode, "Ruby") == 0) return 4;
    if (strcmp(mode, "C") == 0 || strcmp(mode, "C-Header") == 0 || strcmp(mode, "C++") == 0 || strcmp(mode, "ObjC") == 0 ||
        strcmp(mode, "ObjC++") == 0 || strcmp(mode, "Imakefile") == 0)
        return 3;
    return 0;
}

int lang_fold_style(const char *mode)
{
    if (mode == NULL) return 'b';
    if (strcmp(mode, "Python") == 0) return 'i';
    if (strcmp(mode, "Shell") == 0 || strcmp(mode, "Csh") == 0 || strcmp(mode, "Zsh") == 0 || strcmp(mode, "Ruby") == 0) return 'w';
    return 'b';
}

int lang_fold_brackets(const char *mode)
{
    return mode != NULL && (strcmp(mode, "JSON") == 0 || strcmp(mode, "JavaScript") == 0);
}
