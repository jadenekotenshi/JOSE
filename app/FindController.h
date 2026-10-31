#import "Compat.h"
#include "search.h"

@class EditorDoc;

/* The Find and Replace panel, and the searches behind the Search menu.  It works on whichever document the owner says is in
 * front. */
@interface FindController : NSObject
{
    id           owner;                /* the AppController: -frontDocument */
    NSPanel     *panel;
    NSTextField *findField;
    NSTextField *replaceField;
    NSButton    *caseSwitch;
    NSButton    *regexSwitch;
    NSButton    *wordSwitch;
    NSButton    *wrapSwitch;
    NSTextField *message;
    Search      *cached;               /* the compiled form of cachedPattern/cachedFlags */
    NSString    *cachedPattern;
    int          cachedFlags;
    BOOL         lastOK;               /* the last search or replacement found something */
}
- (id)initWithOwner:(id)anOwner;
- (void)showPanel;                      /* Find... / Replace... */
- (void)findAgain;                      /* Find Again: forward, with what the panel holds */
- (void)findPrevious;
- (void)findSelection;
- (BOOL)macroFind:(NSString *)pattern flags:(NSString *)flags;      /* for macros: search with these settings (see core/macro.h); NO if nothing is found */
- (BOOL)macroReplaceKind:(int)kind pattern:(NSString *)pattern replacement:(NSString *)replacement flags:(NSString *)flags;   /* kind 0 replace, 1 all, 2 in the selection */                  /* use the selected text as the search text, and find the next */
@end
