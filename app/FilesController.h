#import "Compat.h"

/* Search > Find in Files...: looks for text in the files of a folder (and its subfolders), lists the lines that match, and
 * replaces in all of them.  Double-clicking a line opens the file there.  A file that is open in a window is searched as it
 * stands in the window, and replaced there (an undoable step, not saved); the others are rewritten on disk, optionally keeping
 * the old file as name.bak.  Files that are not UTF-8 text, or that mix line endings, are never rewritten. */
@interface FilesController : NSObject
{
    id               owner;               /* the AppController: -frontDocument, -openPath:, -documentForPath: */
    NSPanel         *panel;
    NSTextField     *findField;
    NSTextField     *replaceField;
    NSTextField     *folderField;
    NSTextField     *patternField;
    NSButton        *caseSwitch;
    NSButton        *regexSwitch;
    NSButton        *wordSwitch;
    NSButton        *subSwitch;
    NSButton        *backupSwitch;
    NSTextField     *message;
    NSTableView     *table;
    NSMutableArray  *rowText;             /* what each row of the list shows */
    NSMutableArray  *rowPath;             /* the file of each row */
    NSMutableArray  *rowLine;             /* NSNumber: the line of each row */
    NSButton        *findButton;
    NSButton        *replaceButton;
    NSButton        *stopButton;
    NSModalSession   modalSession;        /* while a search or replacement runs, so that the panel (Stop) stays alive */
    BOOL             stopRequested;
    NSTimeInterval   lastPump;
    unsigned int     skippedFiles;        /* files left out of the last run (binary, not UTF-8, too big) */
}
- (id)initWithOwner:(id)anOwner;
- (void)showPanel;
@end
