#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "search.h"

/* ---- characters ---- */

static unsigned lower(unsigned c)
{
    if (c >= 'A' && c <= 'Z') return c + 32;
    if (c >= 0xC0 && c <= 0xDE && c != 0xD7) return c + 32;
    return c;
}

static unsigned upper(unsigned c)
{
    if (c >= 'a' && c <= 'z') return c - 32;
    if (c >= 0xE0 && c <= 0xFE && c != 0xF7) return c - 32;
    return c;
}

static int is_word(unsigned c)
{
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' ||
           (c >= 0xC0 && c != 0xD7 && c != 0xF7);
}

/* ---- the program ---- */

enum { I_CHAR, I_ANY, I_CLASS, I_SPLIT, I_JMP, I_SAVE, I_MARK, I_CHK, I_BOL, I_EOL, I_WB, I_NWB, I_WS, I_WE,
       I_BACK, I_NWBEFORE, I_NWAFTER, I_MATCH };

typedef struct { int op; int x; int y; } Inst;
typedef struct { u16 lo, hi; } Range;
typedef struct { int first; int count; int neg; } Class;
typedef struct { int kind; unsigned a; unsigned b; } Entry;       /* kind 0: try pc a at position b; 1: slot a was b */

#define MAX_PROG   30000
#define MAX_STACK  (2 * 1024 * 1024)
#define MAX_STEPS  4000000L
#define MAX_MARKS  32
#define NSLOTS_BASE (2 * SEARCH_NGROUPS)

struct Search {
    Inst *prog;  int nprog, capprog;
    Range *ranges;  int nranges, capranges;
    Class *classes;  int nclasses, capclasses;
    int icase;
    int nmarks;
    int first;                      /* the character every match must start with, or -1 */
    unsigned *slots;                /* captures (0..19) then loop marks */
    int nslots;
    Entry *stack;  unsigned top, capstack;
};

/* ---- the syntax tree ---- */

enum { N_EMPTY, N_CHAR, N_ANY, N_CLASS, N_CAT, N_ALT, N_REP, N_GROUP, N_BOL, N_EOL, N_WB, N_NWB, N_WS, N_WE, N_BACK };

typedef struct { int type; int a, b; int min, max, lazy; unsigned c; } Node;

typedef struct {
    const u16 *s;  unsigned n, i;
    Node *nodes;  int nn, capn;
    Search *sr;
    int ngroups;
    const char *err;
} Parser;

static int add_node(Parser *p, int type)
{
    Node *nd;

    if (p->nn == p->capn) {
        int c = p->capn ? p->capn * 2 : 64;
        Node *nn = (Node *)realloc(p->nodes, c * sizeof(Node));
        if (nn == NULL) { p->err = "out of memory"; return -1; }
        p->nodes = nn;
        p->capn = c;
    }
    nd = &p->nodes[p->nn];
    memset(nd, 0, sizeof(Node));
    nd->type = type;
    nd->a = nd->b = -1;
    return p->nn++;
}

static int add_range(Search *s, unsigned lo, unsigned hi)
{
    if (s->nranges == s->capranges) {
        int c = s->capranges ? s->capranges * 2 : 32;
        Range *r = (Range *)realloc(s->ranges, c * sizeof(Range));
        if (r == NULL) return 0;
        s->ranges = r;
        s->capranges = c;
    }
    s->ranges[s->nranges].lo = (u16)lo;
    s->ranges[s->nranges].hi = (u16)hi;
    s->nranges++;
    return 1;
}

static int new_class(Search *s, int neg)
{
    if (s->nclasses == s->capclasses) {
        int c = s->capclasses ? s->capclasses * 2 : 8;
        Class *cl = (Class *)realloc(s->classes, c * sizeof(Class));
        if (cl == NULL) return -1;
        s->classes = cl;
        s->capclasses = c;
    }
    s->classes[s->nclasses].first = s->nranges;
    s->classes[s->nclasses].count = 0;
    s->classes[s->nclasses].neg = neg;
    return s->nclasses++;
}

