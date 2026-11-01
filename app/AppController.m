#import "AppController.h"
#import "EditorDoc.h"
#import "FindController.h"
#import "ShellController.h"
#import "PrefsController.h"
#import "TagsController.h"
#import "MacroController.h"
#import "FilesController.h"
#import "SessionController.h"
#import "Appearance.h"
#import "UIHelpers.h"
#import "HKSyntaxDefinition.h"
#include "includes.h"
#include "langmodes.h"

#define TAG_MODE_BASE 1000             /* the Language Mode items: the tag is this plus the mode's index; plain text is TAG_MODE_BASE - 1 */

@interface AppController (Private)
- (void)loadPreferences;
- (void)savePreferences;
- (MacroController *)macroController;
- (void)macroNote:(NSString *)name;
- (void)rebuildMacroMenus;
- (void)rebuildSessionMenus;
- (NSString *)askName:(NSString *)title;
- (void)loadRecent;
- (void)saveRecent;
- (void)rebuildRecentMenu;
- (void)applyIndentPrefsTo:(EditorDoc *)d;
- (void)applyIndentPrefs;
- (id)addItem:(NSString *)title action:(SEL)action key:(NSString *)key target:(id)target toMenu:(NSMenu *)menu;
- (NSMenu *)keepMenu:(NSMenu *)menu;
- (NSMenu *)submenuNamed:(NSString *)title inMenu:(NSMenu *)parent;
@end

@implementation AppController

- (id)init
{
    self = [super init];
    if (self) {
        docs = [[NSMutableArray alloc] init];
        [self loadPreferences];
        [self loadRecent];
        menuKeepers = [[NSMutableArray alloc] init];
        syntaxDir = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"syntax"];
        [syntaxDir retain];
        [HKSyntaxDefinition setSyntaxDirectory:syntaxDir];
    }
    return self;
}

/* ---- saved preferences (NSUserDefaults, as strings: the one form every release of it reads back alike) ---- */

static BOOL pref_bool(NSUserDefaults *ud, NSString *key, BOOL def)
{
    NSString *v = [ud stringForKey:key];

    return v == nil ? def : [v isEqualToString:@"YES"];
}

static void set_pref_bool(NSUserDefaults *ud, NSString *key, BOOL value)
{
    [ud setObject:(value ? @"YES" : @"NO") forKey:key];
}

- (void)loadPreferences
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *w = [ud stringForKey:@"IndentWidth"];

    prefAutoIndent = pref_bool(ud, @"AutoIndent", YES);
    prefUseSpaces = pref_bool(ud, @"UseSpaces", NO);
    prefIndentWidth = w != nil ? [w intValue] : 4;
    if (prefIndentWidth < 1 || prefIndentWidth > 16) prefIndentWidth = 4;
    prefWrap = pref_bool(ud, @"WrapLines", NO);
    prefLineNumbers = pref_bool(ud, @"LineNumbers", NO);
    w = [ud stringForKey:@"FillWidth"];
    prefFillWidth = w != nil ? [w intValue] : 72;
    if (prefFillWidth < 20 || prefFillWidth > 200) prefFillWidth = 72;
    [Appearance loadSettings];
    w = [ud stringForKey:@"ModePrefs"];
    modeprefs_parse(&modePrefs, w != nil ? UI_CPATH(w) : "");
}

- (void)savePreferences
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    set_pref_bool(ud, @"AutoIndent", prefAutoIndent);
    set_pref_bool(ud, @"UseSpaces", prefUseSpaces);
    [ud setObject:[NSString stringWithFormat:@"%d", prefIndentWidth] forKey:@"IndentWidth"];
    set_pref_bool(ud, @"WrapLines", prefWrap);
    set_pref_bool(ud, @"LineNumbers", prefLineNumbers);
    [ud setObject:[NSString stringWithFormat:@"%d", prefFillWidth] forKey:@"FillWidth"];
    {
        char buf[MP_MAX_MODES * 160];

        modeprefs_format(&modePrefs, buf, sizeof buf);
        [ud setObject:[NSString stringWithCString:buf] forKey:@"ModePrefs"];
    }
    [ud synchronize];
}

/* ---- recent files ---- */

#define MAX_RECENT 12

- (void)loadRecent
{
    NSString *v = [[NSUserDefaults standardUserDefaults] stringForKey:@"RecentFiles"];
    NSArray *parts = v != nil ? [v componentsSeparatedByString:@"\n"] : [NSArray array];
    unsigned int i;

    recentFiles = [[NSMutableArray alloc] init];
    for (i = 0; i < [parts count] && [recentFiles count] < MAX_RECENT; i++)
        if ([[parts objectAtIndex:i] length] > 0) [recentFiles addObject:[parts objectAtIndex:i]];
}

- (void)saveRecent
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    [ud setObject:[recentFiles componentsJoinedByString:@"\n"] forKey:@"RecentFiles"];
    [ud synchronize];
}

- (void)openRecent:(id)sender
{
    int i = [sender tag];
    NSString *p;

    if (i < 0 || i >= (int)[recentFiles count]) return;
    p = [[[recentFiles objectAtIndex:i] retain] autorelease];
    if (![[NSFileManager defaultManager] isReadableFileAtPath:p]) {
        NSRunAlertPanel(@"Open Recent", @"%@ is no longer there.", @"OK", nil, nil, p);
        [recentFiles removeObjectAtIndex:i];
        [self saveRecent];
        [self rebuildRecentMenu];
        return;
    }
    [self openPath:p];
}

- (void)clearRecent:(id)sender
{
    [recentFiles removeAllObjects];
    [self saveRecent];
    [self rebuildRecentMenu];
}

- (void)rebuildRecentMenu
{
    unsigned int i;

    if (recentMenu == nil) return;
    NS_DURING
        /* OPENSTEP 4.2's NSMenu has itemArray and removeItem: but no numberOfItems or removeItemAtIndex: */
        NSArray *old = [NSArray arrayWithArray:[recentMenu itemArray]];
        for (i = 0; i < [old count]; i++) [recentMenu removeItem:[old objectAtIndex:i]];
        for (i = 0; i < [recentFiles count]; i++) {
            NSString *p = [recentFiles objectAtIndex:i];
            NSString *title = [NSString stringWithFormat:@"%@  (%@)", [p lastPathComponent],
                               [[p stringByDeletingLastPathComponent] stringByAbbreviatingWithTildeInPath]];
            [[self addItem:title action:@selector(openRecent:) key:@"" target:self toMenu:recentMenu] setTag:(int)i];
        }
        if ([recentFiles count] > 0) [self addItem:@"Clear Menu" action:@selector(clearRecent:) key:@"" target:self toMenu:recentMenu];
        else [[self addItem:@"(none)" action:NULL key:@"" target:self toMenu:recentMenu] setEnabled:NO];
        if ([recentMenu respondsToSelector:@selector(sizeToFit)]) [recentMenu sizeToFit];
    NS_HANDLER
        SSTrace("Open Recent menu: %s -- %s", SSCS([localException name]), SSCS([localException reason]));
    NS_ENDHANDLER
}

