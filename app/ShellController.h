#import "Compat.h"

@class EditorDoc;

/* The Shell menu: run a command on the selection (or the whole text) and put the result back, or insert what a command
 * prints.  The command runs under /bin/sh, in the file's folder; the program waits for it, up to a minute. */
@interface ShellController : NSObject
{
    id          owner;                 /* the AppController: -frontDocument */
    NSPanel    *panel;                 /* the command dialog, while it is up */
    NSTextField *field;
    BOOL        accepted;
}
- (id)initWithOwner:(id)anOwner;
- (void)filterSelection;               /* Filter Selection...: the selection goes through the command and is replaced by its output */
- (void)executeCommand;                /* Execute Command...: its output goes in at the insertion point */
- (void)sortLines;
- (BOOL)macroFilter:(NSString *)command;     /* for macros: filter the selection through a command; NO if it failed */
- (BOOL)macroExecute:(NSString *)command;    /* ... or insert what a command prints */                     /* Filter Selection with `sort` */
@end
