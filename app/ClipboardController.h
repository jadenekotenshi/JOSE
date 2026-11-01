#import "Compat.h"
#include "cliphist.h"

/* The clipboard history: what was cut or copied in Pilcrow (and, whenever Pilcrow becomes the active program again, what was copied
 * elsewhere), the last thirty, newest first.  Edit > Paste from History pastes one and makes it the current clipboard; the Clipboard
 * History panel lists them whole.  Kept in memory only. */
@interface ClipboardController : NSObject
{
    id            owner;               /* the AppController: -frontDocument, -clipboardHistoryChanged */
    ClipRing      ring;
    int           lastChange;          /* the pasteboard's change count when last looked at (-1 if it has none) */
    NSPanel      *panel;
    NSTableView  *table;
    NSTextField  *detail;
}
- (id)initWithOwner:(id)anOwner;
- (void)note;                          /* look at the clipboard: if there is new text, it joins the history */
- (int)count;
- (NSString *)previewAt:(int)i;        /* one line to choose by */
- (BOOL)makeCurrent:(int)i;            /* the entry becomes the clipboard (a rectangle stays a rectangle); NO if there is none */
- (void)pasteEntry:(int)i;             /* make it current and paste it into the front document */
- (void)showPanel;
@end