/* \d \w \s as ranges (kind is the letter, lower case) */
static int add_escape_ranges(Search *s, int kind, int *count)
{
    int before = s->nranges;
    int ok = 1;

    switch (kind) {
    case 'd': ok = add_range(s, '0', '9'); break;
    case 'w': ok = add_range(s, '0', '9') && add_range(s, 'a', 'z') && add_range(s, 'A', 'Z') && add_range(s, '_', '_')
                   && add_range(s, 0xC0, 0xD6) && add_range(s, 0xD8, 0xF6) && add_range(s, 0xF8, 0xFFFF); break;
    case 's': ok = add_range(s, ' ', ' ') && add_range(s, 9, 13); break;
    }
    *count += s->nranges - before;
    return ok;
}

static int parse_alt(Parser *p);

static int peek(Parser *p) { return p->i < p->n ? (int)p->s[p->i] : -1; }

/* The character an escape stands for (after the backslash), for the escapes that are plain characters. */
static unsigned escape_char(unsigned c)
{
    switch (c) {
    case 'n': return '\n';
    case 't': return '\t';
    case 'r': return '\r';
    case 'f': return '\f';
    default: return c;
    }
}

static int parse_class(Parser *p)
{
    Search *s = p->sr;
    int neg = 0, ci, nd, count = 0, firstitem = 1;
    unsigned c, lo;

    if (peek(p) == '^') { neg = 1; p->i++; }
    ci = new_class(s, neg);
    if (ci < 0) { p->err = "out of memory"; return -1; }
    for (;;) {
        if (p->i >= p->n) { p->err = "missing ]"; return -1; }
        c = p->s[p->i++];
        if (c == ']' && !firstitem) break;
        firstitem = 0;
        if (c == '\\' && p->i < p->n) {
            unsigned e = p->s[p->i++];
            if (e == 'd' || e == 'w' || e == 's') {
                if (!add_escape_ranges(s, (int)e, &count)) { p->err = "out of memory"; return -1; }
                continue;
            }
            c = escape_char(e);
        }
        lo = c;
        if (peek(p) == '-' && p->i + 1 < p->n && p->s[p->i + 1] != ']') {
            unsigned hi;
            p->i++;
            hi = p->s[p->i++];
            if (hi == '\\' && p->i < p->n) hi = escape_char(p->s[p->i++]);
            if (hi < lo) { p->err = "range in [] is backwards"; return -1; }
            if (!add_range(s, lo, hi)) { p->err = "out of memory"; return -1; }
            count++;
        } else {
            if (!add_range(s, lo, lo)) { p->err = "out of memory"; return -1; }
            count++;
        }
    }
    s->classes[ci].count = count;
    nd = add_node(p, N_CLASS);
    if (nd < 0) return -1;
    p->nodes[nd].a = ci;
    return nd;
}

/* A {n}, {n,} or {n,m} at p->i (just past the brace); returns 1 and fills min/max, or 0 leaving p->i alone. */
static int parse_braces(Parser *p, int *mn, int *mx)
{
    unsigned save = p->i;
    int a = 0, b = -1, digits = 0;

    while (p->i < p->n && p->s[p->i] >= '0' && p->s[p->i] <= '9') { a = a * 10 + (p->s[p->i++] - '0'); digits++; if (a > 255) a = 255; }
    if (!digits) { p->i = save; return 0; }
    if (peek(p) == ',') {
        int d2 = 0;
        p->i++;
        b = 0;
        while (p->i < p->n && p->s[p->i] >= '0' && p->s[p->i] <= '9') { b = b * 10 + (p->s[p->i++] - '0'); d2++; if (b > 255) b = 255; }
        if (!d2) b = -1;
    } else {
        b = a;
    }
    if (peek(p) != '}') { p->i = save; return 0; }
    p->i++;
    *mn = a;
    *mx = b;
    return 1;
}