- (void)noteRecentFile:(NSString *)path
{
    if (path == nil) return;
    path = [path stringByStandardizingPath];
    [[path retain] autorelease];
    [recentFiles removeObject:path];
    [recentFiles insertObject:path atIndex:0];
    while ([recentFiles count] > MAX_RECENT) [recentFiles removeLastObject];
    [self saveRecent];
    [self rebuildRecentMenu];
}

- (id)addItem:(NSString *)title action:(SEL)action key:(NSString *)key
       target:(id)target toMenu:(NSMenu *)menu
{
    id item = [menu addItemWithTitle:title action:action keyEquivalent:key];
    if (target) [item setTarget:target];
    return item;
}

/* This AppKit does not keep the menus it is given (see StepHack's AppController): every menu is held for the life of the program. */
- (NSMenu *)keepMenu:(NSMenu *)menu
{
    [menuKeepers addObject:menu];
    return menu;
}

- (int)menuCount { return (int)[menuKeepers count]; }

- (NSMenu *)submenuNamed:(NSString *)title inMenu:(NSMenu *)parent
{
    NSMenu *sub = [[NSMenu alloc] initWithTitle:title];
    id item = [parent addItemWithTitle:title action:NULL keyEquivalent:@""];
    [parent setSubmenu:sub forItem:item];
    [self keepMenu:sub];
    return [sub autorelease];
}

- (NSString *)syntaxDirectory { return syntaxDir; }

