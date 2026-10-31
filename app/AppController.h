#import "Compat.h"

@class EditorDoc;
@class FindController;
@class ShellController;

/* Owns every open document and the menus. */
@interface AppController : NSObject
{
    NSMutableArray *docs;              /* EditorDoc* */
    NSMutableArray *menuKeepers;       /* every menu made, held for the life of the program (see -keepMenu:) */
    NSMenu         *modeMenu;          /* Language Mode */
    NSString       *syntaxDir;         /* where the .syntax files are */
    NSTextField    *gotoField;
    FindController *finder;
    ShellController *shell;
    int             prefFillWidth;      /* the right margin of Fill Paragraph */
    BOOL            prefAutoIndent;     /* indentation settings, applied to every document */
    BOOL            prefUseSpaces;
    int             prefIndentWidth;
    BOOL            prefWrap;           /* the setting new windows start with */
    BOOL            prefLineNumbers;
    BOOL            launched;
    NSMutableArray *startupFiles;      /* named on the command line; opened once the event loop runs */
}
- (int)menuCount;
- (void)buildMenu;                      /* before the application runs: only a minimal menu (Quit), quickly */
- (void)buildFullMenu;                  /* the real menus, once the application is running */
- (EditorDoc *)newDocument;
- (void)openAtLaunch:(NSString *)path;
- (EditorDoc *)openPath:(NSString *)path;
- (EditorDoc *)frontDocument;
- (void)documentDidClose:(EditorDoc *)doc;
- (NSString *)syntaxDirectory;
- (NSArray *)modeNames;                 /* the language modes available (sorted) */
@end
