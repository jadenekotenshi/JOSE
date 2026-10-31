#include <string.h>
#include "includes.h"

static int is_blank(u16 c) { return c == ' ' || c == '\t' || c == '\r'; }

static unsigned skip_blanks(const u16 *t, unsigned n, unsigned i)
{
    while (i < n && is_blank(t[i])) i++;
    return i;
}

/* Does the word `w` start at t[i] and end there (a non-word character or the end follows)? */
static int word_at(const u16 *t, unsigned n, unsigned i, const char *w)
{
    unsigned k;

    for (k = 0; w[k]; k++) if (i + k >= n || t[i + k] != (u16)(unsigned char)w[k]) return 0;
    k = i + (unsigned)strlen(w);
    return k >= n || !((t[k] >= 'a' && t[k] <= 'z') || (t[k] >= 'A' && t[k] <= 'Z') || (t[k] >= '0' && t[k] <= '9') || t[k] == '_');
}

/* Copies t[a, b) as ASCII into out; 0 if it holds anything else or is too long. */
static unsigned copy_ascii(const u16 *t, unsigned a, unsigned b, char *out)
{
    unsigned i;

    if (b <= a || b - a >= INCLUDE_NAME_SIZE) return 0;
    for (i = a; i < b; i++) {
        if (t[i] < 32 || t[i] > 126) return 0;
        out[i - a] = (char)t[i];
    }
    out[b - a] = '\0';
    return b - a;
}

static unsigned add_name(char names[INCLUDE_MAX_NAMES][INCLUDE_NAME_SIZE], unsigned count, const char *s)
{
    if (count < INCLUDE_MAX_NAMES && strlen(s) < INCLUDE_NAME_SIZE) {
        strcpy(names[count], s);
        return count + 1;
    }
    return count;
}

/* "a.b.c" or "A::B" -> "a/b/c" + suffix */
static void dots_to_path(const char *dotted, const char *suffix, char *out)
{
    unsigned i, n = 0;

    for (i = 0; dotted[i] && n < INCLUDE_NAME_SIZE - 16; i++) {
        if (dotted[i] == ':' && dotted[i + 1] == ':') { out[n++] = '/'; i++; }
        else out[n++] = dotted[i] == '.' ? '/' : dotted[i];
    }
    out[n] = '\0';
    strcat(out, suffix);
}

/* The first quoted string of t[from, n): its contents are [*a, *b). */
static int first_quoted(const u16 *t, unsigned n, unsigned from, unsigned *a, unsigned *b)
{
    unsigned i, j;

    for (i = from; i < n; i++) {
        if (t[i] == '"' || t[i] == '\'') {
            for (j = i + 1; j < n && t[j] != t[i]; j++) ;
            if (j >= n) return 0;
            *a = i + 1;
            *b = j;
            return *b > *a;
        }
    }
    return 0;
}

static int has_suffix(const char *s, const char *suffix)
{
    size_t a = strlen(s), b = strlen(suffix);

    return a >= b && strcmp(s + a - b, suffix) == 0;
}

