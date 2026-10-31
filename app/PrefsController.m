#import "PrefsController.h"
#import "Appearance.h"
#import "UIHelpers.h"

static const int font_sizes[] = { 8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 24 };
#define N_FONT_SIZES 11
#define DEFAULT_ITEM @"Default (fixed-pitch)"

@interface PrefsController (Private)
- (void)buildPanel;
- (void)syncControls;
- (void)changed;
- (void)schemeChanged:(id)sender;
- (void)backgroundChanged:(id)sender;
- (void)textChanged:(id)sender;
- (void)resetColors:(id)sender;
- (void)fontChanged:(id)sender;
- (void)pathChanged:(id)sender;
- (void)tipsChanged:(id)sender;
- (void)marginChanged:(id)sender;
- (void)closePanel:(id)sender;
@end

@implementation PrefsController

- (id)initWithOwner:(id)anOwner
{
    self = [super init];
    if (self) owner = anOwner;
    return self;
}

- (void)dealloc
{
    [fixedFonts release];
    [super dealloc];
}

/* The fixed-pitch fonts installed: tried once, since asking each font takes a moment. */
- (NSArray *)fixedPitchFonts
{
    if (fixedFonts == nil) {
        NSArray *all = [[NSFontManager sharedFontManager] availableFonts];
        NSMutableArray *found = [NSMutableArray array];
        unsigned int i;

        for (i = 0; i < [all count]; i++) {
            NSString *name = [all objectAtIndex:i];
            NSFont *f = [NSFont fontWithName:name size:12.0];
            if (f != nil && [f isFixedPitch]) [found addObject:name];
        }
        fixedFonts = [[found sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)] retain];
    }
    return fixedFonts;
}

- (void)buildPanel
{
    NSView *cv;
    NSArray *fonts = [self fixedPitchFonts];
    unsigned int i;

    panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 440, 292)
                                       styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                         backing:NSBackingStoreBuffered defer:NO];
    [panel setTitle:@"Preferences"];
    [panel setReleasedWhenClosed:NO];
    cv = [panel contentView];

    [cv addSubview:ui_label(@"Colours:", NSMakeRect(16, 254, 90, 18))];
    schemePopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(110, 250, 110, 24) pullsDown:NO] autorelease];
    [schemePopup addItemWithTitle:@"Light"];
    [schemePopup addItemWithTitle:@"Dark"];
    [schemePopup setTarget:self];
    [schemePopup setAction:@selector(schemeChanged:)];
    [cv addSubview:schemePopup];
    [cv addSubview:ui_button(@"Reset Colours", NSMakeRect(300, 250, 124, 26), self, @selector(resetColors:))];

    [cv addSubview:ui_label(@"Background:", NSMakeRect(16, 218, 90, 18))];
    backgroundWell = [[[NSColorWell alloc] initWithFrame:NSMakeRect(110, 212, 44, 28)] autorelease];
    [backgroundWell setTarget:self];
    [backgroundWell setAction:@selector(backgroundChanged:)];
    [cv addSubview:backgroundWell];
    [cv addSubview:ui_label(@"Text:", NSMakeRect(190, 218, 40, 18))];
    textWell = [[[NSColorWell alloc] initWithFrame:NSMakeRect(234, 212, 44, 28)] autorelease];
    [textWell setTarget:self];
    [textWell setAction:@selector(textChanged:)];
    [cv addSubview:textWell];

    [cv addSubview:ui_label(@"Font:", NSMakeRect(16, 180, 90, 18))];
    fontPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(110, 176, 214, 24) pullsDown:NO] autorelease];
    [fontPopup addItemWithTitle:DEFAULT_ITEM];
    for (i = 0; i < [fonts count]; i++) [fontPopup addItemWithTitle:[fonts objectAtIndex:i]];
    [fontPopup setTarget:self];
    [fontPopup setAction:@selector(fontChanged:)];
    [cv addSubview:fontPopup];
    [cv addSubview:ui_label(@"Size:", NSMakeRect(334, 180, 36, 18))];
    sizePopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(372, 176, 56, 24) pullsDown:NO] autorelease];
    [sizePopup addItemWithTitle:@"-"];
    for (i = 0; i < N_FONT_SIZES; i++) [sizePopup addItemWithTitle:[NSString stringWithFormat:@"%d", font_sizes[i]]];
    [sizePopup setTarget:self];
    [sizePopup setAction:@selector(fontChanged:)];
    [cv addSubview:sizePopup];

    [cv addSubview:ui_label(@"Include path:", NSMakeRect(16, 142, 90, 18))];
    pathField = ui_field(NSMakeRect(110, 140, 314, 22));
    [pathField setTarget:self];
    [pathField setAction:@selector(pathChanged:)];
    [cv addSubview:pathField];
    [cv addSubview:ui_wrapping_label(@"Folders searched, after the file's own, by Open Included File (separate them with colons).",
                                     NSMakeRect(110, 100, 314, 34), NO)];

    tipsSwitch = ui_switch(@"Show a call tip when typing '(' after a tagged name", NSMakeRect(16, 72, 408, 20));
    [tipsSwitch setTarget:self];
    [tipsSwitch setAction:@selector(tipsChanged:)];
    [cv addSubview:tipsSwitch];
    marginSwitch = ui_switch(@"Fold margin (+/-) beside the code", NSMakeRect(16, 46, 408, 20));
    [marginSwitch setTarget:self];
    [marginSwitch setAction:@selector(marginChanged:)];
    [cv addSubview:marginSwitch];

    [cv addSubview:ui_button(@"Close", NSMakeRect(354, 8, 70, 28), self, @selector(closePanel:))];
    [panel center];
}

