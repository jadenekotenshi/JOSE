#include <stdlib.h>
#include <string.h>
#include "undo.h"

typedef struct {
    unsigned pos;
    u16 *removed;  unsigned nremoved;
    u16 *inserted; unsigned ninserted;
    unsigned long when;                 /* time of the last edit merged into it */
    unsigned long serial;               /* identifies the text state after this step */
    int closed;                         /* nothing more may be merged into it */
} Step;

struct Undo {
    Step *undo_s; unsigned nundo, capundo;
    Step *redo_s; unsigned nredo, capredo;
    unsigned max_steps;
    unsigned long max_units, units;
    unsigned long next_serial;
    UndoStep out;                       /* what the last undo/redo call returned points into this */
    Step held;                          /* the step handed out by undo_undo/undo_redo, freed at the next call */
    int have_held;
};

#define MERGE_GAP_MS 3000UL

static unsigned long step_units(const Step *s) { return (unsigned long)s->nremoved + s->ninserted; }

static void step_free(Step *s)
{
    free(s->removed);
    free(s->inserted);
    s->removed = s->inserted = NULL;
}

static u16 *dup16(const u16 *p, unsigned n)
{
    u16 *r;

    if (n == 0) return NULL;
    r = (u16 *)malloc(n * sizeof(u16));
    if (r != NULL) memcpy(r, p, n * sizeof(u16));
    return r;
}

static void release_held(Undo *u)
{
    if (u->have_held) { step_free(&u->held); u->have_held = 0; }
}

Undo *undo_new(unsigned max_steps, unsigned long max_units)
{
    Undo *u = (Undo *)calloc(1, sizeof(Undo));

    if (u == NULL) return NULL;
    u->max_steps = max_steps > 0 ? max_steps : 1;
    u->max_units = max_units;
    return u;
}

static void clear_stack(Step *s, unsigned n)
{
    unsigned i;

    for (i = 0; i < n; i++) step_free(&s[i]);
}

void undo_clear(Undo *u)
{
    release_held(u);
    clear_stack(u->undo_s, u->nundo);
    clear_stack(u->redo_s, u->nredo);
    u->nundo = u->nredo = 0;
    u->units = 0;
}

void undo_free(Undo *u)
{
    if (u == NULL) return;
    undo_clear(u);
    free(u->undo_s);
    free(u->redo_s);
    free(u);
}

static int push(Step **arr, unsigned *n, unsigned *cap, const Step *s)
{
    if (*n == *cap) {
        unsigned nc = *cap ? *cap * 2 : 16;
        Step *na = (Step *)realloc(*arr, nc * sizeof(Step));

        if (na == NULL) return 0;
        *arr = na;
        *cap = nc;
    }
    (*arr)[(*n)++] = *s;
    return 1;
}

static void drop_oldest(Undo *u)
{
    unsigned i;

    if (u->nundo == 0) return;
    u->units -= step_units(&u->undo_s[0]);
    step_free(&u->undo_s[0]);
    for (i = 1; i < u->nundo; i++) u->undo_s[i - 1] = u->undo_s[i];
    u->nundo--;
}

void undo_break(Undo *u)
{
    if (u->nundo > 0) u->undo_s[u->nundo - 1].closed = 1;
}

/* Can the new edit join the newest step?  Typing: it inserts exactly where the last one ended.  Deleting: it removes
 * the text just before (backspace) or at (delete) where the last deletion was. */
static int can_merge(const Undo *u, unsigned pos, unsigned nremoved, unsigned ninserted, unsigned long now)
{
    const Step *t;

    if (u->nundo == 0) return 0;
    t = &u->undo_s[u->nundo - 1];
    if (t->closed || now - t->when > MERGE_GAP_MS) return 0;
    if (nremoved == 0 && ninserted > 0 && t->nremoved == 0)                       /* typing */
        return pos == t->pos + t->ninserted && ninserted <= 8;
    if (nremoved > 0 && ninserted == 0 && t->ninserted == 0) {                    /* deleting */
        if (nremoved > 8) return 0;
        return pos + nremoved == t->pos || pos == t->pos;
    }
    return 0;
}