- (NSArray *)modeNames
{
    NSArray *files = [[NSFileManager defaultManager] directoryContentsAtPath:syntaxDir];
    NSMutableArray *names = [NSMutableArray array];
    unsigned int i;

    for (i = 0; i < [files count]; i++) {
        NSString *f = [files objectAtIndex:i];
        if ([[f pathExtension] isEqualToString:@"syntax"]) [names addObject:[f stringByDeletingPathExtension]];
    }
    return [names sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
}

/* ---- menus ---- */

- (void)buildMenu
{
    NSMenu *main;
    id item;

    main = [self keepMenu:[[[NSMenu alloc] initWithTitle:@"JOSE"] autorelease]];
    item = [main addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    [item setTarget:NSApp];
    [NSApp setMainMenu:main];
}

- (void)buildFullMenu
{
    NSMenu *main = [self keepMenu:[[[NSMenu alloc] initWithTitle:@"JOSE"] autorelease]];
    NSMenu *m;
    NSArray *names;
    unsigned int i;
    id item;

    m = [self submenuNamed:@"Info" inMenu:main];
    [self addItem:@"Info Panel..." action:@selector(showAbout:) key:@"" target:self toMenu:m];

    m = [self submenuNamed:@"File" inMenu:main];
    [self addItem:@"New" action:@selector(newDoc:) key:@"n" target:self toMenu:m];
    [self addItem:@"Open..." action:@selector(openDoc:) key:@"o" target:self toMenu:m];
    recentMenu = [self submenuNamed:@"Open Recent" inMenu:m];
    [self rebuildRecentMenu];
    {
        NSMenu *sm = [self submenuNamed:@"Sessions" inMenu:m];

        [self addItem:@"Save Session As..." action:@selector(saveSessionAs:) key:@"" target:self toMenu:sm];
        [self addItem:@"Save Session" action:@selector(saveSession:) key:@"" target:self toMenu:sm];
        [self addItem:@"Reopen Last Session" action:@selector(reopenLastSession:) key:@"" target:self toMenu:sm];
        sessionOpenMenu = [self submenuNamed:@"Open Session" inMenu:sm];
        sessionSwitchMenu = [self submenuNamed:@"Switch to Session" inMenu:sm];
        sessionDeleteMenu = [self submenuNamed:@"Delete Session" inMenu:sm];
        [self rebuildSessionMenus];
    }
    [self addItem:@"Open Included File" action:@selector(openIncluded:) key:@"d" target:self toMenu:m];
    [self addItem:@"Save" action:@selector(saveDoc:) key:@"s" target:self toMenu:m];
    [self addItem:@"Save As..." action:@selector(saveDocAs:) key:@"S" target:self toMenu:m];
    [self addItem:@"Revert to Saved" action:@selector(revertDoc:) key:@"" target:self toMenu:m];
    [self addItem:@"Close" action:@selector(closeDoc:) key:@"w" target:self toMenu:m];

    m = [self submenuNamed:@"Edit" inMenu:main];
    [self addItem:@"Undo" action:@selector(undoDoc:) key:@"z" target:self toMenu:m];
    [self addItem:@"Redo" action:@selector(redoDoc:) key:@"Z" target:self toMenu:m];
    [self addItem:@"Cut" action:@selector(cut:) key:@"x" target:nil toMenu:m];
    [self addItem:@"Copy" action:@selector(copy:) key:@"c" target:nil toMenu:m];
    [self addItem:@"Paste" action:@selector(paste:) key:@"v" target:nil toMenu:m];
    [self addItem:@"Delete" action:@selector(delete:) key:@"" target:nil toMenu:m];
    [self addItem:@"Select All" action:@selector(selectAll:) key:@"a" target:nil toMenu:m];
    [self addItem:@"Shift Left" action:@selector(shiftLeft:) key:@"[" target:self toMenu:m];
    [self addItem:@"Shift Right" action:@selector(shiftRight:) key:@"]" target:self toMenu:m];
    [self addItem:@"Comment" action:@selector(commentLines:) key:@"/" target:self toMenu:m];
    [self addItem:@"Uncomment" action:@selector(uncommentLines:) key:@"\\" target:self toMenu:m];
    [self addItem:@"Fill Paragraph" action:@selector(fillParagraph:) key:@"j" target:self toMenu:m];
    [self addItem:@"Fold/Unfold Block" action:@selector(toggleFold:) key:@"k" target:self toMenu:m];
    [self addItem:@"Fold All Blocks" action:@selector(foldAll:) key:@"" target:self toMenu:m];
    [self addItem:@"Expand All Blocks" action:@selector(expandAll:) key:@"" target:self toMenu:m];

    m = [self submenuNamed:@"Search" inMenu:main];
    [self addItem:@"Find..." action:@selector(showFind:) key:@"f" target:self toMenu:m];
    [self addItem:@"Find Again" action:@selector(findAgain:) key:@"g" target:self toMenu:m];
    [self addItem:@"Find Previous" action:@selector(findPrevious:) key:@"G" target:self toMenu:m];
    [self addItem:@"Find Selection" action:@selector(findSelection:) key:@"e" target:self toMenu:m];
    [self addItem:@"Replace..." action:@selector(showFind:) key:@"r" target:self toMenu:m];
    [self addItem:@"Find in Files..." action:@selector(showFiles:) key:@"F" target:self toMenu:m];
    [self addItem:@"Go to Matching Bracket" action:@selector(gotoBracket:) key:@"b" target:self toMenu:m];
    [self addItem:@"Select to Matching Bracket" action:@selector(selectBracket:) key:@"B" target:self toMenu:m];
    [self addItem:@"Find Unmatched Bracket / Keyword" action:@selector(findUnmatched:) key:@"u" target:self toMenu:m];
    [self addItem:@"Go to Line..." action:@selector(gotoLine:) key:@"l" target:self toMenu:m];
    [self addItem:@"Find Definition" action:@selector(findDefinition:) key:@"t" target:self toMenu:m];
    [self addItem:@"Return from Definition" action:@selector(returnFromDefinition:) key:@"T" target:self toMenu:m];
    [self addItem:@"Show Call Tip" action:@selector(showCallTip:) key:@"9" target:self toMenu:m];
    [self addItem:@"Load Tags File..." action:@selector(loadTags:) key:@"" target:self toMenu:m];

    m = [self submenuNamed:@"Preferences" inMenu:main];
    [self addItem:@"Preferences Panel..." action:@selector(showPrefs:) key:@"," target:self toMenu:m];
    [[self addItem:@"Wrap Lines" action:@selector(toggleWrap:) key:@"" target:self toMenu:m] setTag:1];
    [self addItem:@"Line Numbers" action:@selector(toggleLineNumbers:) key:@"" target:self toMenu:m];
    [self addItem:@"Auto Indent" action:@selector(toggleAutoIndent:) key:@"" target:self toMenu:m];
    [self addItem:@"Spaces for Indentation" action:@selector(toggleUseSpaces:) key:@"" target:self toMenu:m];
    {
        NSMenu *wm = [self submenuNamed:@"Indent Width" inMenu:m];
        static const int widths[] = { 2, 3, 4, 8 };
        int wi;
        for (wi = 0; wi < 4; wi++) {
            NSString *t = [NSString stringWithFormat:@"%d", widths[wi]];
            [[self addItem:t action:@selector(setIndentWidth:) key:@"" target:self toMenu:wm] setTag:widths[wi]];
        }
    }
    {
        NSMenu *fm = [self submenuNamed:@"Fill Width" inMenu:m];
        static const int fills[] = { 60, 66, 72, 76, 79, 100 };
        int fi;
        for (fi = 0; fi < 6; fi++) {
            NSString *t = [NSString stringWithFormat:@"%d", fills[fi]];
            [[self addItem:t action:@selector(setFillWidth:) key:@"" target:self toMenu:fm] setTag:fills[fi]];
        }
    }
    modeMenu = [self submenuNamed:@"Language Mode" inMenu:m];
    item = [self addItem:@"Plain Text" action:@selector(setMode:) key:@"" target:self toMenu:modeMenu];
    [item setTag:TAG_MODE_BASE - 1];
    names = [self modeNames];
    for (i = 0; i < [names count]; i++) {
        item = [self addItem:[names objectAtIndex:i] action:@selector(setMode:) key:@"" target:self toMenu:modeMenu];
        [item setTag:TAG_MODE_BASE + (int)i];
    }

    m = [self submenuNamed:@"Shell" inMenu:main];
    [self addItem:@"Filter Selection..." action:@selector(filterSelection:) key:@"|" target:self toMenu:m];
    [self addItem:@"Execute Command..." action:@selector(executeCommand:) key:@"!" target:self toMenu:m];
    [self addItem:@"Sort Lines" action:@selector(sortLines:) key:@"" target:self toMenu:m];

    m = [self submenuNamed:@"Macro" inMenu:main];
    [self addItem:@"Learn Macro" action:@selector(learnMacro:) key:@"L" target:self toMenu:m];
    [self addItem:@"Replay Macro" action:@selector(replayMacro:) key:@"y" target:self toMenu:m];
    [self addItem:@"Repeat Macro..." action:@selector(repeatMacro:) key:@"Y" target:self toMenu:m];
    [self addItem:@"Save Macro As..." action:@selector(saveMacro:) key:@"" target:self toMenu:m];
    macroRunMenu = [self submenuNamed:@"Run Macro" inMenu:m];
    macroEditMenu = [self submenuNamed:@"Edit Macro" inMenu:m];
    [self addItem:@"Macro as Text" action:@selector(macroAsText:) key:@"" target:self toMenu:m];
    [self rebuildMacroMenus];

    m = [self submenuNamed:@"Windows" inMenu:main];
    [self addItem:@"Arrange in Front" action:@selector(arrangeInFront:) key:@"" target:nil toMenu:m];
    [self addItem:@"Miniaturize Window" action:@selector(performMiniaturize:) key:@"m" target:nil toMenu:m];
    [self addItem:@"Split Pane" action:@selector(splitPane:) key:@"2" target:self toMenu:m];
    [self addItem:@"Close Pane" action:@selector(closePane:) key:@"1" target:self toMenu:m];
    [NSApp setWindowsMenu:m];

    m = [self submenuNamed:@"Services" inMenu:main];
    [NSApp setServicesMenu:m];

    [self addItem:@"Hide" action:@selector(hide:) key:@"h" target:NSApp toMenu:main];
    [self addItem:@"Quit" action:@selector(terminate:) key:@"q" target:NSApp toMenu:main];
    [NSApp setMainMenu:main];
}

/* The document being worked on: the key window's, or, when a panel (Find) is the key window, the main window's. */
- (EditorDoc *)documentForWindow:(NSWindow *)w
{
    unsigned int i;

    if (w == nil) return nil;
    for (i = 0; i < [docs count]; i++)
        if ([[docs objectAtIndex:i] window] == w) return [docs objectAtIndex:i];
    return nil;
}

- (EditorDoc *)frontDocument
{
    EditorDoc *d = [self documentForWindow:[NSApp keyWindow]];

    if (d == nil) d = [self documentForWindow:[NSApp mainWindow]];
    return d;
}

- (BOOL)validateMenuItem:(id)item
{
    EditorDoc *d = [self frontDocument];
    SEL a = [item action];
    int tag = [item tag];

    if (a == @selector(saveDoc:) || a == @selector(openIncluded:) || a == @selector(findDefinition:) || a == @selector(returnFromDefinition:) || a == @selector(showCallTip:) || a == @selector(saveDocAs:) || a == @selector(closeDoc:) || a == @selector(gotoLine:) || a == @selector(showFind:) || a == @selector(findAgain:)
        || a == @selector(findPrevious:) || a == @selector(findSelection:)
        || a == @selector(toggleWrap:) || a == @selector(setMode:)
        || a == @selector(findUnmatched:) || a == @selector(gotoBracket:) || a == @selector(selectBracket:) || a == @selector(shiftLeft:) || a == @selector(shiftRight:) || a == @selector(commentLines:) || a == @selector(uncommentLines:)
        || a == @selector(fillParagraph:) || a == @selector(toggleFold:) || a == @selector(foldAll:) || a == @selector(expandAll:) || a == @selector(filterSelection:) || a == @selector(executeCommand:) || a == @selector(sortLines:))
        if (d == nil) return NO;
    if (a == @selector(saveSession:)) return [[self sessionController] currentName] != nil;
    if (a == @selector(reopenLastSession:)) return [[self sessionController] hasLast];
    if (a == @selector(splitPane:)) return d != nil && ![d hasSplit];
    if (a == @selector(closePane:)) return d != nil && [d hasSplit];
    if (a == @selector(learnMacro:)) {
        BOOL rec = [self macroRecording];
        [item setTitle:rec ? @"Stop Learning" : @"Learn Macro"];
        return d != nil || rec;
    }
    if (a == @selector(replayMacro:) || a == @selector(repeatMacro:))
        return d != nil && ![self macroRecording] && [[self macroController] hasMacro];
    if (a == @selector(saveMacro:) || a == @selector(macroAsText:))
        return ![self macroRecording] && [[self macroController] hasMacro];
    if (a == @selector(runSavedMacro:)) return d != nil && ![self macroRecording];
    if (a == @selector(setFillWidth:)) [item setState:tag == prefFillWidth ? NSOnState : NSOffState];
    if (a == @selector(toggleLineNumbers:)) [item setState:prefLineNumbers ? NSOnState : NSOffState];
    if (a == @selector(toggleAutoIndent:)) [item setState:prefAutoIndent ? NSOnState : NSOffState];
    if (a == @selector(toggleUseSpaces:)) [item setState:prefUseSpaces ? NSOnState : NSOffState];
    if (a == @selector(setIndentWidth:)) [item setState:tag == prefIndentWidth ? NSOnState : NSOffState];
    if (a == @selector(undoDoc:)) return d != nil && [d canUndo];
    if (a == @selector(redoDoc:)) return d != nil && [d canRedo];
    if (a == @selector(revertDoc:)) return d != nil && [d path] != nil;
    if (a == @selector(toggleWrap:)) [item setState:(d != nil && [d wrap]) ? NSOnState : NSOffState];
    if (a == @selector(setMode:)) {
        NSString *m = [d mode];
        BOOL on = (tag == TAG_MODE_BASE - 1) ? (m == nil) : (m != nil && [m isEqualToString:[item title]]);
        [item setState:on ? NSOnState : NSOffState];
    }
    return YES;
}

/* ---- documents ---- */

- (EditorDoc *)newDocument
{
    EditorDoc *d = [[EditorDoc alloc] initWithOwner:self];

    [self applyIndentPrefsTo:d];
    [d setWrap:prefWrap];
    [docs addObject:d];
    [d release];
    [d showWindow];
    return d;
}

- (EditorDoc *)openPath:(NSString *)path
{
    unsigned int i;
    EditorDoc *d;

    path = [path stringByStandardizingPath];
    for (i = 0; i < [docs count]; i++) {                       /* already open: bring it forward */
        d = [docs objectAtIndex:i];
        if ([d path] != nil && [[d path] isEqualToString:path]) { [d showWindow]; return d; }
    }
    d = [[EditorDoc alloc] initWithOwner:self];
    [self applyIndentPrefsTo:d];
    [d setWrap:prefWrap];
    if (![d openFile:path]) { [d release]; return nil; }
    [docs addObject:d];
    [d release];
    [d showWindow];
    [self noteRecentFile:path];
    [[self sessionController] recordLast];
    return d;
}

- (void)documentDidClose:(EditorDoc *)doc
{
    [[doc retain] autorelease];                                  /* the window is still telling us it is closing */
    [self hideCallTip];
    [docs removeObject:doc];
    [[self sessionController] recordLast];
}

- (void)newDoc:(id)sender { [self newDocument]; }

- (void)openDoc:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    unsigned int i;
    NSArray *files;

    [panel setAllowsMultipleSelection:YES];
    if ([panel runModalForDirectory:NSHomeDirectory() file:nil types:nil] != NSOKButton) return;
    files = [panel filenames];
    for (i = 0; i < [files count]; i++) [self openPath:[files objectAtIndex:i]];
}

- (void)saveDoc:(id)sender { [[self frontDocument] save]; }
- (void)saveDocAs:(id)sender { [[self frontDocument] saveAs]; }

- (void)revertDoc:(id)sender
{
    EditorDoc *d = [self frontDocument];

    if (d == nil || [d path] == nil) return;
    if ([d isDirty] && NSRunAlertPanel(@"Revert", @"Discard the changes to %@?", @"Revert", @"Cancel", nil,
                                        [[d path] lastPathComponent]) != NSAlertDefaultReturn) return;
    [d revert];
}

- (void)undoDoc:(id)sender { [self macroNote:@"undo"]; [[self frontDocument] undo]; }
- (void)redoDoc:(id)sender { [self macroNote:@"redo"]; [[self frontDocument] redo]; }
- (void)closeDoc:(id)sender { [[self frontDocument] closeWindow]; }

- (void)setMode:(id)sender
{
    EditorDoc *d = [self frontDocument];
    int tag = [sender tag];

    if (d == nil) return;
    [d setMode:(tag == TAG_MODE_BASE - 1) ? nil : [sender title]];
    [self applyModePrefsTo:d];
}

/* The value of a setting for a document: what its language mode overrides, else the general preference. */
- (int)effectiveSetting:(int)which for:(EditorDoc *)d
{
    int v = [d mode] != nil ? modeprefs_get(&modePrefs, UI_CPATH([d mode]), which) : MP_UNSET;

    if (v != MP_UNSET) return v;
    switch (which) {
    case MP_INDENT: return prefIndentWidth;
    case MP_SPACES: return prefUseSpaces;
    case MP_AUTO:   return prefAutoIndent;
    default:        return prefWrap;
    }
}

/* Pushes the indentation settings to a document. */
- (void)applyIndentPrefsTo:(EditorDoc *)d
{
    if ([d lineNumbers] != prefLineNumbers) [d setLineNumbers:prefLineNumbers];
    [d setAutoIndent:[self effectiveSetting:MP_AUTO for:d]];
    [d setUseSpaces:[self effectiveSetting:MP_SPACES for:d]];
    [d setIndentWidth:[self effectiveSetting:MP_INDENT for:d]];
}

/* The document's language mode was chosen (a file was opened or saved with a name, or Language Mode was used). */
- (void)applyModePrefsTo:(EditorDoc *)d
{
    [self applyIndentPrefsTo:d];
    if ([d wrap] != (BOOL)[self effectiveSetting:MP_WRAP for:d]) [d setWrap:[self effectiveSetting:MP_WRAP for:d]];
}

- (int)modeSetting:(int)which forMode:(NSString *)name
{
    return modeprefs_get(&modePrefs, UI_CPATH(name), which);
}

- (void)setModeSetting:(int)which value:(int)value forMode:(NSString *)name
{
    unsigned int i;

    if (modeprefs_set(&modePrefs, UI_CPATH(name), which, value) != 0) return;
    [self savePreferences];
    for (i = 0; i < [docs count]; i++) {
        EditorDoc *d = [docs objectAtIndex:i];

        if ([d mode] != nil && [[d mode] isEqualToString:name]) [self applyModePrefsTo:d];
    }
}

- (void)applyIndentPrefs
{
    unsigned int i;

    for (i = 0; i < [docs count]; i++) [self applyIndentPrefsTo:[docs objectAtIndex:i]];
}

- (void)toggleAutoIndent:(id)sender { prefAutoIndent = !prefAutoIndent; [self applyIndentPrefs]; [self savePreferences]; }
- (void)toggleUseSpaces:(id)sender { prefUseSpaces = !prefUseSpaces; [self applyIndentPrefs]; [self savePreferences]; }
- (void)setIndentWidth:(id)sender { prefIndentWidth = [sender tag]; [self applyIndentPrefs]; [self savePreferences]; }

- (void)toggleLineNumbers:(id)sender
{
    unsigned int i;

    prefLineNumbers = !prefLineNumbers;
    for (i = 0; i < [docs count]; i++) [[docs objectAtIndex:i] setLineNumbers:prefLineNumbers];
    [self savePreferences];
}

- (void)findUnmatched:(id)sender
{
    EditorDoc *d = [self frontDocument];
    int r = [d findUnmatchedBracket];

    if (r == 0) NSRunAlertPanel(@"Find Unmatched Bracket", @"Every bracket and block keyword in this file has a partner.", @"OK", nil, nil);
}

- (void)gotoBracket:(id)sender { [self macroNote:@"match-bracket"]; [[self frontDocument] gotoMatchingBracket:NO]; }
- (void)selectBracket:(id)sender { [self macroNote:@"select-bracket"]; [[self frontDocument] gotoMatchingBracket:YES]; }
- (void)shiftLeft:(id)sender { [self macroNote:@"shift-left"]; [[self frontDocument] shiftSelection:-1]; }
- (void)shiftRight:(id)sender { [self macroNote:@"shift-right"]; [[self frontDocument] shiftSelection:1]; }
- (void)commentLines:(id)sender { [self macroNote:@"comment"]; [[self frontDocument] commentSelection:YES]; }
- (void)uncommentLines:(id)sender { [self macroNote:@"uncomment"]; [[self frontDocument] commentSelection:NO]; }

- (void)toggleWrap:(id)sender
{
    EditorDoc *d = [self frontDocument];

    if (d != nil) {
        [d setWrap:![d wrap]];
        prefWrap = [d wrap];
        [self savePreferences];
    }
}

- (FindController *)finder
{
    if (finder == nil) finder = [[FindController alloc] initWithOwner:self];
    return finder;
}

- (ShellController *)shellController
{
    if (shell == nil) shell = [[ShellController alloc] initWithOwner:self];
    return shell;
}

- (void)filterSelection:(id)sender { [[self shellController] filterSelection]; }
- (void)executeCommand:(id)sender { [[self shellController] executeCommand]; }
- (void)sortLines:(id)sender { [[self shellController] sortLines]; }
- (void)fillParagraph:(id)sender
{
    EditorDoc *d = [self frontDocument];

    [self macroNote:@"fill-paragraph"];
    [d expandAllFolds];                      /* a marker must not be re-flowed */
    [d fillWithWidth:prefFillWidth];
}

/* ---- Open Included File ---- */

/* The file that `name` stands for: next to the document, then along the include path (a name like Foo/Bar.h is also looked for as
 * Foo.framework/Headers/Bar.h).  nil if there is none. */
- (NSString *)resolveInclude:(NSString *)name from:(EditorDoc *)d searched:(NSMutableArray *)searched
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *dirs = [NSMutableArray array];
    NSArray *path = [[Appearance includePath] componentsSeparatedByString:@":"];
    unsigned int i;
    BOOL isDir;

    name = [name stringByExpandingTildeInPath];
    if ([name isAbsolutePath]) {
        [searched addObject:name];
        return ([fm fileExistsAtPath:name isDirectory:&isDir] && !isDir) ? name : nil;
    }
    if ([d path] != nil) [dirs addObject:[[d path] stringByDeletingLastPathComponent]];
    for (i = 0; i < [path count]; i++)
        if ([[path objectAtIndex:i] length] > 0) [dirs addObject:[path objectAtIndex:i]];
    for (i = 0; i < [dirs count]; i++) {
        NSString *dir = [dirs objectAtIndex:i], *cand = [dir stringByAppendingPathComponent:name];
        NSRange slash = [name rangeOfString:@"/"];

        if ([fm fileExistsAtPath:cand isDirectory:&isDir] && !isDir) return cand;
        if (slash.length > 0) {
            NSString *fw = [NSString stringWithFormat:@"%@.framework/Headers", [name substringToIndex:slash.location]];
            cand = [[dir stringByAppendingPathComponent:fw] stringByAppendingPathComponent:[name substringFromIndex:NSMaxRange(slash)]];
            if ([fm fileExistsAtPath:cand isDirectory:&isDir] && !isDir) return cand;
        }
        [searched addObject:dir];
    }
    return nil;
}

