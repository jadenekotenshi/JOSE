#import "Compat.h"

/* Saved sets of open files ("sessions"): File > Sessions.  A session is a small text file in ~/.JOSE.sessions holding, for each open
 * file, its caret, scroll position, window frame and wrap setting (see core/session.h).  The set of windows open now is also kept as
 * the "last session", so that it can be reopened -- by hand, or at launch if the preference says so.  Windows without a file are
 * not part of a session. */
@interface SessionController : NSObject
{
    id        owner;                  /* the AppController: -documents, -openPath: */
    NSString *folder;                 /* ~/.JOSE.sessions */
    NSString *current;                /* the name last saved or opened, which Save Session writes to */
    BOOL      quiet;                  /* while a session is being opened or the program is quitting: do not record the windows */
}
- (id)initWithOwner:(id)anOwner;
- (NSArray *)savedNames;              /* sorted */
- (NSString *)currentName;
- (BOOL)saveAs:(NSString *)name;      /* the open windows that have files; NO if the name is bad or there are none */
- (BOOL)save;                         /* under the current name; NO if there is none */
- (void)recordLast;                   /* the open windows become the "last session" (quietly; nothing when there are none) */
- (BOOL)hasLast;
- (BOOL)open:(NSString *)name replace:(BOOL)replace;   /* replace: windows that are not in it are closed first (asking about unsaved work) */
- (BOOL)openLast;                     /* YES if some file was opened */
- (BOOL)deleteNamed:(NSString *)name;
- (void)setQuiet:(BOOL)flag;
- (void)setFolderPath:(NSString *)path;   /* where sessions are kept (for tests) */
- (unsigned int)missingCount;         /* files the last open could not find */
@end
