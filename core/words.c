#include <stdlib.h>
#include <string.h>
#include "words.h"
#include "fold.h"

enum { T_OPEN = 1, T_CLOSE, T_MID };

typedef struct { unsigned s, e; int type; } Tok;

typedef struct { Tok *v; unsigned n, cap; } TokList;

static int add_tok(TokList *l, unsigned s, unsigned e, int type)
{
    if (l->n == l->cap) {
        unsigned nc = l->cap ? l->cap * 2 : 64;
        Tok *nv = (Tok *)realloc(l->v, nc * sizeof(Tok));
        if (!nv) return 0;
        l->v = nv;
        l->cap = nc;
    }
    l->v[l->n].s = s;
    l->v[l->n].e = e;
    l->v[l->n].type = type;
    l->n++;
    return 1;
}

static int is_wc(u16 c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

static int word_is(const u16 *t, unsigned s, unsigned e, const char *w)
{
    unsigned i;

    for (i = 0; w[i]; i++) if (s + i >= e || t[s + i] != (u16)(unsigned char)w[i]) return 0;
    return s + i == e;
}

/* A word on the rest of the line [from, EOL), up to a comment? */
static int line_has_word(const u16 *t, unsigned n, unsigned from, const char *w)
{
    unsigned i = from;

    while (i < n && t[i] != '\n') {
        if (t[i] == '#') break;
        if (is_wc(t[i]) && (i == from || !is_wc(t[i - 1]))) {
            unsigned j = i;
            while (j < n && is_wc(t[j])) j++;
            if (word_is(t, i, j, w)) return 1;
            i = j;
        } else i++;
    }
    return 0;
}

/* ---- shell and csh ---- */

/* Classifies a word at a command position; *after is whether a command can follow it directly. */
static int classify_sh(const u16 *t, unsigned s, unsigned e, int csh, int *after)
{
    static const char *const sh_open[] = { "if", "case", "while", "until", "for", "select", "repeat", NULL };
    static const char *const sh_close[] = { "fi", "esac", "done", NULL };
    static const char *const sh_mid[] = { "then", "elif", "else", "do", NULL };
    static const char *const csh_open[] = { "foreach", "while", "switch", NULL };
    static const char *const csh_close[] = { "end", "endif", "endsw", NULL };
    static const char *const csh_mid[] = { "else", NULL };
    const char *const *o = csh ? csh_open : sh_open, *const *c = csh ? csh_close : sh_close, *const *m = csh ? csh_mid : sh_mid;
    int i;

    *after = 0;
    for (i = 0; o[i]; i++) if (word_is(t, s, e, o[i])) {
        *after = word_is(t, s, e, "if") || word_is(t, s, e, "while") || word_is(t, s, e, "until");
        return T_OPEN;
    }
    for (i = 0; c[i]; i++) if (word_is(t, s, e, c[i])) return T_CLOSE;
    for (i = 0; m[i]; i++) if (word_is(t, s, e, m[i])) { *after = 1; return T_MID; }
    return 0;
}

static int scan_sh(const u16 *t, unsigned n, int csh, TokList *l)
{
    unsigned i = 0, j, end, lines, id;
    int cmd = 1, prev_else = 0;

    while (i < n) {
        u16 c = t[i];
        if (c == '\n') { cmd = 1; i++; continue; }
        if (c == ' ' && i + 5 < n && t[i + 1] == '.' && fold_token_at(t, n, i, &end, &lines, &id)) { i = end; cmd = 1; prev_else = 0; continue; }
        if (c == ' ' || c == '\t' || c == '\r') { i++; continue; }
        if (c == '\\') { i += (i + 1 < n) ? 2 : 1; continue; }
        if (c == '#' && (i == 0 || t[i - 1] == ' ' || t[i - 1] == '\t' || t[i - 1] == ';' || t[i - 1] == '\n')) {
            while (i < n && t[i] != '\n') i++;
            continue;
        }
        if (c == '\'') {
            for (j = i + 1; j < n && t[j] != '\''; j++) ;
            i = j + 1;
            cmd = 0;
            continue;
        }
        if (c == '"') {
            for (j = i + 1; j < n && t[j] != '"'; j++) if (t[j] == '\\') j++;
            i = j + 1;
            cmd = 0;
            continue;
        }
        if (c == ';' || c == '&' || c == '|' || c == '(' || c == ')' || c == '`' || (c == '{' && !(i > 0 && t[i - 1] == '$'))) {
            cmd = 1;
            prev_else = 0;
            i++;
            continue;
        }
        if (is_wc(c)) {
            u16 prev = i > 0 ? t[i - 1] : 0, next;
            int bad, after = 0, type = 0;

            for (j = i; j < n && is_wc(t[j]); j++) ;
            next = j < n ? t[j] : 0;
            bad = prev == '$' || prev == '-' || prev == '.' || prev == '/' || prev == '@' || prev == ':' ||
                  next == '=' || next == '-' || next == '.' || next == '/';
            if (cmd && !bad) {
                type = classify_sh(t, i, j, csh, &after);
                if (csh && type == T_OPEN && word_is(t, i, j, "if")) type = 0;       /* handled below */
                if (csh && cmd && !bad && word_is(t, i, j, "if")) {
                    /* `if (...) then` opens a block; `if (...) command` and `else if` do not */
                    if (!prev_else && line_has_word(t, n, j, "then")) type = T_OPEN;
                    after = 0;
                }
                if (type == T_MID && csh && word_is(t, i, j, "else")) after = 1;
                if (type != 0 && !add_tok(l, i, j, type)) return 0;
            }
            prev_else = (cmd && !bad && word_is(t, i, j, "else")) ? 1 : 0;
            cmd = type != 0 ? after : 0;
            i = j;
            continue;
        }
        if (c != '!') { cmd = 0; prev_else = 0; }
        i++;
    }
    return 1;
}


/* ---- Ruby ---- */

static int scan_ruby(const u16 *t, unsigned n, TokList *l)
{
    static const char *const open_any[] = { "def", "class", "module", NULL };           /* openers wherever they stand */
    static const char *const open_cmd[] = { "if", "unless", "while", "until", "case", "begin", "for", NULL };    /* ... only at the start of a statement */
    static const char *const mids[] = { "else", "elsif", "when", "rescue", "ensure", "then", "in", NULL };
    unsigned i = 0, j, end, lines, id, k;
    int cmd = 1, loop_stmt = 0, bol = 1;

    while (i < n) {
        u16 c = t[i];
        if (c == '\n') { cmd = 1; loop_stmt = 0; bol = 1; i++; continue; }
        if (c == ' ' && i + 5 < n && t[i + 1] == '.' && fold_token_at(t, n, i, &end, &lines, &id)) { i = end; cmd = 1; continue; }
        if (c == ' ' || c == '\t' || c == '\r') { i++; continue; }
        if (bol && c == '=' && word_is(t, i + 1, i + 6, "begin")) {            /* =begin ... =end */
            for (j = i; j < n; j++) {
                if (t[j] == '\n' && j + 4 < n && t[j + 1] == '=' && word_is(t, j + 2, j + 5, "end")) { j += 5; break; }
            }
            while (j < n && t[j] != '\n') j++;
            i = j;
            continue;
        }
        bol = 0;
        if (c == '\\') { i += (i + 1 < n) ? 2 : 1; continue; }
        if (c == '#') { while (i < n && t[i] != '\n') i++; continue; }
        if (c == '\'' || c == '"') {
            for (j = i + 1; j < n && t[j] != c; j++) if (t[j] == '\\') j++;
            i = j + 1;
            cmd = 0;
            continue;
        }
        if (c == ';' || c == '(' || c == '{' || c == '=') { cmd = 1; i++; continue; }
        if (is_wc(c)) {
            u16 prev = i > 0 ? t[i - 1] : 0, next, next2;
            int bad, type = 0, after = 0;

            for (j = i; j < n && is_wc(t[j]); j++) ;
            next = j < n ? t[j] : 0;
            next2 = j + 1 < n ? t[j + 1] : 0;
            bad = prev == '.' || prev == ':' || prev == '@' || prev == '$' || next == '?' || next == '!' ||
                  (next == ':' && next2 != ':');
            if (!bad) {
                if (word_is(t, i, j, "end")) { type = T_CLOSE; }
                else if (word_is(t, i, j, "do")) {
                    if (loop_stmt) { loop_stmt = 0; type = 0; after = 1; }       /* `while x do`: the loop's own end */
                    else type = T_OPEN;
                    after = 1;
                } else {
                    for (k = 0; open_any[k]; k++) if (word_is(t, i, j, open_any[k])) type = T_OPEN;
                    if (!type && cmd) for (k = 0; open_cmd[k]; k++) if (word_is(t, i, j, open_cmd[k])) { type = T_OPEN; break; }
                    if (type == T_OPEN && cmd && (word_is(t, i, j, "while") || word_is(t, i, j, "until") || word_is(t, i, j, "for"))) loop_stmt = 1;
                    if (!type) for (k = 0; mids[k]; k++) if (word_is(t, i, j, mids[k])) { type = T_MID; after = 1; break; }
                    if (type == T_OPEN && word_is(t, i, j, "begin")) after = 1;
                }
                if (type != 0 && !add_tok(l, i, j, type)) return 0;
            }
            cmd = (type == T_MID || after) ? 1 : 0;
            i = j;
            continue;
        }
        cmd = 0;
        i++;
    }
    return 1;
}

/* ---- the C preprocessor ---- */

static int scan_cpp(const u16 *t, unsigned n, TokList *l)
{
    unsigned i = 0, j, k;
    int bol = 1;

    while (i < n) {
        u16 c = t[i];
        if (c == '\n') { bol = 1; i++; continue; }
        if (c == ' ' || c == '\t' || c == '\r') { i++; continue; }
        if (c == '/' && i + 1 < n && t[i + 1] == '*') {
            for (i += 2; i + 1 < n && !(t[i] == '*' && t[i + 1] == '/'); i++) ;
            i += 2;
            bol = 0;
            continue;
        }
        if (c == '/' && i + 1 < n && t[i + 1] == '/') {
            while (i < n && t[i] != '\n') i++;
            continue;
        }
        if (c == '"' || c == '\'') {
            for (j = i + 1; j < n && t[j] != c && t[j] != '\n'; j++) if (t[j] == '\\') j++;
            i = j + 1;
            bol = 0;
            continue;
        }
        if (c == '#' && bol) {
            j = i + 1;
            while (j < n && (t[j] == ' ' || t[j] == '\t')) j++;
            for (k = j; k < n && is_wc(t[k]); k++) ;
            if (word_is(t, j, k, "if") || word_is(t, j, k, "ifdef") || word_is(t, j, k, "ifndef")) { if (!add_tok(l, i, k, T_OPEN)) return 0; }
            else if (word_is(t, j, k, "endif")) { if (!add_tok(l, i, k, T_CLOSE)) return 0; }
            else if (word_is(t, j, k, "else") || word_is(t, j, k, "elif")) { if (!add_tok(l, i, k, T_MID)) return 0; }
            bol = 0;
            i = k > i ? k : i + 1;
            continue;
        }
        bol = 0;
        i++;
    }
    return 1;
}

/* ---- pairing ---- */

/* Which closing word a shell or csh block word goes with: 1 if/fi (endif), 2 case/esac (switch/endsw), 3 loops/done (end). */
static int family(const u16 *t, const Tok *k, int csh)
{
    if (word_is(t, k->s, k->e, "if") || word_is(t, k->s, k->e, "fi") || word_is(t, k->s, k->e, "endif")) return 1;
    if (word_is(t, k->s, k->e, csh ? "switch" : "case") || word_is(t, k->s, k->e, csh ? "endsw" : "esac")) return 2;
    return 3;
}

static void add_lone(WordBlocks *b, unsigned s, unsigned e, int type)
{
    b->lone[b->nlone].s = s;
    b->lone[b->nlone].e = e;
    b->lone[b->nlone].type = type;
    b->nlone++;
}

int words_scan(const u16 *t, unsigned n, int kind, WordBlocks *out)
{
    TokList l = { 0, 0, 0 };
    unsigned *stack = NULL, top = 0, i;
    int *pair_of = NULL;
    int ok;

    memset(out, 0, sizeof(*out));
    if (kind == WORDS_SH) ok = scan_sh(t, n, 0, &l);
    else if (kind == WORDS_CSH) ok = scan_sh(t, n, 1, &l);
    else if (kind == WORDS_CPP) ok = scan_cpp(t, n, &l);
    else if (kind == WORDS_RUBY) ok = scan_ruby(t, n, &l);
    else return 1;
    if (!ok) { free(l.v); return 0; }
    if (l.n == 0) { free(l.v); return 1; }
    stack = (unsigned *)malloc(l.n * sizeof(unsigned));
    pair_of = (int *)malloc(l.n * sizeof(int));
    out->pairs = (WordPair *)malloc(l.n * sizeof(WordPair));
    out->mids = (WordMid *)malloc(l.n * sizeof(WordMid));
    out->lone = (WordLone *)malloc(l.n * sizeof(WordLone));
    if (!stack || !pair_of || !out->pairs || !out->mids || !out->lone) { free(stack); free(pair_of); words_free(out); free(l.v); return 0; }
    for (i = 0; i < l.n; i++) pair_of[i] = -1;
    /* mids wait for their opener's pair, so remember which opener each belongs to */
    {
        unsigned *mid_open = (unsigned *)malloc(l.n * sizeof(unsigned));
        unsigned nmid = 0;

        if (!mid_open) { free(stack); free(pair_of); words_free(out); free(l.v); return 0; }
        for (i = 0; i < l.n; i++) {
            if (l.v[i].type == T_OPEN) stack[top++] = i;
            else if (l.v[i].type == T_CLOSE) {
                unsigned j = top;

                if (kind == WORDS_SH || kind == WORDS_CSH) {           /* the nearest open word that this one closes */
                    int f = family(t, &l.v[i], kind == WORDS_CSH);

                    while (j > 0 && family(t, &l.v[stack[j - 1]], kind == WORDS_CSH) != f) j--;
                }
                if (top > 0 && j > 0) {
                    unsigned o;

                    while (top > j) { top--; add_lone(out, l.v[stack[top]].s, l.v[stack[top]].e, WORD_LONE_OPEN); }
                    o = stack[--top];
                    out->pairs[out->npairs].os = l.v[o].s;
                    out->pairs[out->npairs].oe = l.v[o].e;
                    out->pairs[out->npairs].cs = l.v[i].s;
                    out->pairs[out->npairs].ce = l.v[i].e;
                    pair_of[o] = (int)out->npairs;
                    out->npairs++;
                } else add_lone(out, l.v[i].s, l.v[i].e, WORD_LONE_CLOSE);
            } else if (top == 0) {
                add_lone(out, l.v[i].s, l.v[i].e, WORD_LONE_MID);
            } else {
                out->mids[nmid].s = l.v[i].s;
                out->mids[nmid].e = l.v[i].e;
                mid_open[nmid] = stack[top - 1];
                nmid++;
            }
        }
        for (i = 0; i < nmid; i++) {
            if (pair_of[mid_open[i]] >= 0) {
                out->mids[out->nmids] = out->mids[i];
                out->mids[out->nmids].pair = (unsigned)pair_of[mid_open[i]];
                out->nmids++;
            }
        }
        free(mid_open);
        while (top > 0) { top--; add_lone(out, l.v[stack[top]].s, l.v[stack[top]].e, WORD_LONE_OPEN); }
    }
    free(stack);
    free(pair_of);
    free(l.v);
    return 1;
}

void words_free(WordBlocks *b)
{
    free(b->lone);
    b->lone = NULL;
    b->nlone = 0;
    free(b->pairs);
    free(b->mids);
    b->pairs = NULL;
    b->mids = NULL;
    b->npairs = b->nmids = 0;
}

int words_match(const WordBlocks *b, unsigned pos, unsigned *ws, unsigned *we, unsigned *ms, unsigned *me)
{
    unsigned i;

    for (i = 0; i < b->npairs; i++) {
        const WordPair *p = &b->pairs[i];
        if (pos >= p->os && pos <= p->oe) { *ws = p->os; *we = p->oe; *ms = p->cs; *me = p->ce; return 1; }
        if (pos >= p->cs && pos <= p->ce) { *ws = p->cs; *we = p->ce; *ms = p->os; *me = p->oe; return 1; }
    }
    for (i = 0; i < b->nmids; i++) {
        const WordMid *m = &b->mids[i];
        if (pos >= m->s && pos <= m->e) {
            *ws = m->s;
            *we = m->e;
            *ms = b->pairs[m->pair].cs;
            *me = b->pairs[m->pair].ce;
            return 1;
        }
    }
    return 0;
}

static unsigned line_end(const u16 *t, unsigned n, unsigned i)
{
    while (i < n && t[i] != '\n') i++;
    return i;
}

static unsigned line_start(const u16 *t, unsigned i)
{
    while (i > 0 && t[i - 1] != '\n') i--;
    return i;
}

int words_fold_block(const WordBlocks *b, const u16 *t, unsigned n, unsigned pos, unsigned *hs, unsigned *he)
{
    unsigned ls, le, i, best = 0, bestsize = 0;
    int found = 0;

    if (pos > n) pos = n;
    ls = line_start(t, pos);
    le = line_end(t, n, pos);
    /* opens on this line */
    for (i = 0; i < b->npairs; i++) {
        const WordPair *p = &b->pairs[i];
        if (p->os >= ls && p->os < le && p->cs > le && (!found || p->os < b->pairs[best].os)) { best = i; found = 1; }
    }
    /* closes on it */
    if (!found) {
        for (i = 0; i < b->npairs; i++) {
            const WordPair *p = &b->pairs[i];
            if (p->cs >= ls && p->cs < le && p->os < ls) { best = i; found = 1; break; }
        }
    }
    /* the innermost around it */
    if (!found) {
        for (i = 0; i < b->npairs; i++) {
            const WordPair *p = &b->pairs[i];
            if (p->os < ls && p->cs >= le && (!found || p->cs - p->os < bestsize)) { best = i; bestsize = p->cs - p->os; found = 1; }
        }
    }
    if (!found) return 0;
    *hs = line_end(t, n, b->pairs[best].os);
    *he = b->pairs[best].cs;
    return *he > *hs;
}

unsigned words_fold_top(const WordBlocks *b, const u16 *t, unsigned n, unsigned **hs, unsigned **he)
{
    unsigned count = 0, i, last_end = 0, *a, *c;
    unsigned *order;
    unsigned j;

    *hs = *he = NULL;
    if (b->npairs == 0) return 0;
    a = (unsigned *)malloc(b->npairs * sizeof(unsigned));
    c = (unsigned *)malloc(b->npairs * sizeof(unsigned));
    order = (unsigned *)malloc(b->npairs * sizeof(unsigned));
    if (!a || !c || !order) { free(a); free(c); free(order); return 0; }
    for (i = 0; i < b->npairs; i++) order[i] = i;
    for (i = 1; i < b->npairs; i++) {                       /* by position of the opening word */
        unsigned v = order[i];
        for (j = i; j > 0 && b->pairs[order[j - 1]].os > b->pairs[v].os; j--) order[j] = order[j - 1];
        order[j] = v;
    }
    for (i = 0; i < b->npairs; i++) {
        const WordPair *p = &b->pairs[order[i]];
        unsigned h;
        if (count > 0 && p->os < last_end) continue;         /* inside the block before */
        last_end = p->ce;
        h = line_end(t, n, p->os);
        if (p->cs > h) {
            a[count] = h;
            c[count] = p->cs;
            count++;
        }
    }
    free(order);
    *hs = a;
    *he = c;
    return count;
}