- (void)openIncluded:(id)sender
{
    EditorDoc *d = [self frontDocument];
    char names[INCLUDE_MAX_NAMES][INCLUDE_NAME_SIZE], tok[INCLUDE_NAME_SIZE];
    NSString *line, *found = nil, *first = nil;
    NSMutableArray *searched = [NSMutableArray array];
    unsigned int count, i, n;
    int system = 0;
    u16 *u;

    if (d == nil) return;
    line = [d lineAtCaret];
    n = [line length];
    u = (u16 *)malloc((n + 1) * sizeof(u16));
    if (u == NULL) return;
    if (n > 0) [line getCharacters:u];
    count = include_parse(u, n, [d mode] != nil ? [[d mode] cString] : NULL, names, &system);
    free(u);
    if (count == 0) {                                          /* not an include line: a selected name, or the name at the insertion point */
        NSString *sel = [d selectedString];

        if (sel != nil && [sel length] < INCLUDE_NAME_SIZE && [sel rangeOfString:@"\n"].length == 0) {
            strcpy(names[0], [ui_trim(sel) cString]);
            count = strlen(names[0]) > 0 ? 1 : 0;
        } else {
            NSRange r = [[d textView] selectedRange];
            NSRange lr = [[[d textView] string] lineRangeForRange:NSMakeRange(r.location, 0)];
            u = (u16 *)malloc((n + 1) * sizeof(u16));
            if (u != NULL) {
                if (n > 0) [line getCharacters:u];
                if (include_token(u, n, r.location - lr.location, tok, sizeof tok) > 0) { strcpy(names[0], tok); count = 1; }
                free(u);
            }
        }
    }
    if (count == 0) { NSBeep(); return; }
    for (i = 0; i < count && found == nil; i++) {
        NSString *nm = [NSString stringWithCString:names[i]];
        if (first == nil) first = nm;
        found = [self resolveInclude:nm from:d searched:searched];
    }
    if (found == nil) {
        NSRunAlertPanel(@"Open Included File", @"%@ was not found in:\n%@", @"OK", nil, nil, first,
                        [searched count] > 0 ? [searched componentsJoinedByString:@"\n"] : @"(nowhere)");
        return;
    }
    [self openPath:found];
}

