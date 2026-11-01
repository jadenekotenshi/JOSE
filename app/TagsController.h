#import "Compat.h"

@class EditorDoc;

/* Tags: ctags files give the place where each name is defined.  Find Definition opens it (in a window of its own), Return from
 * Definition goes back, and a call tip -- the declaration line -- can be shown for the name before a typed `(`.  The tags file is
 * found by looking for a file called `tags` in the document's folder and the folders above it; others can be loaded by hand. */
@interface TagsController : NSObject
{
    id               owner;               /* the AppController: -frontDocument, -openPath: */
    NSMutableArray  *sets;                /* the tags files that are loaded */
    NSMutableArray  *jumps;               /* where Find Definition came from, to go back to */
    NSPanel         *tipPanel;
    NSTextField     *tipField;
    NSPopUpButton   *choice;              /* the chooser, while it is up */
    BOOL             chosen;
}
- (id)initWithOwner:(id)anOwner;
- (void)loadTagsFile;                     /* Load Tags File...: ask for one */
- (void)findDefinition;
- (void)returnFromDefinition;
- (void)showCallTip;                      /* for the name at the insertion point */
- (void)showCallTipAfterParenIn:(EditorDoc *)doc;   /* a `(` was just typed after a name */
- (void)hideCallTip;
- (NSArray *)completionNamesForPrefix:(NSString *)prefix document:(EditorDoc *)d max:(unsigned int)max;   /* tag names that start with it */
@end
