#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "macro.h"

static void fail(char *err, unsigned size, const char *msg)
{
    if (err != NULL && size > 0) {
        strncpy(err, msg, size - 1);
        err[size - 1] = '\0';
    }
}

static int is_blank(char c) { return c == ' ' || c == '\t' || c == '\r'; }
static int is_word_char(char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == ':' || c == '-' || c == '.';
}

static int hexval(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* A quoted string at *p (which points at the opening quote).  Leaves *p after the closing quote.  NULL on a bad string. */
static char *read_string(const char **p, char *err, unsigned errsize)
{
    const char *s = *p + 1;
    char *out = (char *)malloc(strlen(s) + 1);
    unsigned n = 0;

    if (out == NULL) { fail(err, errsize, "out of memory"); return NULL; }
    while (*s && *s != '"') {
        if (*s == '\\') {
            s++;
            switch (*s) {
            case 'n': out[n++] = '\n'; break;
            case 't': out[n++] = '\t'; break;
            case 'r': out[n++] = '\r'; break;
            case '\\': out[n++] = '\\'; break;
            case '"': out[n++] = '"'; break;
            case 'x':
                if (hexval(s[1]) >= 0 && hexval(s[2]) >= 0) {
                    out[n++] = (char)(hexval(s[1]) * 16 + hexval(s[2]));
                    s += 2;
                    break;
                }
                /* fall through */
            default:
                free(out);
                fail(err, errsize, "bad escape in a string");
                return NULL;
            }
            s++;
        } else {
            out[n++] = *s++;
        }
    }
    if (*s != '"') { free(out); fail(err, errsize, "a string is not closed"); return NULL; }
    out[n] = '\0';
    *p = s + 1;
    return out;
}

void macro_op_free(MacroOp *op)
{
    free(op->s1);
    free(op->s2);
    op->s1 = op->s2 = NULL;
}

int macro_parse_line(const char *line, MacroOp *op, char *err, unsigned errsize)
{
    const char *p = line;
    char verb[24];
    unsigned n = 0;
    int kind, want_word = 0, want_strings = 0;

    memset(op, 0, sizeof *op);
    while (is_blank(*p)) p++;
    if (*p == '\0' || *p == '\n' || *p == '#') return 0;
    while (is_word_char(*p) && n < sizeof verb - 1) verb[n++] = *p++;
    verb[n] = '\0';
    if (n == 0 || (*p != '\0' && !is_blank(*p) && *p != '\n')) { fail(err, errsize, "a command is expected"); return -1; }
    if (strcmp(verb, "insert") == 0) { kind = MOP_INSERT; want_strings = 1; }
    else if (strcmp(verb, "action") == 0) { kind = MOP_ACTION; want_word = 1; }
    else if (strcmp(verb, "command") == 0) { kind = MOP_COMMAND; want_word = 1; }
    else if (strcmp(verb, "find") == 0) { kind = MOP_FIND; want_word = 1; want_strings = 1; }
    else if (strcmp(verb, "replace") == 0) { kind = MOP_REPLACE; want_word = 1; want_strings = 2; }
    else if (strcmp(verb, "replace-all") == 0) { kind = MOP_REPLACE_ALL; want_word = 1; want_strings = 2; }
    else if (strcmp(verb, "replace-sel") == 0) { kind = MOP_REPLACE_SEL; want_word = 1; want_strings = 2; }
    else if (strcmp(verb, "filter") == 0) { kind = MOP_FILTER; want_strings = 1; }
    else if (strcmp(verb, "exec") == 0) { kind = MOP_EXEC; want_strings = 1; }
    else { fail(err, errsize, "unknown command"); return -1; }
    op->kind = kind;
    while (is_blank(*p)) p++;
    if (want_word) {
        n = 0;
        while (is_word_char(*p) && n < sizeof op->word - 1) op->word[n++] = *p++;
        op->word[n] = '\0';
        if (n == 0) { fail(err, errsize, "a word is expected"); op->kind = MOP_NONE; return -1; }
        while (is_blank(*p)) p++;
    }
    if (want_strings >= 1) {
        if (*p != '"') { fail(err, errsize, "a quoted string is expected"); op->kind = MOP_NONE; return -1; }
        op->s1 = read_string(&p, err, errsize);
        if (op->s1 == NULL) { op->kind = MOP_NONE; return -1; }
        while (is_blank(*p)) p++;
    }
    if (want_strings >= 2) {
        if (*p != '"') { fail(err, errsize, "a second quoted string is expected"); macro_op_free(op); op->kind = MOP_NONE; return -1; }
        op->s2 = read_string(&p, err, errsize);
        if (op->s2 == NULL) { macro_op_free(op); op->kind = MOP_NONE; return -1; }
        while (is_blank(*p)) p++;
    }
    if (*p != '\0' && *p != '\n' && *p != '#') {
        macro_op_free(op);
        op->kind = MOP_NONE;
        fail(err, errsize, "something is left over at the end of the line");
        return -1;
    }
    return 0;
}

char *macro_quote(const char *s)
{
    size_t n = strlen(s);
    char *out = (char *)malloc(n * 4 + 3);
    char *o = out;

    if (out == NULL) return NULL;
    *o++ = '"';
    for (; *s; s++) {
        unsigned char c = (unsigned char)*s;
        if (c == '\\' || c == '"') { *o++ = '\\'; *o++ = (char)c; }
        else if (c == '\n') { *o++ = '\\'; *o++ = 'n'; }
        else if (c == '\t') { *o++ = '\\'; *o++ = 't'; }
        else if (c == '\r') { *o++ = '\\'; *o++ = 'r'; }
        else if (c < 0x20 || c == 0x7f) { sprintf(o, "\\x%02x", c); o += 4; }
        else *o++ = (char)c;
    }
    *o++ = '"';
    *o = '\0';
    return out;
}