void undo_record(Undo *u, unsigned pos, const u16 *removed, unsigned nremoved, const u16 *inserted, unsigned ninserted,
                 unsigned long now_ms)
{
    Step s;

    if (nremoved == 0 && ninserted == 0) return;
    release_held(u);
    clear_stack(u->redo_s, u->nredo);
    u->nredo = 0;

    if (can_merge(u, pos, nremoved, ninserted, now_ms)) {
        Step *t = &u->undo_s[u->nundo - 1];

        if (nremoved == 0) {                                  /* typing: append */
            u16 *ni = (u16 *)realloc(t->inserted, (t->ninserted + ninserted) * sizeof(u16));

            if (ni != NULL) {
                memcpy(ni + t->ninserted, inserted, ninserted * sizeof(u16));
                t->inserted = ni;
                t->ninserted += ninserted;
                u->units += ninserted;
                t->when = now_ms;
                t->serial = ++u->next_serial;
                return;
            }
        } else {                                              /* deleting */
            u16 *nr = (u16 *)malloc((t->nremoved + nremoved) * sizeof(u16));

            if (nr != NULL) {
                if (pos + nremoved == t->pos) {               /* backspace: the new text comes before the old */
                    memcpy(nr, removed, nremoved * sizeof(u16));
                    memcpy(nr + nremoved, t->removed, t->nremoved * sizeof(u16));
                    t->pos = pos;
                } else {                                      /* delete: after it */
                    memcpy(nr, t->removed, t->nremoved * sizeof(u16));
                    memcpy(nr + t->nremoved, removed, nremoved * sizeof(u16));
                }
                free(t->removed);
                t->removed = nr;
                t->nremoved += nremoved;
                u->units += nremoved;
                t->when = now_ms;
                t->serial = ++u->next_serial;
                return;
            }
        }
    }

    s.pos = pos;
    s.removed = dup16(removed, nremoved);   s.nremoved = nremoved;
    s.inserted = dup16(inserted, ninserted); s.ninserted = ninserted;
    s.when = now_ms;
    s.serial = ++u->next_serial;
    s.closed = 0;
    if ((nremoved && s.removed == NULL) || (ninserted && s.inserted == NULL) || !push(&u->undo_s, &u->nundo, &u->capundo, &s)) {
        step_free(&s);
        return;
    }
    u->units += step_units(&s);
    while (u->nundo > u->max_steps || (u->max_units > 0 && u->units > u->max_units && u->nundo > 1)) drop_oldest(u);
}

int undo_can_undo(const Undo *u) { return u->nundo > 0; }
int undo_can_redo(const Undo *u) { return u->nredo > 0; }

static void hand_out(Undo *u, Step *s, UndoStep *out)
{
    u->held = *s;
    u->have_held = 1;
    out->pos = u->held.pos;
    out->removed = u->held.removed;   out->nremoved = u->held.nremoved;
    out->inserted = u->held.inserted; out->ninserted = u->held.ninserted;
}

int undo_undo(Undo *u, UndoStep *step)
{
    Step s, copy;

    release_held(u);
    if (u->nundo == 0) return 0;
    s = u->undo_s[--u->nundo];
    u->units -= step_units(&s);
    copy = s;
    copy.removed = dup16(s.removed, s.nremoved);
    copy.inserted = dup16(s.inserted, s.ninserted);
    copy.closed = 1;
    if (!push(&u->redo_s, &u->nredo, &u->capredo, &copy)) step_free(&copy);
    hand_out(u, &s, step);
    return 1;
}

int undo_redo(Undo *u, UndoStep *step)
{
    Step s, copy;

    release_held(u);
    if (u->nredo == 0) return 0;
    s = u->redo_s[--u->nredo];
    copy = s;
    copy.removed = dup16(s.removed, s.nremoved);
    copy.inserted = dup16(s.inserted, s.ninserted);
    copy.closed = 1;
    if (!push(&u->undo_s, &u->nundo, &u->capundo, &copy)) step_free(&copy);
    else u->units += step_units(&copy);
    hand_out(u, &s, step);
    return 1;
}

unsigned long undo_version(const Undo *u)
{
    return u->nundo > 0 ? u->undo_s[u->nundo - 1].serial : 0;
}
