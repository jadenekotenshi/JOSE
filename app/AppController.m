#import "AppController.h"
#import "EditorDoc.h"
#import "FindController.h"
#import "UIHelpers.h"
#import "HKSyntaxDefinition.h"

#define TAG_MODE_BASE 1000             /* the Language Mode items: the tag is this plus the mode's index; plain text is TAG_MODE_BASE - 1 */

@interface AppController (Private)
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
        menuKeepers = [[NSMutableArray alloc] init];
        syntaxDir = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"syntax"];
        [syntaxDir retain];
        [HKSyntaxDefinition setSyntaxDirectory:syntaxDir];
    }
    return self;
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

    m = [self submenuNamed:@"Search" inMenu:main];
    [self addItem:@"Find..." action:@selector(showFind:) key:@"f" target:self toMenu:m];
    [self addItem:@"Find Again" action:@selector(findAgain:) key:@"g" target:self toMenu:m];
    [self addItem:@"Find Previous" action:@selector(findPrevious:) key:@"G" target:self toMenu:m];
    [self addItem:@"Find Selection" action:@selector(findSelection:) key:@"e" target:self toMenu:m];
    [self addItem:@"Replace..." action:@selector(showFind:) key:@"r" target:self toMenu:m];
    [self addItem:@"Go to Line..." action:@selector(gotoLine:) key:@"l" target:self toMenu:m];

    m = [self submenuNamed:@"Preferences" inMenu:main];
    [[self addItem:@"Wrap Lines" action:@selector(toggleWrap:) key:@"" target:self toMenu:m] setTag:1];
    modeMenu = [self submenuNamed:@"Language Mode" inMenu:m];
    item = [self addItem:@"Plain Text" action:@selector(setMode:) key:@"" target:self toMenu:modeMenu];
    [item setTag:TAG_MODE_BASE - 1];
    names = [self modeNames];
    for (i = 0; i < [names count]; i++) {
        item = [self addItem:[names objectAtIndex:i] action:@selector(setMode:) key:@"" target:self toMenu:modeMenu];
        [item setTag:TAG_MODE_BASE + (int)i];
    }

    m = [self submenuNamed:@"Windows" inMenu:main];
    [self addItem:@"Arrange in Front" action:@selector(arrangeInFront:) key:@"" target:nil toMenu:m];
    [self addItem:@"Miniaturize Window" action:@selector(performMiniaturize:) key:@"m" target:nil toMenu:m];
    [NSApp setWindowsMenu:m];

    m = [self submenuNamed:@"Services" inMenu:main];
    [NSApp setServicesMenu:m];

    [self addItem:@"Hide" action:@selector(hide:) key:@"h" target:NSApp toMenu:main];
    [self addItem:@"Quit" action:@selector(terminate:) key:@"q" target:NSApp toMenu:main];
    [NSApp setMainMenu:main];
}

- (EditorDoc *)frontDocument
{
    NSWindow *w = [NSApp keyWindow];
    unsigned int i;

    if (w == nil) w = [NSApp mainWindow];
    for (i = 0; i < [docs count]; i++)
        if ([[docs objectAtIndex:i] window] == w) return [docs objectAtIndex:i];
    return nil;
}

- (BOOL)validateMenuItem:(id)item
{
    EditorDoc *d = [self frontDocument];
    SEL a = [item action];
    int tag = [item tag];

    if (a == @selector(saveDoc:) || a == @selector(saveDocAs:) || a == @selector(closeDoc:) || a == @selector(gotoLine:) || a == @selector(showFind:) || a == @selector(findAgain:)
        || a == @selector(findPrevious:) || a == @selector(findSelection:)
        || a == @selector(toggleWrap:) || a == @selector(setMode:))
        if (d == nil) return NO;
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

    [docs addObject:d];
    [d release];
    [d showWindow];
    return d;
}

- (EditorDoc *)openPath:(NSString *)path
{
    unsigned int i;
    EditorDoc *d;

    for (i = 0; i < [docs count]; i++) {                       /* already open: bring it forward */
        d = [docs objectAtIndex:i];
        if ([d path] != nil && [[d path] isEqualToString:path]) { [d showWindow]; return d; }
    }
    d = [[EditorDoc alloc] initWithOwner:self];
    if (![d openFile:path]) { [d release]; return nil; }
    [docs addObject:d];
    [d release];
    [d showWindow];
    return d;
}

- (void)documentDidClose:(EditorDoc *)doc
{
    [[doc retain] autorelease];                                  /* the window is still telling us it is closing */
    [docs removeObject:doc];
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

- (void)undoDoc:(id)sender { [[self frontDocument] undo]; }
- (void)redoDoc:(id)sender { [[self frontDocument] redo]; }
- (void)closeDoc:(id)sender { [[self frontDocument] closeWindow]; }

- (void)setMode:(id)sender
{
    EditorDoc *d = [self frontDocument];
    int tag = [sender tag];

    if (d == nil) return;
    [d setMode:(tag == TAG_MODE_BASE - 1) ? nil : [sender title]];
}

- (void)toggleWrap:(id)sender
{
    EditorDoc *d = [self frontDocument];

    if (d != nil) [d setWrap:![d wrap]];
}

- (FindController *)finder
{
    if (finder == nil) finder = [[FindController alloc] initWithOwner:self];
    return finder;
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
    if ([docs count] == 0) [self newDocument];
}

- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename
{
    return [self openPath:filename] != nil;
}

- (BOOL)applicationShouldTerminate:(id)sender
{
    unsigned int i;

    for (i = 0; i < [docs count]; i++) {
        EditorDoc *d = [docs objectAtIndex:i];
        if ([d isDirty]) {
            [d showWindow];
            if (![d closeWindow]) return NO;
            i = 0;
            continue;
        }
    }
    return YES;
}

@end
