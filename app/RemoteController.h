#import "Compat.h"

@class EditorDoc;

/* Remote editing: File > Open Remote... reads `[user@]host:path` by running  stepssh (or OpenSSH's ssh)  host 'cat path'  and opens
 * the text in a window of its own; Save writes it back the same way (to a temporary file first, then over the original, so a
 * broken connection never leaves half a file), after checking with `cksum` that the file has not changed on the other side since
 * it was read.  Which program runs, and where it is, is set in Preferences > Remote Editing.  The program must log in without
 * asking anything (a key; for OpenSSH an agent).  Only UTF-8 text is edited. */
@interface RemoteController : NSObject
{
    id          owner;                /* the AppController: -newDocument, -frontDocument */
    NSPanel    *dialogPanel;
    NSTextField *specField;
    NSMutableArray *recent;           /* the specs opened lately, newest first */
}
- (id)initWithOwner:(id)anOwner;
- (void)openDialog;                   /* ask for a name, then open it */
- (EditorDoc *)openSpec:(NSString *)spec;    /* nil (after telling the user why) if it could not be opened */
- (BOOL)saveDocument:(EditorDoc *)d;  /* YES if the text was written */
- (BOOL)reloadDocument:(EditorDoc *)d;
- (BOOL)remoteChanged:(EditorDoc *)d; /* the file on the other side is not what was read (NO if it cannot tell) */
@end