/* ---- tags ---- */

- (TagsController *)tagsController
{
    if (tags == nil) tags = [[TagsController alloc] initWithOwner:self];
    return tags;
}

- (void)findDefinition:(id)sender { [[self tagsController] findDefinition]; }
- (void)returnFromDefinition:(id)sender { [[self tagsController] returnFromDefinition]; }
- (void)showCallTip:(id)sender { [[self tagsController] showCallTip]; }
- (void)loadTags:(id)sender { [[self tagsController] loadTagsFile]; }
- (void)hideCallTip { if (tags != nil) [tags hideCallTip]; }
- (void)showCallTipAfterParenIn:(EditorDoc *)doc { if (![self macroReplaying]) [[self tagsController] showCallTipAfterParenIn:doc]; }

/* ---- macros ---- */

- (MacroController *)macroController
{
    if (macros == nil) macros = [[MacroController alloc] initWithOwner:self];
    return macros;
}

- (BOOL)macroRecording { return macros != nil && [macros recording]; }
- (BOOL)macroReplaying { return macros != nil && [macros replaying]; }
- (void)macroNote:(NSString *)name { if (macros != nil) [macros noteCommand:name]; }
- (void)macroNoteInsert:(NSString *)text { if (macros != nil) [macros noteInsert:text]; }
- (void)macroNoteAction:(NSString *)name { if (macros != nil) [macros noteAction:name]; }
- (void)macroNoteFind:(NSString *)pattern flags:(NSString *)flags { if (macros != nil) [macros noteFind:pattern flags:flags]; }
- (void)macroNoteFilter:(NSString *)verb command:(NSString *)command { if (macros != nil) [macros noteFilter:verb command:command]; }
- (BOOL)macroIsRecordableAction:(NSString *)name { return [[self macroController] isRecordableAction:name]; }

