#ifndef MODEPREFS_H
#define MODEPREFS_H

/* Per-language-mode settings: a mode (Python, Makefile ...) may override the indentation width, tabs or spaces, auto indent
 * and line wrapping that the Preferences menu sets for everything.  Plain C so that the parsing and the text form can be
 * tested on the host.  The saved form is one line per mode:  Python indent=4 spaces=1 auto=1 wrap=0  (a setting that is not
 * overridden is left out). */

#define MP_MAX_MODES 64
#define MP_NAME_SIZE 40
#define MP_UNSET (-1)

enum { MP_INDENT, MP_SPACES, MP_AUTO, MP_WRAP, MP_COUNT };

typedef struct {
    char name[MP_NAME_SIZE];
    int  v[MP_COUNT];                  /* MP_UNSET, or the value (a width, or 0/1) */
} ModeEntry;

typedef struct {
    ModeEntry e[MP_MAX_MODES];
    int       n;
} ModePrefs;

void modeprefs_clear(ModePrefs *mp);
void modeprefs_parse(ModePrefs *mp, const char *text);                  /* replaces the contents; bad lines are skipped */
unsigned modeprefs_format(const ModePrefs *mp, char *out, unsigned cap);   /* NUL-terminated; returns the length (or the length needed, if cap was too small) */
const ModeEntry *modeprefs_find(const ModePrefs *mp, const char *name);   /* NULL if the mode overrides nothing */
int modeprefs_get(const ModePrefs *mp, const char *name, int which);       /* MP_UNSET if not overridden */
int modeprefs_set(ModePrefs *mp, const char *name, int which, int value);  /* MP_UNSET removes; 0 on success, -1 if invalid or full */

#endif
