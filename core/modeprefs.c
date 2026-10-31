#include "modeprefs.h"
#include <stdlib.h>
#include <string.h>

static const char *keys[MP_COUNT] = { "indent", "spaces", "auto", "wrap" };

void modeprefs_clear(ModePrefs *mp)
{
    mp->n = 0;
}

static int valid_value(int which, int value)
{
    if (value == MP_UNSET) return 1;
    if (which == MP_INDENT) return value >= 1 && value <= 16;
    return value == 0 || value == 1;
}

static int entry_empty(const ModeEntry *e)
{
    int i;

    for (i = 0; i < MP_COUNT; i++)
        if (e->v[i] != MP_UNSET) return 0;
    return 1;
}

static ModeEntry *find_entry(ModePrefs *mp, const char *name)
{
    int i;

    for (i = 0; i < mp->n; i++)
        if (strcmp(mp->e[i].name, name) == 0) return &mp->e[i];
    return NULL;
}

const ModeEntry *modeprefs_find(const ModePrefs *mp, const char *name)
{
    return find_entry((ModePrefs *)mp, name);
}

int modeprefs_get(const ModePrefs *mp, const char *name, int which)
{
    const ModeEntry *e;

    if (which < 0 || which >= MP_COUNT) return MP_UNSET;
    e = modeprefs_find(mp, name);
    return e != NULL ? e->v[which] : MP_UNSET;
}

int modeprefs_set(ModePrefs *mp, const char *name, int which, int value)
{
    ModeEntry *e;
    int i;

    if (which < 0 || which >= MP_COUNT || !valid_value(which, value)) return -1;
    if (name[0] == '\0' || strlen(name) >= MP_NAME_SIZE || strchr(name, ' ') != NULL) return -1;
    e = find_entry(mp, name);
    if (e == NULL) {
        if (value == MP_UNSET) return 0;
        if (mp->n >= MP_MAX_MODES) return -1;
        e = &mp->e[mp->n++];
        strcpy(e->name, name);
        for (i = 0; i < MP_COUNT; i++) e->v[i] = MP_UNSET;
    }
    e->v[which] = value;
    if (entry_empty(e)) {                       /* nothing left to override: the mode drops out */
        *e = mp->e[mp->n - 1];
        mp->n--;
    }
    return 0;
}

void modeprefs_parse(ModePrefs *mp, const char *text)
{
    const char *p = text;

    mp->n = 0;
    while (*p != '\0') {
        char line[256], *tok, *save;
        unsigned len = 0;
        char name[MP_NAME_SIZE];
        int first = 1;

        while (*p != '\0' && *p != '\n') { if (len < sizeof line - 1) line[len++] = *p; p++; }
        line[len] = '\0';
        if (*p == '\n') p++;
        name[0] = '\0';
        for (tok = line; *tok != '\0'; tok = save) {
            char *eq;

            while (*tok == ' ' || *tok == '\t') tok++;
            if (*tok == '\0') break;
            for (save = tok; *save != '\0' && *save != ' ' && *save != '\t'; save++) {}
            if (*save != '\0') *save++ = '\0';
            if (first) {
                first = 0;
                if (strlen(tok) >= MP_NAME_SIZE) break;
                strcpy(name, tok);
                continue;
            }
            eq = strchr(tok, '=');
            if (eq != NULL) {
                int k;

                *eq = '\0';
                for (k = 0; k < MP_COUNT; k++)
                    if (strcmp(tok, keys[k]) == 0) modeprefs_set(mp, name, k, atoi(eq + 1));
            }
        }
    }
}

unsigned modeprefs_format(const ModePrefs *mp, char *out, unsigned cap)
{
    unsigned total = 0;
    int i, k;

    if (cap > 0) out[0] = '\0';
    for (i = 0; i < mp->n; i++) {
        char line[160];
        unsigned l;

        strcpy(line, mp->e[i].name);
        for (k = 0; k < MP_COUNT; k++)
            if (mp->e[i].v[k] != MP_UNSET) {
                char num[16];
                int v = mp->e[i].v[k], d = 0, j;

                strcat(line, " ");
                strcat(line, keys[k]);
                strcat(line, "=");
                if (v == 0) num[d++] = '0';
                while (v > 0) { num[d++] = (char)('0' + v % 10); v /= 10; }
                for (j = 0; j < d / 2; j++) { char t = num[j]; num[j] = num[d - 1 - j]; num[d - 1 - j] = t; }
                num[d] = '\0';
                strcat(line, num);
            }
        strcat(line, "\n");
        l = (unsigned)strlen(line);
        if (cap > 0 && total + l < cap) memcpy(out + total, line, l + 1);
        total += l;
    }
    return total;
}