- (void)macroNoteReplace:(NSString *)verb pattern:(NSString *)pattern replacement:(NSString *)replacement flags:(NSString *)flags
{
    if (macros != nil) [macros noteReplace:verb pattern:pattern replacement:replacement flags:flags];
}

/* A menu command by the name a macro gives it. */
- (BOOL)macroCommand:(NSString *)name
{
    static const struct { const char *name; const char *sel; } T[] = {
        { "shift-left", "shiftLeft:" }, { "shift-right", "shiftRight:" },
        { "comment", "commentLines:" }, { "uncomment", "uncommentLines:" },
        { "fill-paragraph", "fillParagraph:" },
        { "fold-toggle", "toggleFold:" }, { "fold-all", "foldAll:" }, { "expand-all", "expandAll:" },
        { "match-bracket", "gotoBracket:" }, { "select-bracket", "selectBracket:" },
        { "undo", "undoDoc:" }, { "redo", "redoDoc:" },
        { NULL, NULL }
    };
    int i;

    for (i = 0; T[i].name != NULL; i++) {
        if ([name isEqualToString:[NSString stringWithCString:T[i].name]]) {
            [self performSelector:NSSelectorFromString([NSString stringWithCString:T[i].sel]) withObject:nil];
            return YES;
        }
    }
    return NO;
}

- (void)learnMacro:(id)sender
{
    unsigned int i;

    [[self macroController] toggleLearning];
    for (i = 0; i < [docs count]; i++) [[docs objectAtIndex:i] macroStateChanged];
    [self rebuildMacroMenus];
}

- (void)replayMacro:(id)sender { [[self macroController] replay]; }
- (void)repeatMacro:(id)sender { [[self macroController] repeatDialog]; }

- (void)runSavedMacro:(id)sender
{
    NSArray *names = [[self macroController] savedNames];
    int i = [sender tag];

    if (i >= 0 && i < (int)[names count]) [[self macroController] runSaved:[names objectAtIndex:i]];
}

- (void)editSavedMacro:(id)sender
{
    NSArray *names = [[self macroController] savedNames];
    int i = [sender tag];

    if (i >= 0 && i < (int)[names count]) [self openPath:[[[self macroController] folderPath] stringByAppendingPathComponent:[names objectAtIndex:i]]];
}

