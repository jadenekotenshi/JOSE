#include <stdlib.h>
#include "brace.h"

int brace_is_bracket(unsigned c)
{
    return c == '(' || c == ')' || c == '[' || c == ']' || c == '{' || c == '}';
}

static int is_open(unsigned c) { return c == '(' || c == '[' || c == '{'; }

static unsigned partner(unsigned c)
{
    switch (c) {
    case '(': return ')';
    case ')': return '(';
    case '[': return ']';
    case ']': return '[';
    case '{': return '}';
    default: return '{';
    }
}

/* Plain counting of one kind of bracket, forwards or backwards. */
static int plain_match(const u16 *t, unsigned len, unsigned pos, unsigned *match)
{
    unsigned c = t[pos], p = partner(c), i;
    long depth = 0;

    if (is_open(c)) {
        for (i = pos; i < len; i++) {
            if (t[i] == c) depth++;
            else if (t[i] == p && --depth == 0) { *match = i; return 1; }
        }
    } else {
        for (i = pos + 1; i > 0; i--) {
            if (t[i - 1] == c) depth++;
            else if (t[i - 1] == p && --depth == 0) { *match = i - 1; return 1; }
        }
    }
    return 0;
}

enum { S_CODE, S_LINE, S_BLOCK, S_STR, S_CHR };

int brace_match(const u16 *t, unsigned len, unsigned pos, int c_aware, unsigned *match)
{
    unsigned *stack = NULL, cap = 0, top = 0, i, c;
    int state = S_CODE, pos_in_code = 0, found = 0;
    unsigned target = 0;                       /* the stack depth just after the opening bracket at pos was pushed */

    if (pos >= len || !brace_is_bracket(t[pos])) return 0;
    if (!c_aware) return plain_match(t, len, pos, match);
    for (i = 0; i < len; i++) {
        c = t[i];
        if (state == S_LINE) {
            if (c == '\n') state = S_CODE;
        } else if (state == S_BLOCK) {
            if (c == '*' && i + 1 < len && t[i + 1] == '/') { state = S_CODE; i++; }
        } else if (state == S_STR || state == S_CHR) {
            if (c == '\\') i++;
            else if (c == '\n' || (state == S_STR && c == '"') || (state == S_CHR && c == '\'')) state = S_CODE;
        } else if (c == '/' && i + 1 < len && t[i + 1] == '/') { state = S_LINE; i++; }
        else if (c == '/' && i + 1 < len && t[i + 1] == '*') { state = S_BLOCK; i++; }
        else if (c == '"') state = S_STR;
        else if (c == '\'') state = S_CHR;
        else if (is_open(c)) {
            if (top == cap) {
                unsigned nc = cap ? cap * 2 : 64;
                unsigned *ns = (unsigned *)realloc(stack, nc * sizeof(unsigned));
                if (ns == NULL) { free(stack); return 0; }
                stack = ns;
                cap = nc;
            }
            stack[top++] = i;
            if (i == pos) { target = top; pos_in_code = 1; }
        } else if (brace_is_bracket(c)) {
            if (i == pos) pos_in_code = 1;
            if (top > 0 && partner(c) == t[stack[top - 1]]) {
                unsigned opener = stack[--top];
                if (i == pos) { *match = opener; found = 1; break; }
                if (target != 0 && top + 1 == target) { *match = i; found = 1; break; }
            }
        }
        if (i >= pos && !pos_in_code) break;           /* went past the bracket without it being code */
    }
    free(stack);
    if (found) return 1;
    if (!pos_in_code) return plain_match(t, len, pos, match);
    return 0;
}

static int problem_add(BraceProblem **v, unsigned *n, unsigned *cap, unsigned pos, int kind, unsigned other)
{
    if (*n == *cap) {
        unsigned nc = *cap ? *cap * 2 : 16;
        BraceProblem *nv = (BraceProblem *)realloc(*v, nc * sizeof(BraceProblem));

        if (nv == NULL) return 0;
        *v = nv;
        *cap = nc;
    }
    (*v)[*n].pos = pos;
    (*v)[*n].kind = kind;
    (*v)[*n].other = other;
    (*n)++;
    return 1;
}

static int problem_cmp(const void *a, const void *b)
{
    unsigned x = ((const BraceProblem *)a)->pos, y = ((const BraceProblem *)b)->pos;

    return x < y ? -1 : (x > y ? 1 : 0);
}

unsigned brace_scan_problems(const u16 *t, unsigned len, int c_aware, BraceProblem **out)
{
    unsigned *stack = NULL, cap = 0, top = 0, i, c, np = 0, pcap = 0;
    int state = S_CODE, ok = 1;

    *out = NULL;
    for (i = 0; i < len && ok; i++) {
        c = t[i];
        if (c_aware && state == S_LINE) {
            if (c == '\n') state = S_CODE;
        } else if (c_aware && state == S_BLOCK) {
            if (c == '*' && i + 1 < len && t[i + 1] == '/') { state = S_CODE; i++; }
        } else if (c_aware && (state == S_STR || state == S_CHR)) {
            if (c == '\\') i++;
            else if (c == '\n' || (state == S_STR && c == '"') || (state == S_CHR && c == '\'')) state = S_CODE;
        } else if (c_aware && c == '/' && i + 1 < len && t[i + 1] == '/') { state = S_LINE; i++; }
        else if (c_aware && c == '/' && i + 1 < len && t[i + 1] == '*') { state = S_BLOCK; i++; }
        else if (c_aware && c == '"') state = S_STR;
        else if (c_aware && c == '\'') state = S_CHR;
        else if (is_open(c)) {
            if (top == cap) {
                unsigned nc = cap ? cap * 2 : 64;
                unsigned *ns = (unsigned *)realloc(stack, nc * sizeof(unsigned));
                if (ns == NULL) { ok = 0; break; }
                stack = ns;
                cap = nc;
            }
            stack[top++] = i;
        } else if (brace_is_bracket(c)) {
            unsigned j = top;

            while (j > 0 && partner(c) != t[stack[j - 1]]) j--;      /* the nearest open bracket that this one closes */
            if (top == 0) ok = problem_add(out, &np, &pcap, i, BRACE_STRAY, 0);
            else if (j == 0) {                                        /* closes nothing that is open: a typo for the innermost */
                ok = problem_add(out, &np, &pcap, i, BRACE_MISMATCH, stack[top - 1]);
                top--;
            } else {
                while (ok && top > j) { ok = problem_add(out, &np, &pcap, stack[top - 1], BRACE_UNCLOSED, 0); top--; }
                top--;                                                /* the pair itself */
            }
        }
    }
    while (ok && top > 0) { ok = problem_add(out, &np, &pcap, stack[top - 1], BRACE_UNCLOSED, 0); top--; }
    free(stack);
    if (!ok) { free(*out); *out = NULL; return 0; }
    if (np > 1) qsort(*out, np, sizeof(BraceProblem), problem_cmp);
    return np;
}