static int parse_atom(Parser *p)
{
    unsigned c = p->s[p->i++];
    int nd, sub;

    switch (c) {
    case '(':
        if (peek(p) == '?' && p->i + 1 < p->n && p->s[p->i + 1] == ':') {
            p->i += 2;
            sub = parse_alt(p);
            if (sub < 0) return -1;
            if (peek(p) != ')') { p->err = "missing )"; return -1; }
            p->i++;
            return sub;
        }
        if (p->ngroups >= SEARCH_NGROUPS - 1) { p->err = "more than 9 groups"; return -1; }
        {
            int g = ++p->ngroups;
            sub = parse_alt(p);
            if (sub < 0) return -1;
            if (peek(p) != ')') { p->err = "missing )"; return -1; }
            p->i++;
            nd = add_node(p, N_GROUP);
            if (nd < 0) return -1;
            p->nodes[nd].a = sub;
            p->nodes[nd].c = (unsigned)g;
            return nd;
        }
    case '[': return parse_class(p);
    case '.': return add_node(p, N_ANY);
    case '^': return add_node(p, N_BOL);
    case '$': return add_node(p, N_EOL);
    case '\\':
        if (p->i >= p->n) { p->err = "pattern ends with a backslash"; return -1; }
        c = p->s[p->i++];
        switch (c) {
        case '<': return add_node(p, N_WS);
        case '>': return add_node(p, N_WE);
        case 'b': return add_node(p, N_WB);
        case 'B': return add_node(p, N_NWB);
        case 'd': case 'D': case 'w': case 'W': case 's': case 'S': {
            int ci = new_class(p->sr, c == 'D' || c == 'W' || c == 'S');
            int count = 0;
            if (ci < 0 || !add_escape_ranges(p->sr, (int)lower(c), &count)) { p->err = "out of memory"; return -1; }
            p->sr->classes[ci].count = count;
            nd = add_node(p, N_CLASS);
            if (nd < 0) return -1;
            p->nodes[nd].a = ci;
            return nd;
        }
        default:
            if (c >= '1' && c <= '9') {
                nd = add_node(p, N_BACK);
                if (nd < 0) return -1;
                p->nodes[nd].c = c - '0';
                return nd;
            }
            nd = add_node(p, N_CHAR);
            if (nd < 0) return -1;
            p->nodes[nd].c = escape_char(c);
            return nd;
        }
    case '*': case '+': case '?':
        p->err = "nothing before a repeat";
        return -1;
    default:
        nd = add_node(p, N_CHAR);
        if (nd < 0) return -1;
        p->nodes[nd].c = c;
        return nd;
    }
}

static int parse_rep(Parser *p)
{
    int atom = parse_atom(p), nd;

    if (atom < 0) return -1;
    for (;;) {
        int c = peek(p), mn, mx;

        if (c == '*') { mn = 0; mx = -1; p->i++; }
        else if (c == '+') { mn = 1; mx = -1; p->i++; }
        else if (c == '?') { mn = 0; mx = 1; p->i++; }
        else if (c == '{') {
            p->i++;
            if (!parse_braces(p, &mn, &mx)) { p->i--; break; }       /* a brace that is not a repeat is an ordinary character */
            if (mx != -1 && mx < mn) { p->err = "repeat count is backwards"; return -1; }
        } else break;
        nd = add_node(p, N_REP);
        if (nd < 0) return -1;
        p->nodes[nd].a = atom;
        p->nodes[nd].min = mn;
        p->nodes[nd].max = mx;
        if (peek(p) == '?') { p->nodes[nd].lazy = 1; p->i++; }
        atom = nd;
    }
    return atom;
}

static int parse_cat(Parser *p)
{
    int left = -1, nd, right;

    while (p->i < p->n && p->s[p->i] != '|' && p->s[p->i] != ')') {
        right = parse_rep(p);
        if (right < 0) return -1;
        if (left < 0) { left = right; continue; }
        nd = add_node(p, N_CAT);
        if (nd < 0) return -1;
        p->nodes[nd].a = left;
        p->nodes[nd].b = right;
        left = nd;
    }
    if (left < 0) left = add_node(p, N_EMPTY);
    return left;
}

static int parse_alt(Parser *p)
{
    int left = parse_cat(p), right, nd;

    if (left < 0) return -1;
    while (peek(p) == '|') {
        p->i++;
        right = parse_cat(p);
        if (right < 0) return -1;
        nd = add_node(p, N_ALT);
        if (nd < 0) return -1;
        p->nodes[nd].a = left;
        p->nodes[nd].b = right;
        left = nd;
    }
    return left;
}

/* ---- code generation ---- */

typedef struct { Search *s; Parser *p; const char *err; } Gen;