- (void)rebuildMacroMenus
{
    NSMenu *menus[2];
    SEL acts[2];
    NSArray *names;
    unsigned int m, i;

    if (macroRunMenu == nil) return;
    names = [[self macroController] savedNames];
    menus[0] = macroRunMenu;  acts[0] = @selector(runSavedMacro:);
    menus[1] = macroEditMenu; acts[1] = @selector(editSavedMacro:);
    NS_DURING
        for (m = 0; m < 2; m++) {
            NSArray *old = [NSArray arrayWithArray:[menus[m] itemArray]];
            for (i = 0; i < [old count]; i++) [menus[m] removeItem:[old objectAtIndex:i]];
            for (i = 0; i < [names count]; i++) [[self addItem:[names objectAtIndex:i] action:acts[m] key:@"" target:self toMenu:menus[m]] setTag:(int)i];
            if ([names count] == 0) [[self addItem:@"(none saved)" action:NULL key:@"" target:self toMenu:menus[m]] setEnabled:NO];
            if ([menus[m] respondsToSelector:@selector(sizeToFit)]) [menus[m] sizeToFit];
        }
    NS_HANDLER
        SSTrace("macro menus: %s -- %s", SSCS([localException name]), SSCS([localException reason]));
    NS_ENDHANDLER
}

- (void)saveMacro:(id)sender
{
    NSPanel *panel;
    NSTextField *field;
    int result;

    if (![[self macroController] hasMacro]) return;
    panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 300, 92)
                                       styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                         backing:NSBackingStoreBuffered defer:NO];
    [panel setTitle:@"Save Macro"];
    field = ui_field(NSMakeRect(70, 54, 210, 22));
    [[panel contentView] addSubview:ui_label(@"Name:", NSMakeRect(16, 56, 50, 18))];
    [[panel contentView] addSubview:field];
    [[panel contentView] addSubview:ui_button(@"Save", NSMakeRect(210, 12, 70, 28), self, @selector(gotoOK:))];
    [[panel contentView] addSubview:ui_button(@"Cancel", NSMakeRect(130, 12, 70, 28), self, @selector(gotoCancel:))];
    [panel center];
    [panel makeFirstResponder:field];
    result = [NSApp runModalForWindow:panel];
    if (result == NSOKButton) {
        if ([[self macroController] saveLastAs:[field stringValue]]) [self rebuildMacroMenus];
        else NSRunAlertPanel(@"Save Macro", @"The macro could not be saved under that name.", @"OK", nil, nil);
    }
    [panel close];
    [panel release];
}

/* The macro learned last, as text in a window of its own: it can be read, changed and saved (in the macro folder, or anywhere). */
- (void)macroAsText:(id)sender
{
    EditorDoc *d = [self newDocument];

    [[d textView] setString:[@"# JOSE macro\n" stringByAppendingString:[[self macroController] lastAsText]]];
    [d setMode:@"JOSEMacro"];
}

- (void)splitPane:(id)sender { [[self frontDocument] splitPane]; }
- (void)closePane:(id)sender { [[self frontDocument] closePane]; }

/* ---- sessions ---- */

- (SessionController *)sessionController
{
    if (sessions == nil) sessions = [[SessionController alloc] initWithOwner:self];
    return sessions;
}

- (void)rebuildSessionMenus
{
    NSMenu *menus[3];
    SEL acts[3];
    NSArray *names;
    unsigned int m, i;

    if (sessionOpenMenu == nil) return;
    names = [[self sessionController] savedNames];
    menus[0] = sessionOpenMenu;   acts[0] = @selector(openSavedSession:);
    menus[1] = sessionSwitchMenu; acts[1] = @selector(switchToSavedSession:);
    menus[2] = sessionDeleteMenu; acts[2] = @selector(deleteSavedSession:);
    NS_DURING
        for (m = 0; m < 3; m++) {
            NSArray *old = [NSArray arrayWithArray:[menus[m] itemArray]];
            for (i = 0; i < [old count]; i++) [menus[m] removeItem:[old objectAtIndex:i]];
            for (i = 0; i < [names count]; i++) [[self addItem:[names objectAtIndex:i] action:acts[m] key:@"" target:self toMenu:menus[m]] setTag:(int)i];
            if ([names count] == 0) [[self addItem:@"(none saved)" action:NULL key:@"" target:self toMenu:menus[m]] setEnabled:NO];
            if ([menus[m] respondsToSelector:@selector(sizeToFit)]) [menus[m] sizeToFit];
        }
    NS_HANDLER
        SSTrace("session menus: %s -- %s", SSCS([localException name]), SSCS([localException reason]));
    NS_ENDHANDLER
}

/* A small modal panel asking for a name; nil if cancelled. */
- (NSString *)askName:(NSString *)title
{
    NSPanel *panel;
    NSTextField *field;
    NSString *result = nil;

    panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 300, 92)
                                       styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                         backing:NSBackingStoreBuffered defer:NO];
    [panel setTitle:title];
    field = ui_field(NSMakeRect(70, 54, 210, 22));
    [field setTarget:self];
    [field setAction:@selector(gotoOK:)];
    [[panel contentView] addSubview:ui_label(@"Name:", NSMakeRect(16, 56, 50, 18))];
    [[panel contentView] addSubview:field];
    [[panel contentView] addSubview:ui_button(@"Save", NSMakeRect(210, 12, 70, 28), self, @selector(gotoOK:))];
    [[panel contentView] addSubview:ui_button(@"Cancel", NSMakeRect(130, 12, 70, 28), self, @selector(gotoCancel:))];
    [panel center];
    [panel makeFirstResponder:field];
    if ([NSApp runModalForWindow:panel] == NSOKButton) result = [[[field stringValue] copy] autorelease];
    [panel close];
    [panel release];
    return result;
}

- (void)saveSessionAs:(id)sender
{
    NSString *name = [self askName:@"Save Session"];

    if (name == nil) return;
    if ([[self sessionController] saveAs:name]) [self rebuildSessionMenus];
    else NSRunAlertPanel(@"Save Session", @"The session could not be saved under that name (it needs a name without a slash or a leading dot, and at least one window that shows a file).", @"OK", nil, nil);
}

- (void)saveSession:(id)sender
{
    if (![[self sessionController] save]) NSRunAlertPanel(@"Save Session", @"The session could not be saved.", @"OK", nil, nil);
}

- (void)afterSessionOpen:(NSString *)name ok:(BOOL)ok
{
    unsigned int miss = [[self sessionController] missingCount];

    [[self sessionController] recordLast];
    if (!ok && miss == 0) return;                                /* cancelled while closing windows */
    if (miss > 0) NSRunAlertPanel(@"Open Session", @"%u of the files in the session %@ could not be found.", @"OK", nil, nil, miss, name);
}