unsigned include_parse(const u16 *t, unsigned n, const char *mode, char names[INCLUDE_MAX_NAMES][INCLUDE_NAME_SIZE], int *system)
{
    unsigned i = skip_blanks(t, n, 0), j, count = 0;
    char buf[INCLUDE_NAME_SIZE];

    *system = 0;
    if (mode == NULL) return 0;
    if (strcmp(mode, "C") == 0 || strcmp(mode, "C-Header") == 0 || strcmp(mode, "C++") == 0 || strcmp(mode, "ObjC") == 0 ||
        strcmp(mode, "ObjC++") == 0 || strcmp(mode, "Imakefile") == 0) {
        if (i >= n || t[i] != '#') return 0;
        i = skip_blanks(t, n, i + 1);
        if (word_at(t, n, i, "include")) i += 7;
        else if (word_at(t, n, i, "import")) i += 6;
        else if (word_at(t, n, i, "include_next")) i += 12;
        else return 0;
        i = skip_blanks(t, n, i);
        if (i < n && (t[i] == '<' || t[i] == '"')) {
            u16 close = t[i] == '<' ? '>' : '"';
            *system = t[i] == '<';
            for (j = i + 1; j < n && t[j] != close; j++) ;
            if (j < n && copy_ascii(t, i + 1, j, buf)) return add_name(names, 0, buf);
        }
        return 0;
    }
    if (strcmp(mode, "Python") == 0) {
        if (word_at(t, n, i, "import")) {
            i = skip_blanks(t, n, i + 6);
            for (j = i; j < n && (t[j] == '_' || t[j] == '.' || (t[j] >= 'a' && t[j] <= 'z') || (t[j] >= 'A' && t[j] <= 'Z') || (t[j] >= '0' && t[j] <= '9')); j++) ;
            if (copy_ascii(t, i, j, buf)) {
                char p[INCLUDE_NAME_SIZE];
                dots_to_path(buf, ".py", p);
                count = add_name(names, count, p);
                dots_to_path(buf, "/__init__.py", p);
                count = add_name(names, count, p);
            }
            return count;
        }
        if (word_at(t, n, i, "from")) {
            char module[INCLUDE_NAME_SIZE];
            i = skip_blanks(t, n, i + 4);
            for (j = i; j < n && (t[j] == '_' || t[j] == '.' || (t[j] >= 'a' && t[j] <= 'z') || (t[j] >= 'A' && t[j] <= 'Z') || (t[j] >= '0' && t[j] <= '9')); j++) ;
            if (!copy_ascii(t, i, j, module)) return 0;
            {
                char p[INCLUDE_NAME_SIZE];
                dots_to_path(module, ".py", p);
                count = add_name(names, count, p);
                dots_to_path(module, "/__init__.py", p);
                count = add_name(names, count, p);
            }
            i = skip_blanks(t, n, j);
            if (word_at(t, n, i, "import")) {                       /* `from pkg import mod` may mean pkg/mod.py */
                i = skip_blanks(t, n, i + 6);
                for (j = i; j < n && (t[j] == '_' || (t[j] >= 'a' && t[j] <= 'z') || (t[j] >= 'A' && t[j] <= 'Z') || (t[j] >= '0' && t[j] <= '9')); j++) ;
                if (copy_ascii(t, i, j, buf)) {
                    char p[INCLUDE_NAME_SIZE];
                    strcat(module, ".");
                    strcat(module, buf);
                    dots_to_path(module, ".py", p);
                    count = add_name(names, count, p);
                }
            }
            return count;
        }
        return 0;
    }
    if (strcmp(mode, "BSDMakefile") == 0) {                        /* .include <bsd.prog.mk>   .include "local.mk" */
        if (i >= n || t[i] != '.') return 0;
        i = skip_blanks(t, n, i + 1);
        if (word_at(t, n, i, "include")) i += 7;
        else if (word_at(t, n, i, "sinclude")) i += 8;
        else if (word_at(t, n, i, "dinclude")) i += 8;
        else return 0;
        i = skip_blanks(t, n, i);
        if (i < n && (t[i] == '<' || t[i] == '"')) {
            u16 close = t[i] == '<' ? '>' : '"';
            *system = t[i] == '<';
            for (j = i + 1; j < n && t[j] != close; j++) ;
            if (j < n && copy_ascii(t, i + 1, j, buf)) return add_name(names, 0, buf);
        }
        return 0;
    }
    if (strcmp(mode, "Ruby") == 0) {                               /* require 'x'   require_relative "x"   load 'x' */
        unsigned a, b;
        int relative = 0;

        if (word_at(t, n, i, "require_relative")) { i += 16; relative = 1; }
        else if (word_at(t, n, i, "require")) i += 7;
        else if (word_at(t, n, i, "load")) i += 4;
        else return 0;
        if (!first_quoted(t, n, i, &a, &b) || !copy_ascii(t, a, b, buf)) return 0;
        *system = !relative && buf[0] != '.' && buf[0] != '/';
        if (!has_suffix(buf, ".rb")) {
            char p[INCLUDE_NAME_SIZE];
            if (strlen(buf) + 4 < INCLUDE_NAME_SIZE) { strcpy(p, buf); strcat(p, ".rb"); count = add_name(names, count, p); }
        }
        return add_name(names, count, buf);
    }
    if (strcmp(mode, "JavaScript") == 0) {                         /* require('x')   import a from 'x'   export * from 'x' */
        unsigned a, b, from;
        int found = 0;

        if (word_at(t, n, i, "import") || word_at(t, n, i, "export")) {
            /* the module is the string after `from`, or the first string of `import 'x'` */
            for (from = i; from + 4 <= n; from++)
                if (word_at(t, n, from, "from") && (from == 0 || !((t[from - 1] >= 'a' && t[from - 1] <= 'z') || (t[from - 1] >= 'A' && t[from - 1] <= 'Z') || t[from - 1] == '_'))) { found = 1; break; }
            if (found) found = first_quoted(t, n, from + 4, &a, &b);
            else found = first_quoted(t, n, i + 6, &a, &b);
        } else {
            for (from = i; from + 7 <= n; from++)
                if (word_at(t, n, from, "require")) { found = first_quoted(t, n, from + 7, &a, &b); break; }
        }
        if (!found || !copy_ascii(t, a, b, buf)) return 0;
        *system = buf[0] != '.' && buf[0] != '/';
        count = add_name(names, 0, buf);
        if (!has_suffix(buf, ".js") && !has_suffix(buf, ".json") && !has_suffix(buf, ".mjs")) {
            char p[INCLUDE_NAME_SIZE];
            if (strlen(buf) + 10 < INCLUDE_NAME_SIZE) {
                strcpy(p, buf); strcat(p, ".js"); count = add_name(names, count, p);
                strcpy(p, buf); strcat(p, "/index.js"); count = add_name(names, count, p);
            }
        }
        return count;
    }
    if (strcmp(mode, "Shell") == 0 || strcmp(mode, "Csh") == 0 || strcmp(mode, "Zsh") == 0) {
        if (word_at(t, n, i, "source")) i += 6;
        else if (i < n && t[i] == '.' && i + 1 < n && is_blank(t[i + 1])) i += 1;
        else return 0;
        i = skip_blanks(t, n, i);
        if (i < n && (t[i] == '"' || t[i] == '\'')) {
            u16 q = t[i];
            for (j = i + 1; j < n && t[j] != q; j++) ;
            return copy_ascii(t, i + 1, j, buf) ? add_name(names, 0, buf) : 0;
        }
        for (j = i; j < n && !is_blank(t[j]) && t[j] != ';' && t[j] != '#'; j++) ;
        return copy_ascii(t, i, j, buf) ? add_name(names, 0, buf) : 0;
    }
    if (strcmp(mode, "Perl") == 0) {
        if (word_at(t, n, i, "use") || word_at(t, n, i, "require")) {
            i = skip_blanks(t, n, i + (word_at(t, n, i, "use") ? 3 : 7));
            if (i < n && (t[i] == '"' || t[i] == '\'')) {
                u16 q = t[i];
                for (j = i + 1; j < n && t[j] != q; j++) ;
                return copy_ascii(t, i + 1, j, buf) ? add_name(names, 0, buf) : 0;
            }
            for (j = i; j < n && (t[j] == '_' || t[j] == ':' || (t[j] >= 'a' && t[j] <= 'z') || (t[j] >= 'A' && t[j] <= 'Z') || (t[j] >= '0' && t[j] <= '9')); j++) ;
            if (copy_ascii(t, i, j, buf) && strchr(buf, ':') == NULL && buf[0] >= 'a' && buf[0] <= 'z') return 0;       /* a pragma: use strict */
            if (copy_ascii(t, i, j, buf)) {
                char p[INCLUDE_NAME_SIZE];
                dots_to_path(buf, ".pm", p);
                return add_name(names, 0, p);
            }
        }
        return 0;
    }
    if (strcmp(mode, "GNUmakefile") == 0) {
        if (i < n && t[i] == '-') i++;
        if (!word_at(t, n, i, "include")) return 0;
        i = skip_blanks(t, n, i + 7);
        for (j = i; j < n && !is_blank(t[j]); j++) ;
        return copy_ascii(t, i, j, buf) ? add_name(names, 0, buf) : 0;
    }
    return 0;
}

unsigned include_token(const u16 *t, unsigned n, unsigned pos, char *out, unsigned cap)
{
    unsigned a = pos, b = pos;

#define TOKCH(c) (((c) >= 'a' && (c) <= 'z') || ((c) >= 'A' && (c) <= 'Z') || ((c) >= '0' && (c) <= '9') || (c) == '.' || (c) == '/' || (c) == '_' || (c) == '-' || (c) == '+' || (c) == '~')
    if (pos > n) pos = a = b = n;
    while (a > 0 && TOKCH(t[a - 1])) a--;
    while (b < n && TOKCH(t[b])) b++;
#undef TOKCH
    if (b <= a || b - a >= cap) return 0;
    {
        unsigned i;
        for (i = a; i < b; i++) out[i - a] = (char)t[i];
        out[b - a] = '\0';
    }
    return b - a;
}