static int emit(Gen *g, int op, int x, int y)
{
    Search *s = g->s;

    if (s->nprog >= MAX_PROG) { g->err = "pattern is too big"; return -1; }
    if (s->nprog == s->capprog) {
        int c = s->capprog ? s->capprog * 2 : 64;
        Inst *pr = (Inst *)realloc(s->prog, c * sizeof(Inst));
        if (pr == NULL) { g->err = "out of memory"; return -1; }
        s->prog = pr;
        s->capprog = c;
    }
    s->prog[s->nprog].op = op;
    s->prog[s->nprog].x = x;
    s->prog[s->nprog].y = y;
    return s->nprog++;
}

static int nullable(Parser *p, int n)
{
    Node *nd = &p->nodes[n];

    switch (nd->type) {
    case N_CHAR: case N_ANY: case N_CLASS: return 0;
    case N_CAT: return nullable(p, nd->a) && nullable(p, nd->b);
    case N_ALT: return nullable(p, nd->a) || nullable(p, nd->b);
    case N_REP: return nd->min == 0 || nullable(p, nd->a);
    case N_GROUP: return nullable(p, nd->a);
    default: return 1;
    }
}

static int gen(Gen *g, int n)
{
    Parser *p = g->p;
    Search *s = g->s;
    Node *nd = &p->nodes[n];
    int i, l1, l2, l3, k;

    if (g->err) return -1;
    switch (nd->type) {
    case N_EMPTY: return 0;
    case N_CHAR: return emit(g, I_CHAR, (int)(s->icase ? lower(nd->c) : nd->c), 0) < 0 ? -1 : 0;
    case N_ANY: return emit(g, I_ANY, 0, 0) < 0 ? -1 : 0;
    case N_CLASS: return emit(g, I_CLASS, nd->a, 0) < 0 ? -1 : 0;
    case N_BOL: return emit(g, I_BOL, 0, 0) < 0 ? -1 : 0;
    case N_EOL: return emit(g, I_EOL, 0, 0) < 0 ? -1 : 0;
    case N_WB: return emit(g, I_WB, 0, 0) < 0 ? -1 : 0;
    case N_NWB: return emit(g, I_NWB, 0, 0) < 0 ? -1 : 0;
    case N_WS: return emit(g, I_WS, 0, 0) < 0 ? -1 : 0;
    case N_WE: return emit(g, I_WE, 0, 0) < 0 ? -1 : 0;
    case N_BACK: return emit(g, I_BACK, (int)nd->c, 0) < 0 ? -1 : 0;
    case N_CAT:
        if (gen(g, nd->a) < 0) return -1;
        return gen(g, nd->b);
    case N_ALT:
        l1 = emit(g, I_SPLIT, 0, 0);
        if (l1 < 0) return -1;
        s->prog[l1].x = s->nprog;
        if (gen(g, nd->a) < 0) return -1;
        l2 = emit(g, I_JMP, 0, 0);
        if (l2 < 0) return -1;
        s->prog[l1].y = s->nprog;
        if (gen(g, nd->b) < 0) return -1;
        s->prog[l2].x = s->nprog;
        return 0;
    case N_GROUP:
        if (emit(g, I_SAVE, 2 * (int)nd->c, 0) < 0) return -1;
        if (gen(g, nd->a) < 0) return -1;
        return emit(g, I_SAVE, 2 * (int)nd->c + 1, 0) < 0 ? -1 : 0;
    case N_REP: {
        int splits[256], ns = 0;
        for (i = 0; i < nd->min; i++)
            if (gen(g, nd->a) < 0) return -1;
        if (nd->max == -1) {
            int mark = nullable(p, nd->a);
            l1 = emit(g, I_SPLIT, 0, 0);
            if (l1 < 0) return -1;
            k = -1;
            if (mark) {
                if (s->nmarks >= MAX_MARKS) { g->err = "too many nested repeats"; return -1; }
                k = s->nmarks++;
                if (emit(g, I_MARK, k, 0) < 0) return -1;
            }
            l2 = s->nprog;
            if (gen(g, nd->a) < 0) return -1;
            if (mark && emit(g, I_CHK, k, 0) < 0) return -1;
            l3 = emit(g, I_JMP, l1, 0);
            if (l3 < 0) return -1;
            if (nd->lazy) { s->prog[l1].x = s->nprog; s->prog[l1].y = l1 + 1; }
            else { s->prog[l1].x = l1 + 1; s->prog[l1].y = s->nprog; }
            (void)l2;
        } else {
            for (i = nd->min; i < nd->max; i++) {
                l1 = emit(g, I_SPLIT, 0, 0);
                if (l1 < 0) return -1;
                s->prog[l1].x = l1 + 1;           /* greedy: take the repeat; fixed up below for lazy */
                splits[ns++] = l1;
                if (gen(g, nd->a) < 0) return -1;
            }
            for (i = 0; i < ns; i++) {
                if (nd->lazy) { s->prog[splits[i]].x = s->nprog; s->prog[splits[i]].y = splits[i] + 1; }
                else { s->prog[splits[i]].y = s->nprog; }
            }
        }
        return 0;
    }
    }
    return 0;
}