- (void)openSavedSession:(id)sender
{
    NSArray *names = [[self sessionController] savedNames];
    int i = [sender tag];

    if (i < 0 || i >= (int)[names count]) return;
    [self afterSessionOpen:[names objectAtIndex:i] ok:[[self sessionController] open:[names objectAtIndex:i] replace:NO]];
    [self rebuildSessionMenus];
}

- (void)switchToSavedSession:(id)sender
{
    NSArray *names = [[self sessionController] savedNames];
    int i = [sender tag];

    if (i < 0 || i >= (int)[names count]) return;
    [self afterSessionOpen:[names objectAtIndex:i] ok:[[self sessionController] open:[names objectAtIndex:i] replace:YES]];
    [self rebuildSessionMenus];
}

- (void)deleteSavedSession:(id)sender
{
    NSArray *names = [[self sessionController] savedNames];
    int i = [sender tag];

    if (i < 0 || i >= (int)[names count]) return;
    if (NSRunAlertPanel(@"Delete Session", @"Delete the saved session %@?", @"Delete", @"Cancel", nil, [names objectAtIndex:i]) != NSAlertDefaultReturn) return;
    [[self sessionController] deleteNamed:[names objectAtIndex:i]];
    [self rebuildSessionMenus];
}

- (void)reopenLastSession:(id)sender
{
    BOOL ok = [[self sessionController] openLast];

    [self afterSessionOpen:@"(last)" ok:ok];
}

- (void)showFiles:(id)sender
{
    if (filesFinder == nil) filesFinder = [[FilesController alloc] initWithOwner:self];
    [filesFinder showPanel];
}

- (NSArray *)documents { return [NSArray arrayWithArray:docs]; }

- (EditorDoc *)documentForPath:(NSString *)path
{
    unsigned int i;

    path = [path stringByStandardizingPath];
    for (i = 0; i < [docs count]; i++) {
        EditorDoc *d = [docs objectAtIndex:i];

        if ([d path] != nil && [[d path] isEqualToString:path]) return d;
    }
    return nil;
}

- (void)showPrefs:(id)sender
{
    if (prefs == nil) prefs = [[PrefsController alloc] initWithOwner:self];
    [prefs showPanel];
}

- (void)appearanceChanged
{
    unsigned int i;

    for (i = 0; i < [docs count]; i++) [[docs objectAtIndex:i] applyAppearance];
}

- (void)toggleFold:(id)sender { [self macroNote:@"fold-toggle"]; [[self frontDocument] toggleFold]; }
- (void)foldAll:(id)sender { [self macroNote:@"fold-all"]; [[self frontDocument] foldAll]; }
- (void)expandAll:(id)sender { [self macroNote:@"expand-all"]; [[self frontDocument] expandAllFolds]; }

- (void)setFillWidth:(id)sender
{
    prefFillWidth = [sender tag];
    [self savePreferences];
}

- (void)showFind:(id)sender { [[self finder] showPanel]; }
- (void)findAgain:(id)sender { [[self finder] findAgain]; }
- (void)findPrevious:(id)sender { [[self finder] findPrevious]; }
- (void)findSelection:(id)sender { [[self finder] findSelection]; }

/* Go to Line: a small panel with a field. */
- (void)gotoOK:(id)sender { [NSApp stopModalWithCode:NSOKButton]; }
- (void)gotoCancel:(id)sender { [NSApp stopModalWithCode:NSCancelButton]; }

- (void)gotoLine:(id)sender
{
    EditorDoc *d = [self frontDocument];
    NSPanel *panel;
    NSTextField *field;
    int result;

    if (d == nil) return;
    panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 260, 92)
                                       styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                         backing:NSBackingStoreBuffered defer:NO];
    [panel setTitle:@"Go to Line"];
    field = ui_field(NSMakeRect(80, 54, 160, 22));
    [field setTarget:self];
    [field setAction:@selector(gotoOK:)];                                   /* Return goes, like the button */
    [[panel contentView] addSubview:ui_label(@"Line:", NSMakeRect(16, 56, 60, 18))];
    [[panel contentView] addSubview:field];
    [[panel contentView] addSubview:ui_button(@"Go", NSMakeRect(170, 12, 70, 28), self, @selector(gotoOK:))];
    [[panel contentView] addSubview:ui_button(@"Cancel", NSMakeRect(90, 12, 70, 28), self, @selector(gotoCancel:))];
    [panel center];
    [panel makeFirstResponder:field];
    result = [NSApp runModalForWindow:panel];
    if (result == NSOKButton) [d goToLine:[[field stringValue] intValue]];
    [panel close];
    [panel release];
}

/* ---- the application ---- */

- (void)openAtLaunch:(NSString *)path
{
    if (startupFiles == nil) startupFiles = [[NSMutableArray alloc] init];
    [startupFiles addObject:path];
}

/* NSApp's standard info panel crashed on 4.2 (it wants an Info file the bundle lacks); a plain alert does not. */
- (void)showAbout:(id)sender
{
    NSRunAlertPanel(@"JOSE", @"Jade's OPENSTEP Editor\n\nVersion 0.0.1\n\nA syntax-highlighting text editor.\nHighlighting by HighlighterKit (LGPL).",
                    @"OK", nil, nil);
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    int i;
    launched = YES;
    [self buildFullMenu];
    for (i = 0; i < (int)[startupFiles count]; i++) [self openPath:[startupFiles objectAtIndex:i]];
    [startupFiles release]; startupFiles = nil;
    if ([docs count] == 0 && [Appearance reopenLastSession] && [[self sessionController] hasLast]) {
        BOOL ok = [[self sessionController] openLast];

        SSTrace("reopening the last session: %s, %u missing", ok ? "done" : "nothing opened", [[self sessionController] missingCount]);
    }
    if ([docs count] == 0) [self newDocument];
}

- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename
{
    return [self openPath:filename] != nil;
}

- (BOOL)applicationShouldTerminate:(id)sender
{
    unsigned int i;

    [[self sessionController] recordLast];                       /* the windows as they are now, before any is closed */
    [[self sessionController] setQuiet:YES];
    for (i = 0; i < [docs count]; i++) {
        EditorDoc *d = [docs objectAtIndex:i];
        if ([d isDirty]) {
            [d showWindow];
            if (![d closeWindow]) { [[self sessionController] setQuiet:NO]; return NO; }
            i = 0;
            continue;
        }
    }
    return YES;
}

@end