- (void)syncControls
{
    NSString *fn = [Appearance fontName];
    float fs = [Appearance fontSize];
    int i;

    [schemePopup selectItemWithTitle:[Appearance dark] ? @"Dark" : @"Light"];
    [backgroundWell setColor:[Appearance backgroundColor]];
    [textWell setColor:[Appearance textColor]];
    if (fn != nil && [fontPopup indexOfItemWithTitle:fn] >= 0) [fontPopup selectItemWithTitle:fn];
    else [fontPopup selectItemWithTitle:DEFAULT_ITEM];
    [sizePopup selectItemWithTitle:@"-"];
    for (i = 0; i < N_FONT_SIZES; i++)
        if ((float)font_sizes[i] == fs) [sizePopup selectItemWithTitle:[NSString stringWithFormat:@"%d", font_sizes[i]]];
    [pathField setStringValue:[Appearance includePath]];
    [tipsSwitch setState:[Appearance callTips] ? NSOnState : NSOffState];
    [marginSwitch setState:[Appearance foldMargin] ? NSOnState : NSOffState];
}

- (void)showPanel
{
    if (panel == nil) [self buildPanel];
    [self syncControls];
    [panel makeKeyAndOrderFront:nil];
}

- (void)changed
{
    [Appearance saveSettings];
    [owner appearanceChanged];
}

- (void)schemeChanged:(id)sender
{
    [Appearance setDark:[[schemePopup titleOfSelectedItem] isEqualToString:@"Dark"]];
    [self syncControls];
    [self changed];
}

- (void)backgroundChanged:(id)sender
{
    [Appearance setBackgroundColor:[backgroundWell color]];
    [self changed];
}

- (void)textChanged:(id)sender
{
    [Appearance setTextColor:[textWell color]];
    [self changed];
}

- (void)resetColors:(id)sender
{
    [Appearance resetColors];
    [self syncControls];
    [self changed];
}

- (void)fontChanged:(id)sender
{
    NSString *name = [fontPopup titleOfSelectedItem];
    NSString *size = [sizePopup titleOfSelectedItem];

    [Appearance setFontName:[name isEqualToString:DEFAULT_ITEM] ? nil : name size:[size isEqualToString:@"-"] ? 0.0 : (float)[size intValue]];
    [self changed];
}

- (void)pathChanged:(id)sender
{
    [Appearance setIncludePath:ui_trim([pathField stringValue])];
    [self changed];
}

- (void)tipsChanged:(id)sender
{
    [Appearance setCallTips:[tipsSwitch state] == NSOnState];
    [self changed];
}

- (void)marginChanged:(id)sender
{
    [Appearance setFoldMargin:[marginSwitch state] == NSOnState];
    [self changed];
}

- (void)closePanel:(id)sender
{
    [self pathChanged:nil];                 /* a path typed without pressing Return still counts */
    [panel orderOut:nil];
}

@end
