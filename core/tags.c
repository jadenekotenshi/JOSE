#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tags.h"

struct Tags {
    Tag *v;
    unsigned n, cap;
};

static char *dup_range(const char *s, size_t n)
{
    char *p = (char *)malloc(n + 1);

    if (p == NULL) return NULL;
    memcpy(p, s, n);
    p[n] = '\0';
    return p;
}

static void free_tag(Tag *t)
{
    free(t->name);
    free(t->file);
    free(t->pattern);
    free(t->kind);
    free(t->signature);
}

void tags_free(Tags *t)
{
    unsigned i;

    if (t == NULL) return;
    for (i = 0; i < t->n; i++) free_tag(&t->v[i]);
    free(t->v);
    free(t);
}

unsigned tags_count(const Tags *t) { return t->n; }
const Tag *tags_at(const Tags *t, unsigned i) { return &t->v[i]; }

/* ---- reading ---- */

/* Parses the search pattern at s (which points at the opening / or ?): returns the text of the line without ^ and $, with the
 * escapes taken out, and sets *end to just past the closing delimiter.  NULL if it does not close. */
static char *parse_pattern(const char *s, const char **end)
{
    char delim = s[0];
    const char *p = s + 1, *e;
    size_t len = 0;
    char *out;
    int anchored_end = 0;

    for (e = p; *e && *e != delim; e++) if (*e == '\\' && e[1]) e++;
    if (*e != delim) return NULL;
    *end = e + 1;
    out = (char *)malloc((size_t)(e - p) + 1);
    if (out == NULL) return NULL;
    if (*p == '^') p++;
    while (p < e) {
        if (*p == '\\' && p + 1 < e && (p[1] == '\\' || p[1] == '/' || p[1] == '?' || p[1] == '$' || p[1] == '^' || p[1] == '*' || p[1] == '[' || p[1] == ']' || p[1] == '.')) {
            out[len++] = p[1];
            p += 2;
        } else if (*p == '$' && p + 1 == e) {
            anchored_end = 1;
            p++;
        } else {
            out[len++] = *p++;
        }
    }
    (void)anchored_end;
    out[len] = '\0';
    return out;
}

static int add_tag(Tags *t, Tag *tag)
{
    if (t->n == t->cap) {
        unsigned nc = t->cap ? t->cap * 2 : 256;
        Tag *nv = (Tag *)realloc(t->v, nc * sizeof(Tag));
        if (nv == NULL) return 0;
        t->v = nv;
        t->cap = nc;
    }
    t->v[t->n++] = *tag;
    return 1;
}

/* One line (without its newline).  Lines that are not tags are ignored. */
static void parse_line(Tags *t, char *line)
{
    char *tab1, *tab2, *addr, *rest = NULL;
    Tag tag;
    const char *end;

    if (line[0] == '!' || line[0] == '\0') return;
    tab1 = strchr(line, '\t');
    if (tab1 == NULL) return;
    tab2 = strchr(tab1 + 1, '\t');
    if (tab2 == NULL) return;
    addr = tab2 + 1;
    memset(&tag, 0, sizeof tag);
    if (*addr == '/' || *addr == '?') {
        tag.pattern = parse_pattern(addr, &end);
        if (tag.pattern == NULL) return;
        rest = (char *)end;
    } else if (*addr >= '0' && *addr <= '9') {
        char *e;
        tag.line = (int)strtol(addr, &e, 10);
        rest = e;
    } else {
        return;
    }
    tag.name = dup_range(line, (size_t)(tab1 - line));
    tag.file = dup_range(tab1 + 1, (size_t)(tab2 - tab1 - 1));
    /* extension fields: ;"<TAB>kind<TAB>name:value ... */
    if (rest != NULL && rest[0] == ';' && rest[1] == '"') {
        char *f = rest + 2;
        while (*f == '\t') {
            char *next = strchr(f + 1, '\t');
            size_t len = next ? (size_t)(next - f - 1) : strlen(f + 1);
            const char *field = f + 1;
            if (len > 0) {
                const char *colon = memchr(field, ':', len);
                if (colon == NULL && tag.kind == NULL) tag.kind = dup_range(field, len);
                else if (colon != NULL && (size_t)(colon - field) == 4 && strncmp(field, "kind", 4) == 0 && tag.kind == NULL)
                    tag.kind = dup_range(colon + 1, len - 5);
                else if (colon != NULL && (size_t)(colon - field) == 9 && strncmp(field, "signature", 9) == 0 && tag.signature == NULL)
                    tag.signature = dup_range(colon + 1, len - 10);
                else if (colon != NULL && (size_t)(colon - field) == 4 && strncmp(field, "line", 4) == 0 && tag.line == 0)
                    tag.line = atoi(colon + 1);
            }
            if (next == NULL) break;
            f = next;
        }
    }
    if (tag.name == NULL || tag.file == NULL || !add_tag(t, &tag)) free_tag(&tag);
}

