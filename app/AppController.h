#import "Compat.h"
#include "modeprefs.h"

@class EditorDoc;
@class FindController;
@class ShellController;
@class PrefsController;
@class TagsController;
@class MacroController;
@class SessionController;
@class FilesController;
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
    PrefsController *prefs;
    TagsController *tags;
    MacroController *macros;
    FilesController *filesFinder;
    SessionController *sessions;
    NSMenu         *sessionOpenMenu;    /* File > Sessions > Open / Switch to / Delete */
    NSMenu         *sessionSwitchMenu;
    NSMenu         *sessionDeleteMenu;
    NSMenu         *macroRunMenu;       /* Macro > Run Macro */
    NSMenu         *macroEditMenu;      /* Macro > Edit Macro */
    NSMutableArray *recentFiles;        /* paths, most recent first */
    NSMenu         *recentMenu;         /* File > Open Recent */
    int             prefFillWidth;      /* the right margin of Fill Paragraph */
    BOOL            prefAutoIndent;     /* indentation settings, applied to every document */
    BOOL            prefUseSpaces;
    int             prefIndentWidth;
    BOOL            prefWrap;           /* the setting new windows start with */
    BOOL            prefLineNumbers;
    ModePrefs       modePrefs;          /* what each language mode overrides */
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
- (SessionController *)sessionController;
- (NSArray *)documents;                 /* every open document, oldest first */
- (EditorDoc *)documentForPath:(NSString *)path;   /* the window showing this file, or nil */
- (void)documentDidClose:(EditorDoc *)doc;
- (NSString *)syntaxDirectory;
- (void)noteRecentFile:(NSString *)path;  /* a file was opened or saved: it goes to the top of Open Recent */
- (NSArray *)modeNames;                 /* the syntax files' base names, sorted */
- (int)modeSetting:(int)which forMode:(NSString *)name;   /* MP_UNSET if the mode leaves it to the Preferences menu */
- (void)setModeSetting:(int)which value:(int)value forMode:(NSString *)name;   /* saved, and applied to the windows in that mode */
- (void)applyModePrefsTo:(EditorDoc *)d;   /* a document's mode was chosen: its settings, else the general ones */
- (FindController *)finder;
- (ShellController *)shellController;
- (BOOL)macroRecording;                 /* a macro is being learned */
- (BOOL)macroReplaying;
- (void)macroNoteInsert:(NSString *)text;           /* what is done while learning */
- (void)macroNoteAction:(NSString *)selectorName;
- (void)macroNoteFind:(NSString *)pattern flags:(NSString *)flags;
- (void)macroNoteReplace:(NSString *)verb pattern:(NSString *)pattern replacement:(NSString *)replacement flags:(NSString *)flags;
- (void)macroNoteFilter:(NSString *)verb command:(NSString *)command;
- (BOOL)macroIsRecordableAction:(NSString *)selectorName;
- (BOOL)macroCommand:(NSString *)name;             /* a menu command by its macro name */
- (void)hideCallTip;                    /* the call tip, if one is showing, goes away */
- (void)showCallTipAfterParenIn:(EditorDoc *)doc;
- (void)appearanceChanged;              /* the font or colours changed: every window shows them */
- (NSArray *)modeNames;                 /* the language modes available (sorted) */
@end
