#ifndef UNDO_H
#define UNDO_H

/* An undo/redo history of text edits, in UTF-16 units (NSString's unichar).  Each edit replaces `nremoved` units at `pos`
 * with `ninserted` units; typing and deleting a character at a time are merged into one step.  Plain C so that it can be
 * tested on the host. */

#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;
#endif

typedef struct Undo Undo;

typedef struct {
    unsigned pos;
    const u16 *removed;  unsigned nremoved;     /* what the edit took out (valid until the next call on the history) */
    const u16 *inserted; unsigned ninserted;    /* what it put in */
} UndoStep;

/* max_steps: how many steps are kept; max_units: how many text units all the steps may hold together (the oldest go first). */
Undo *undo_new(unsigned max_steps, unsigned long max_units);
void undo_free(Undo *u);

/* Records an edit that is about to happen or has happened.  `now_ms` (any increasing clock, in milliseconds) lets edits made
 * close together merge; pass the same value for edits that should always merge.  Clears the redo history. */
void undo_record(Undo *u, unsigned pos, const u16 *removed, unsigned nremoved, const u16 *inserted, unsigned ninserted,
                 unsigned long now_ms);

/* Ends the current step: the next edit starts a new one (call when the cursor jumps, on a save, ...). */
void undo_break(Undo *u);

int undo_can_undo(const Undo *u);
int undo_can_redo(const Undo *u);

/* Takes the newest step off the history and describes how to undo it: replace the `ninserted` units at `pos` with `removed`.
 * Returns 0 if there is nothing to undo.  The step moves to the redo history. */
int undo_undo(Undo *u, UndoStep *step);

/* The reverse: replace the `nremoved` units at `pos` with `inserted`. */
int undo_redo(Undo *u, UndoStep *step);

/* A number that identifies the state of the text: it returns to an earlier value when edits are undone back to that state.
 * `undo_version` after a save is what to compare against to know whether the text has changed since. */
unsigned long undo_version(const Undo *u);

void undo_clear(Undo *u);

#endif