/* ---- creating a search ---- */

static void set_err(char *err, unsigned size, const char *msg)
{
    if (err != NULL && size > 0) {
        strncpy(err, msg, size - 1);
        err[size - 1] = '\0';
    }
}

void search_free(Search *s)
{
    if (s == NULL) return;
    free(s->prog);
    free(s->ranges);
    free(s->classes);
    free(s->slots);
    free(s->stack);
    free(s);
}

Search *search_new(const u16 *pat, unsigned npat, int flags, char *err, unsigned errsize)
{
    Search *s = (Search *)calloc(1, sizeof(Search));
    Gen g;
    unsigned i;
    int wordl, wordr;

    if (s == NULL) { set_err(err, errsize, "out of memory"); return NULL; }
    s->icase = (flags & SEARCH_ICASE) != 0;
    g.s = s;
    g.err = NULL;
    g.p = NULL;
    if (npat == 0) { set_err(err, errsize, "the search text is empty"); search_free(s); return NULL; }
    /* A whole word needs a boundary where the pattern's own edge is a word character (so "->" can still be found as a word);
     * a regular expression is not looked into, so it always gets both. */
    wordl = (flags & SEARCH_WORD) && ((flags & SEARCH_REGEX) || is_word(pat[0]));
    wordr = (flags & SEARCH_WORD) && ((flags & SEARCH_REGEX) || is_word(pat[npat - 1]));
    if (wordl) {
        if (emit(&g, I_NWBEFORE, 0, 0) < 0) goto nomem;
    }
    if (flags & SEARCH_REGEX) {
        Parser p;
        int root;

        memset(&p, 0, sizeof(p));
        p.s = pat;
        p.n = npat;
        p.sr = s;
        root = parse_alt(&p);
        if (root >= 0 && p.i < p.n) { p.err = "unmatched )"; root = -1; }
        if (root < 0) {
            set_err(err, errsize, p.err != NULL ? p.err : "bad pattern");
            free(p.nodes);
            search_free(s);
            return NULL;
        }
        g.p = &p;
        if (gen(&g, root) < 0) {
            set_err(err, errsize, g.err != NULL ? g.err : "bad pattern");
            free(p.nodes);
            search_free(s);
            return NULL;
        }
        free(p.nodes);
    } else {
        for (i = 0; i < npat; i++)
            if (emit(&g, I_CHAR, (int)(s->icase ? lower(pat[i]) : pat[i]), 0) < 0) goto nomem;
    }
    if (wordr) {
        if (emit(&g, I_NWAFTER, 0, 0) < 0) goto nomem;
    }
    if (emit(&g, I_MATCH, 0, 0) < 0) goto nomem;
    s->first = (s->prog[0].op == I_CHAR) ? s->prog[0].x : -1;
    s->nslots = NSLOTS_BASE + s->nmarks;
    s->slots = (unsigned *)malloc(s->nslots * sizeof(unsigned));
    if (s->slots == NULL) goto nomem;
    return s;

nomem:
    set_err(err, errsize, g.err != NULL ? g.err : "out of memory");
    search_free(s);
    return NULL;
}

/* ---- running ---- */

static int push(Search *s, int kind, unsigned a, unsigned b)
{
    if (s->top == s->capstack) {
        unsigned c = s->capstack ? s->capstack * 2 : 256;
        Entry *e;
        if (c > MAX_STACK) return 0;
        e = (Entry *)realloc(s->stack, c * sizeof(Entry));
        if (e == NULL) return 0;
        s->stack = e;
        s->capstack = c;
    }
    s->stack[s->top].kind = kind;
    s->stack[s->top].a = a;
    s->stack[s->top].b = b;
    s->top++;
    return 1;
}