/* A stable merge sort by name, so that tags of one name stay in file order. */
static void sort_tags(Tags *t)
{
    Tag *tmp, *src = t->v, *dst;
    unsigned width, lo;

    if (t->n < 2) return;
    tmp = (Tag *)malloc(t->n * sizeof(Tag));
    if (tmp == NULL) return;
    dst = tmp;
    for (width = 1; width < t->n; width *= 2) {
        Tag *swap;
        for (lo = 0; lo < t->n; lo += 2 * width) {
            unsigned mid = lo + width < t->n ? lo + width : t->n;
            unsigned hi = lo + 2 * width < t->n ? lo + 2 * width : t->n;
            unsigned a = lo, b = mid, k = lo;
            while (a < mid && b < hi) dst[k++] = strcmp(src[b].name, src[a].name) < 0 ? src[b++] : src[a++];
            while (a < mid) dst[k++] = src[a++];
            while (b < hi) dst[k++] = src[b++];
        }
        swap = src;
        src = dst;
        dst = swap;
    }
    if (src != t->v) memcpy(t->v, src, t->n * sizeof(Tag));
    free(tmp);
}

Tags *tags_load(const char *path)
{
    FILE *fp = fopen(path, "r");
    Tags *t;
    char *buf = NULL;
    size_t cap = 0, len = 0;
    int c;

    if (fp == NULL) return NULL;
    t = (Tags *)calloc(1, sizeof(Tags));
    if (t == NULL) { fclose(fp); return NULL; }
    while ((c = getc(fp)) != EOF) {
        if (c == '\n' || c == '\r') {
            if (len > 0) { buf[len] = '\0'; parse_line(t, buf); }
            len = 0;
            continue;
        }
        if (len + 2 > cap) {
            size_t nc = cap ? cap * 2 : 1024;
            char *nb = (char *)realloc(buf, nc);
            if (nb == NULL) break;
            buf = nb;
            cap = nc;
        }
        buf[len++] = (char)c;
    }
    if (len > 0) { buf[len] = '\0'; parse_line(t, buf); }
    free(buf);
    fclose(fp);
    sort_tags(t);
    return t;
}

unsigned tags_find(const Tags *t, const char *name, unsigned *first)
{
    unsigned lo = 0, hi = t->n, count = 0, i;

    while (lo < hi) {                                           /* the first tag not before `name` */
        unsigned mid = lo + (hi - lo) / 2;
        if (strcmp(t->v[mid].name, name) < 0) lo = mid + 1;
        else hi = mid;
    }
    for (i = lo; i < t->n && strcmp(t->v[i].name, name) == 0; i++) count++;
    *first = lo;
    return count;
}

unsigned tags_tip(const Tag *tag, char *out, unsigned cap)
{
    const char *s = NULL;
    char tmp[1024];
    size_t a = 0, b;

    if (cap == 0) return 0;
    if (tag->pattern != NULL && strchr(tag->pattern, '(') != NULL) s = tag->pattern;
    if (s == NULL && tag->signature != NULL && strlen(tag->name) + strlen(tag->signature) < sizeof tmp) {
        strcpy(tmp, tag->name);
        strcat(tmp, tag->signature);
        s = tmp;
    }
    if (s == NULL) s = tag->pattern != NULL ? tag->pattern : tag->name;
    while (s[a] == ' ' || s[a] == '\t') a++;
    b = strlen(s);
    while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\t' || s[b - 1] == '\r')) b--;
    if (b - a >= cap) b = a + cap - 1;
    memcpy(out, s + a, b - a);
    out[b - a] = '\0';
    {   /* tabs inside show as spaces */
        size_t i;
        for (i = 0; out[i]; i++) if (out[i] == '\t') out[i] = ' ';
    }
    return (unsigned)(b - a);
}
