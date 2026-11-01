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
    { "pmacro", "PilcrowMacro" }, { "jmacro", "PilcrowMacro" },
    { "ini", "INI" }, { "cfg", "INI" }, { "inf", "INI" },
    { "html", "HTML" }, { "htm", "HTML" }, { "xhtml", "HTML" }, { "shtml", "HTML" }, { "css", "CSS" },
    { "xml", "XML" }, { "xsl", "XML" }, { "xslt", "XML" }, { "xsd", "XML" }, { "svg", "XML" }, { "rss", "XML" }, { "atom", "XML" },
    { "wsdl", "XML" }, { "dtd", "XML" }, { "xbl", "XML" },
    { "s", "AsmX86" }, { "asm", "AsmX86" },                              /* the dialect is settled by looking at the text (lang_refine_mode) */
    { "md", "Markdown" }, { "markdown", "Markdown" }, { "mkd", "Markdown" }, { "mdown", "Markdown" },
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
    { ".gitconfig", "INI" }, { ".editorconfig", "INI" }, { ".zshrc", "Zsh" }, { ".zshenv", "Zsh" }, { ".zprofile", "Zsh" }, { ".zlogin", "Zsh" }, { ".zlogout", "Zsh" },
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

static int ci_prefix(const char *s, const char *prefix)
{
    for (; *prefix != '\0'; s++, prefix++) {
        int a = (unsigned char)*s, b = (unsigned char)*prefix;

        if (a >= 'A' && a <= 'Z') a += 32;
        if (a != b) return 0;
    }
    return 1;
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
    if (first_line != NULL && (strncmp(first_line, "# Pilcrow macro", 15) == 0 || strncmp(first_line, "# JOSE macro", 12) == 0)) return "PilcrowMacro";     /* JOSE was the name before Pilcrow */
    if (first_line != NULL && strncmp(first_line, "<?xml", 5) == 0) return "XML";
    if (first_line != NULL && (ci_prefix(first_line, "<!doctype html") || ci_prefix(first_line, "<html"))) return "HTML";
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
        { "PilcrowMacro", "#", "" }, { "JavaScript", "//", "" }, { "Ruby", "#", "" }, { "Zsh", "#", "" }, { "BSDMakefile", "#", "" }, { "Markdown", "<!--", "-->" }, { "HTML", "<!--", "-->" }, { "XML", "<!--", "-->" }, { "CSS", "/*", "*/" }, { "INI", ";", "" },
        { "AsmX86", "#", "" }, { "AsmM68k", "|", "" }, { "AsmSparc", "!", "" }, { "Imakefile", "XCOMM", "" },
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
        strcmp(mode, "ObjC++") == 0 || strcmp(mode, "CSS") == 0 || strcmp(mode, "Perl") == 0 || strcmp(mode, "Shell") == 0 || strcmp(mode, "Csh") == 0 ||
        strcmp(mode, "Zsh") == 0 || strcmp(mode, "JavaScript") == 0 || strcmp(mode, "JSON") == 0)
        return 'b';
    return 0;
}

int lang_c_like(const char *mode)
{
    if (mode == NULL) return 0;
    return strcmp(mode, "C") == 0 || strcmp(mode, "C-Header") == 0 || strcmp(mode, "C++") == 0 || strcmp(mode, "ObjC") == 0 ||
           strcmp(mode, "ObjC++") == 0 || strcmp(mode, "JavaScript") == 0 || strcmp(mode, "JSON") == 0 || strcmp(mode, "CSS") == 0;
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

/* ---- which assembler? ----
 * (Careful with names: NeXT's cc predefines `sparc`, `m68k` and `i386` as macros for the architecture it is building, so none of them
 * can be a variable name.) */

/* How often `word` occurs in t[0, n) with a non-identifier character on each side (or, with a leading '%' or '$', just after one). */
static int count_word(const char *t, size_t n, const char *word)
{
    size_t wl = strlen(word), i;
    int count = 0;

    for (i = 0; i + wl <= n; i++) {
        if (t[i] != word[0] || strncmp(t + i, word, wl) != 0) continue;
        if (word[0] != '%' && i > 0 && (isalnum((unsigned char)t[i - 1]) || t[i - 1] == '_' || t[i - 1] == '.')) continue;
        if (i + wl < n && (isalnum((unsigned char)t[i + wl]) || t[i + wl] == '_')) continue;
        count++;
    }
    return count;
}

const char *lang_sniff_asm(const char *text, size_t n)
{
    static const char *const x86_words[] = { "%eax", "%ebx", "%ecx", "%edx", "%esp", "%ebp", "%esi", "%edi", "%rax", "%rsp", "%rbp", "%xmm0",
                                       "movl", "pushl", "popl", "leal", "addl", "subl", "cmpl", "xorl", "movb", "movw", "testl", NULL };
    static const char *const sparc_words[] = { "%o0", "%o1", "%o2", "%o3", "%l0", "%l1", "%l2", "%i0", "%i1", "%i2", "%g0", "%g1", "%sp", "%fp",
                                         "%hi", "%lo", "sethi", "retl", "restore", "save", "ldd", "std", NULL };
    static const char *const m68k_words[] = { "d0", "d1", "d2", "d3", "a0", "a1", "a2", "a6", "a7", "sp", "moveq", "movel", "move.l", "movem.l",
                                        "movea.l", "link", "unlk", "rts", "jsr", "bsr", "dbra", "fp0", "fp1", NULL };
    int sx = 0, ss = 0, sm = 0, i;

    for (i = 0; x86_words[i]; i++) sx += count_word(text, n, x86_words[i]);
    for (i = 0; sparc_words[i]; i++) ss += count_word(text, n, sparc_words[i]);
    for (i = 0; m68k_words[i]; i++) sm += count_word(text, n, m68k_words[i]);
    if (sx < 2 && ss < 2 && sm < 2) return NULL;
    if (ss > sx && ss >= sm) return "AsmSparc";
    if (sm > sx && sm > ss) return "AsmM68k";
    return "AsmX86";
}

const char *lang_refine_mode(const char *mode, const char *text, size_t n)
{
    const char *better;

    if (mode == NULL || strncmp(mode, "Asm", 3) != 0) return mode;
    better = lang_sniff_asm(text, n);
    return better != NULL ? better : mode;
}