static int class_has(const Search *s, const Class *cl, unsigned c)
{
    int i;

    for (i = 0; i < cl->count; i++) {
        const Range *r = &s->ranges[cl->first + i];
        if (c >= r->lo && c <= r->hi) return 1;
    }
    return 0;
}

static int class_match(const Search *s, const Class *cl, unsigned c)
{
    int in = class_has(s, cl, c);

    if (!in && s->icase) in = class_has(s, cl, lower(c)) || class_has(s, cl, upper(c));
    return cl->neg ? !in : in;
}

/* Tries the program at `start`; the captures are left in s->slots on success. */
static int run(Search *s, const u16 *t, unsigned len, unsigned start)
{
    const Inst *pr = s->prog;
    unsigned *sl = s->slots;
    unsigned pc = 0, sp = start;
    long steps = 0;
    int i;

    s->top = 0;
    for (i = 0; i < s->nslots; i++) sl[i] = SEARCH_NONE;
    sl[0] = start;
    for (;;) {
        const Inst *in = &pr[pc];

        if (++steps > MAX_STEPS) return 0;
        switch (in->op) {
        case I_CHAR:
            if (sp < len && (s->icase ? lower(t[sp]) : (unsigned)t[sp]) == (unsigned)in->x) { sp++; pc++; continue; }
            break;
        case I_ANY:
            if (sp < len && t[sp] != '\n') { sp++; pc++; continue; }
            break;
        case I_CLASS:
            if (sp < len && class_match(s, &s->classes[in->x], t[sp])) { sp++; pc++; continue; }
            break;
        case I_SPLIT:
            if (!push(s, 0, (unsigned)in->y, sp)) return 0;
            pc = (unsigned)in->x;
            continue;
        case I_JMP:
            pc = (unsigned)in->x;
            continue;
        case I_SAVE:
            if (!push(s, 1, (unsigned)in->x, sl[in->x])) return 0;
            sl[in->x] = sp;
            pc++;
            continue;
        case I_MARK:
            if (!push(s, 1, (unsigned)(NSLOTS_BASE + in->x), sl[NSLOTS_BASE + in->x])) return 0;
            sl[NSLOTS_BASE + in->x] = sp;
            pc++;
            continue;
        case I_CHK:
            if (sl[NSLOTS_BASE + in->x] != sp) { pc++; continue; }
            break;                                  /* an empty pass round a loop: stop going round */
        case I_BOL:
            if (sp == 0 || t[sp - 1] == '\n') { pc++; continue; }
            break;
        case I_EOL:
            if (sp == len || t[sp] == '\n') { pc++; continue; }
            break;
        case I_WB: case I_NWB: case I_WS: case I_WE: {
            int before = sp > 0 && is_word(t[sp - 1]);
            int after = sp < len && is_word(t[sp]);
            int ok;
            if (in->op == I_WB) ok = before != after;
            else if (in->op == I_NWB) ok = before == after;
            else if (in->op == I_WS) ok = !before && after;
            else ok = before && !after;
            if (ok) { pc++; continue; }
            break;
        }
        case I_NWBEFORE:
            if (!(sp > 0 && is_word(t[sp - 1]))) { pc++; continue; }
            break;
        case I_NWAFTER:
            if (!(sp < len && is_word(t[sp]))) { pc++; continue; }
            break;
        case I_BACK: {
            unsigned a = sl[2 * in->x], b = sl[2 * in->x + 1], n, j;
            if (a == SEARCH_NONE || b == SEARCH_NONE) break;
            n = b - a;
            if (sp + n > len) break;
            for (j = 0; j < n; j++) {
                unsigned x = t[a + j], y = t[sp + j];
                if (x != y && !(s->icase && lower(x) == lower(y))) break;
            }
            if (j < n) break;
            sp += n;
            pc++;
            continue;
        }
        case I_MATCH:
            sl[1] = sp;
            return 1;
        }
        /* failure: back up to the last choice */
        for (;;) {
            Entry e;
            if (s->top == 0) return 0;
            e = s->stack[--s->top];
            if (e.kind == 1) { sl[e.a] = e.b; continue; }
            pc = e.a;
            sp = e.b;
            break;
        }
    }
}

