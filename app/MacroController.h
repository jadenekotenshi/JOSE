#import "Compat.h"

@class EditorDoc;

/* Macros: learn what is done in a window and replay it.  What is learned is a list of lines in the macro language of
 * core/macro.h (typed text, key actions, menu commands, searches), which can be saved under a name, shown as text, edited,
 * and run again from a window's text.  Nothing is learned from the mouse. */
@interface MacroController : NSObject
{
    id               owner;              /* the AppController */
    BOOL             recording;
    BOOL             replaying;
    NSMutableArray  *lines;              /* what has been learned so far */
    NSMutableString *pendingInsert;      /* typed text not yet turned into a line (consecutive keys make one insert) */
    NSArray         *last;               /* the last complete macro */
    NSString        *folder;             /* where the saved macros are */
    NSPanel         *repeatPanel;
    NSTextField     *repeatField;
    NSButton        *untilSwitch;
    BOOL             accepted;
}
- (id)initWithOwner:(id)anOwner;
- (BOOL)recording;
- (BOOL)replaying;
- (BOOL)hasMacro;                        /* there is a macro to replay */
- (void)toggleLearning;                  /* Learn Macro / Stop Learning */

/* What the rest of the program tells it as things happen (ignored unless a macro is being learned). */
- (void)noteInsert:(NSString *)text;
- (void)noteAction:(NSString *)selectorName;
- (void)noteCommand:(NSString *)name;
- (void)noteFind:(NSString *)pattern flags:(NSString *)flags;
- (void)noteReplace:(NSString *)verb pattern:(NSString *)pattern replacement:(NSString *)replacement flags:(NSString *)flags;
- (void)noteFilter:(NSString *)verb command:(NSString *)command;
- (BOOL)isRecordableAction:(NSString *)selectorName;

- (BOOL)replay;                          /* once, in the front window; NO if it stopped early */
- (void)repeatDialog;                    /* Repeat Macro...: n times, or until it fails */
- (BOOL)runLines:(NSArray *)macroLines;  /* any list of macro lines in the front window */
- (NSString *)lastAsText;

- (NSArray *)savedNames;                 /* the saved macros, sorted */
- (BOOL)saveLastAs:(NSString *)name;
- (BOOL)runSaved:(NSString *)name;
- (NSString *)folderPath;
- (void)setFolderPath:(NSString *)path;   /* where saved macros go (the tests use a folder of their own) */
@end