static void fill(const Search *s, SearchMatch *m)
{
    int g;

    for (g = 0; g < SEARCH_NGROUPS; g++) {
        unsigned a = s->slots[2 * g], b = s->slots[2 * g + 1];
        if (a == SEARCH_NONE || b == SEARCH_NONE || b < a) { m->start[g] = m->end[g] = SEARCH_NONE; }
        else { m->start[g] = a; m->end[g] = b; }
    }
}

int search_match_at(Search *s, const u16 *text, unsigned len, unsigned pos, SearchMatch *m)
{
    if (pos > len) return 0;
    if (!run(s, text, len, pos)) return 0;
    fill(s, m);
    return 1;
}

static int try_at(Search *s, const u16 *text, unsigned len, unsigned pos, SearchMatch *m)
{
    if (s->first >= 0) {
        if (pos >= len) return 0;
        if ((s->icase ? lower(text[pos]) : (unsigned)text[pos]) != (unsigned)s->first) return 0;
    }
    if (!run(s, text, len, pos)) return 0;
    fill(s, m);
    return 1;
}

int search_find(Search *s, const u16 *text, unsigned len, unsigned from, int forward, int wrap, SearchMatch *m)
{
    unsigned pos;

    if (from > len) from = len;
    if (forward) {
        for (pos = from; pos <= len; pos++)
            if (try_at(s, text, len, pos, m)) return 1;
        if (wrap)
            for (pos = 0; pos < from; pos++)
                if (try_at(s, text, len, pos, m)) return 1;
    } else {
        for (pos = from; pos > 0; pos--)
            if (try_at(s, text, len, pos - 1, m)) return 1;
        if (wrap)
            for (pos = len + 1; pos > from; pos--)
                if (try_at(s, text, len, pos - 1, m)) return 1;
    }
    return 0;
}

/* ---- replacing ---- */

unsigned search_expand(const SearchMatch *m, const u16 *text, const u16 *repl, unsigned nrepl, int literal,
                       u16 *out, unsigned cap)
{
    unsigned need = 0, i, j;

#define PUT(ch) do { if (need < cap) out[need] = (u16)(ch); need++; } while (0)
    for (i = 0; i < nrepl; i++) {
        unsigned c = repl[i];
        if (!literal && c == '\\' && i + 1 < nrepl) {
            unsigned e = repl[++i];
            if (e >= '0' && e <= '9') {
                int g = (int)(e - '0');
                if (m->start[g] != SEARCH_NONE)
                    for (j = m->start[g]; j < m->end[g]; j++) PUT(text[j]);
            } else if (e == 'n') PUT('\n');
            else if (e == 't') PUT('\t');
            else PUT(e);
        } else {
            PUT(c);
        }
    }
#undef PUT
    return need;
}

int search_replace_all(Search *s, const u16 *text, unsigned len, unsigned lo, unsigned hi, const u16 *repl, unsigned nrepl,
                       int literal, u16 **out, unsigned *outlen, unsigned *first, unsigned *last, unsigned *count)
{
    u16 *buf = NULL;
    unsigned used = 0, capb = 0, n = 0, pos = lo, copied = 0, need, i;
    SearchMatch m;

    *out = NULL;
    *outlen = 0;
    *count = 0;
    if (hi > len) hi = len;
    while (pos <= hi && search_find(s, text, len, pos, 1, 0, &m)) {
        if (m.end[0] > hi || m.start[0] > hi) break;
        if (n == 0) { *first = m.start[0]; copied = m.start[0]; }
        need = (m.start[0] - copied) + search_expand(&m, text, repl, nrepl, literal, NULL, 0);
        if (used + need > capb) {
            unsigned c = capb ? capb : 256;
            u16 *nb;
            while (used + need > c) c *= 2;
            nb = (u16 *)realloc(buf, c * sizeof(u16));
            if (nb == NULL) { free(buf); return 0; }
            buf = nb;
            capb = c;
        }
        for (i = copied; i < m.start[0]; i++) buf[used++] = text[i];
        used += search_expand(&m, text, repl, nrepl, literal, buf + used, capb - used);
        copied = m.end[0];
        n++;
        pos = m.end[0] > m.start[0] ? m.end[0] : m.end[0] + 1;
    }
    if (n == 0) { free(buf); return 0; }
    *out = buf;
    *outlen = used;
    *last = copied;
    *count = n;
    return 1;
}
