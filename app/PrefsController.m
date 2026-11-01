#import "PrefsController.h"
#import "AppController.h"
#include "modeprefs.h"
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
- (void)sessionChanged:(id)sender;
- (void)closePanel:(id)sender;
- (void)showModes:(id)sender;
- (void)buildModePanel;
- (void)syncModeControls;
- (void)modeSelected:(id)sender;
- (void)modeSettingChanged:(id)sender;
- (void)closeModePanel:(id)sender;
- (void)showRemote:(id)sender;
- (void)buildRemotePanel;
- (void)remoteProgramChanged:(id)sender;
- (void)remoteFieldsChanged:(id)sender;
- (void)closeRemotePanel:(id)sender;
- (void)showMarkdown:(id)sender;
- (void)buildMarkdownPanel;
- (void)markdownChanged:(id)sender;
- (void)closeMarkdownPanel:(id)sender;
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

    panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 440, 318)
                                       styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                         backing:NSBackingStoreBuffered defer:NO];
    [panel setTitle:@"Preferences"];
    [panel setReleasedWhenClosed:NO];
    cv = [panel contentView];

    [cv addSubview:ui_label(@"Colours:", NSMakeRect(16, 280, 90, 18))];
    schemePopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(110, 276, 110, 24) pullsDown:NO] autorelease];
    [schemePopup addItemWithTitle:@"Light"];
    [schemePopup addItemWithTitle:@"Dark"];
    [schemePopup setTarget:self];
    [schemePopup setAction:@selector(schemeChanged:)];
    [cv addSubview:schemePopup];
    [cv addSubview:ui_button(@"Reset Colours", NSMakeRect(300, 276, 124, 26), self, @selector(resetColors:))];

    [cv addSubview:ui_label(@"Background:", NSMakeRect(16, 244, 90, 18))];
    backgroundWell = [[[NSColorWell alloc] initWithFrame:NSMakeRect(110, 238, 44, 28)] autorelease];
    [backgroundWell setTarget:self];
    [backgroundWell setAction:@selector(backgroundChanged:)];
    [cv addSubview:backgroundWell];
    [cv addSubview:ui_label(@"Text:", NSMakeRect(190, 244, 40, 18))];
    textWell = [[[NSColorWell alloc] initWithFrame:NSMakeRect(234, 238, 44, 28)] autorelease];
    [textWell setTarget:self];
    [textWell setAction:@selector(textChanged:)];
    [cv addSubview:textWell];

    [cv addSubview:ui_label(@"Font:", NSMakeRect(16, 206, 90, 18))];
    fontPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(110, 202, 214, 24) pullsDown:NO] autorelease];
    [fontPopup addItemWithTitle:DEFAULT_ITEM];
    for (i = 0; i < [fonts count]; i++) [fontPopup addItemWithTitle:[fonts objectAtIndex:i]];
    [fontPopup setTarget:self];
    [fontPopup setAction:@selector(fontChanged:)];
    [cv addSubview:fontPopup];
    [cv addSubview:ui_label(@"Size:", NSMakeRect(334, 206, 36, 18))];
    sizePopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(372, 202, 56, 24) pullsDown:NO] autorelease];
    [sizePopup addItemWithTitle:@"-"];
    for (i = 0; i < N_FONT_SIZES; i++) [sizePopup addItemWithTitle:[NSString stringWithFormat:@"%d", font_sizes[i]]];
    [sizePopup setTarget:self];
    [sizePopup setAction:@selector(fontChanged:)];
    [cv addSubview:sizePopup];

    [cv addSubview:ui_label(@"Include path:", NSMakeRect(16, 168, 90, 18))];
    pathField = ui_field(NSMakeRect(110, 166, 314, 22));
    [pathField setTarget:self];
    [pathField setAction:@selector(pathChanged:)];
    [cv addSubview:pathField];
    [cv addSubview:ui_wrapping_label(@"Folders searched, after the file's own, by Open Included File (separate them with colons).",
                                     NSMakeRect(110, 126, 314, 34), NO)];

    tipsSwitch = ui_switch(@"Show a call tip when typing '(' after a tagged name", NSMakeRect(16, 98, 408, 20));
    [tipsSwitch setTarget:self];
    [tipsSwitch setAction:@selector(tipsChanged:)];
    [cv addSubview:tipsSwitch];
    marginSwitch = ui_switch(@"Fold margin (+/-) beside the code", NSMakeRect(16, 72, 408, 20));
    [marginSwitch setTarget:self];
    [marginSwitch setAction:@selector(marginChanged:)];
    [cv addSubview:marginSwitch];

    sessionSwitch = ui_switch(@"Reopen the last session's files when JOSE starts", NSMakeRect(16, 46, 408, 20));
    [sessionSwitch setTarget:self];
    [sessionSwitch setAction:@selector(sessionChanged:)];
    [cv addSubview:sessionSwitch];

    [cv addSubview:ui_button(@"Language Modes...", NSMakeRect(16, 8, 120, 28), self, @selector(showModes:))];
    [cv addSubview:ui_button(@"Remote Editing...", NSMakeRect(140, 8, 118, 28), self, @selector(showRemote:))];
    [cv addSubview:ui_button(@"Markdown...", NSMakeRect(262, 8, 86, 28), self, @selector(showMarkdown:))];
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
    [sessionSwitch setState:[Appearance reopenLastSession] ? NSOnState : NSOffState];
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

- (void)sessionChanged:(id)sender
{
    [Appearance setReopenLastSession:[sessionSwitch state] == NSOnState];
    [self changed];
}

- (void)closePanel:(id)sender
{
    [self pathChanged:nil];                 /* a path typed without pressing Return still counts */
    [panel orderOut:nil];
}

/* ---- the Language Modes panel ---- */

#define SAME_ITEM @"Same as general"
static const int mode_widths[] = { 2, 3, 4, 5, 6, 8 };
#define N_MODE_WIDTHS 6

static NSPopUpButton *tri_popup(NSRect r, id target, SEL action, BOOL widths)
{
    NSPopUpButton *p = [[[NSPopUpButton alloc] initWithFrame:r pullsDown:NO] autorelease];
    int i;

    [p addItemWithTitle:SAME_ITEM];
    if (widths) {
        for (i = 0; i < N_MODE_WIDTHS; i++) [p addItemWithTitle:[NSString stringWithFormat:@"%d", mode_widths[i]]];
    } else {
        [p addItemWithTitle:@"On"];
        [p addItemWithTitle:@"Off"];
    }
    [p setTarget:target];
    [p setAction:action];
    return p;
}

- (void)buildModePanel
{
    NSView *cv;
    NSArray *names = [owner modeNames];
    unsigned int i;

    modePanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 360, 248)
                                           styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                             backing:NSBackingStoreBuffered defer:NO];
    [modePanel setTitle:@"Language Modes"];
    [modePanel setReleasedWhenClosed:NO];
    cv = [modePanel contentView];
    [cv addSubview:ui_label(@"Mode:", NSMakeRect(16, 212, 90, 18))];
    modePopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(140, 208, 204, 24) pullsDown:NO] autorelease];
    for (i = 0; i < [names count]; i++) [modePopup addItemWithTitle:[names objectAtIndex:i]];
    [modePopup setTarget:self];
    [modePopup setAction:@selector(modeSelected:)];
    [cv addSubview:modePopup];
    [cv addSubview:ui_label(@"Indent width:", NSMakeRect(16, 176, 110, 18))];
    modeIndentPopup = tri_popup(NSMakeRect(140, 172, 204, 24), self, @selector(modeSettingChanged:), YES);
    [cv addSubview:modeIndentPopup];
    [cv addSubview:ui_label(@"Use spaces:", NSMakeRect(16, 142, 110, 18))];
    modeSpacesPopup = tri_popup(NSMakeRect(140, 138, 204, 24), self, @selector(modeSettingChanged:), NO);
    [cv addSubview:modeSpacesPopup];
    [cv addSubview:ui_label(@"Auto indent:", NSMakeRect(16, 108, 110, 18))];
    modeAutoPopup = tri_popup(NSMakeRect(140, 104, 204, 24), self, @selector(modeSettingChanged:), NO);
    [cv addSubview:modeAutoPopup];
    [cv addSubview:ui_label(@"Wrap lines:", NSMakeRect(16, 74, 110, 18))];
    modeWrapPopup = tri_popup(NSMakeRect(140, 70, 204, 24), self, @selector(modeSettingChanged:), NO);
    [cv addSubview:modeWrapPopup];
    [cv addSubview:ui_wrapping_label(@"A setting left at \"Same as general\" follows the Preferences menu. Windows in the mode change at once.",
                                     NSMakeRect(16, 36, 328, 30), NO)];
    [cv addSubview:ui_button(@"Close", NSMakeRect(274, 4, 70, 28), self, @selector(closeModePanel:))];
    [modePanel center];
}

/* Shows what the chosen mode overrides. */
- (void)syncModeControls
{
    NSString *m = [modePopup titleOfSelectedItem];
    int w = [owner modeSetting:MP_INDENT forMode:m], v;

    if (w == MP_UNSET) [modeIndentPopup selectItemWithTitle:SAME_ITEM];
    else [modeIndentPopup selectItemWithTitle:[NSString stringWithFormat:@"%d", w]];
    v = [owner modeSetting:MP_SPACES forMode:m];
    [modeSpacesPopup selectItemWithTitle:v == MP_UNSET ? SAME_ITEM : (v ? @"On" : @"Off")];
    v = [owner modeSetting:MP_AUTO forMode:m];
    [modeAutoPopup selectItemWithTitle:v == MP_UNSET ? SAME_ITEM : (v ? @"On" : @"Off")];
    v = [owner modeSetting:MP_WRAP forMode:m];
    [modeWrapPopup selectItemWithTitle:v == MP_UNSET ? SAME_ITEM : (v ? @"On" : @"Off")];
}

- (void)showModePanel
{
    if (modePanel == nil) [self buildModePanel];
    [self syncModeControls];
    [modePanel makeKeyAndOrderFront:nil];
}

- (void)showModes:(id)sender
{
    [self showModePanel];
}

- (void)modeSelected:(id)sender
{
    [self syncModeControls];
}

static int popup_flag(NSPopUpButton *p)
{
    NSString *t = [p titleOfSelectedItem];

    if ([t isEqualToString:@"On"]) return 1;
    if ([t isEqualToString:@"Off"]) return 0;
    return MP_UNSET;
}

- (void)modeSettingChanged:(id)sender
{
    NSString *m = [modePopup titleOfSelectedItem];
    NSString *w = [modeIndentPopup titleOfSelectedItem];

    [owner setModeSetting:MP_INDENT value:[w isEqualToString:SAME_ITEM] ? MP_UNSET : [w intValue] forMode:m];
    [owner setModeSetting:MP_SPACES value:popup_flag(modeSpacesPopup) forMode:m];
    [owner setModeSetting:MP_AUTO value:popup_flag(modeAutoPopup) forMode:m];
    [owner setModeSetting:MP_WRAP value:popup_flag(modeWrapPopup) forMode:m];
}

- (void)closeModePanel:(id)sender
{
    [modePanel orderOut:nil];
}

/* ---- the Remote Editing panel ---- */

#define STEPSSH_ITEM @"StepSSH (stepssh)"
#define OPENSSH_ITEM @"OpenSSH (ssh)"

- (void)buildRemotePanel
{
    NSView *cv;

    remotePanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 420, 214)
                                            styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                              backing:NSBackingStoreBuffered defer:NO];
    [remotePanel setTitle:@"Remote Editing"];
    [remotePanel setReleasedWhenClosed:NO];
    cv = [remotePanel contentView];
    [cv addSubview:ui_label(@"Run:", NSMakeRect(16, 178, 90, 18))];
    remoteProgramPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(110, 174, 200, 24) pullsDown:NO] autorelease];
    [remoteProgramPopup addItemWithTitle:STEPSSH_ITEM];
    [remoteProgramPopup addItemWithTitle:OPENSSH_ITEM];
    [remoteProgramPopup setTarget:self];
    [remoteProgramPopup setAction:@selector(remoteProgramChanged:)];
    [cv addSubview:remoteProgramPopup];
    [cv addSubview:ui_label(@"Program:", NSMakeRect(16, 142, 90, 18))];
    remotePathField = ui_field(NSMakeRect(110, 140, 292, 22));
    [remotePathField setTarget:self];
    [remotePathField setAction:@selector(remoteFieldsChanged:)];
    [cv addSubview:remotePathField];
    [cv addSubview:ui_label(@"Arguments:", NSMakeRect(16, 110, 90, 18))];
    remoteExtraField = ui_field(NSMakeRect(110, 108, 292, 22));
    [remoteExtraField setTarget:self];
    [remoteExtraField setAction:@selector(remoteFieldsChanged:)];
    [cv addSubview:remoteExtraField];
    [cv addSubview:ui_wrapping_label(@"Remote files are read and written by running this program on the other machine (File > Open Remote). It must log in without asking anything: use a key (and, for OpenSSH, ssh-agent), and connect once from a terminal first so that the host key is known. Arguments such as -p 2222 or -i keyfile go before the host name.",
                                     NSMakeRect(16, 40, 388, 62), NO)];
    [cv addSubview:ui_button(@"Close", NSMakeRect(334, 8, 70, 28), self, @selector(closeRemotePanel:))];
    [remotePanel center];
}

- (void)showRemote:(id)sender
{
    [self showRemotePanel];
}

- (void)showRemotePanel
{
    int which = [Appearance remoteProgram];

    if (remotePanel == nil) [self buildRemotePanel];
    [remoteProgramPopup selectItemWithTitle:which == 1 ? OPENSSH_ITEM : STEPSSH_ITEM];
    [remotePathField setStringValue:[Appearance remotePathFor:which]];
    [remoteExtraField setStringValue:[Appearance remoteExtra]];
    [remotePanel makeKeyAndOrderFront:nil];
}

- (void)remoteFieldsChanged:(id)sender
{
    int which = [[remoteProgramPopup titleOfSelectedItem] isEqualToString:OPENSSH_ITEM] ? 1 : 0;

    [Appearance setRemoteProgram:which];
    [Appearance setRemotePath:ui_trim([remotePathField stringValue]) for:which];
    [Appearance setRemoteExtra:ui_trim([remoteExtraField stringValue])];
    [Appearance saveSettings];
}

- (void)remoteProgramChanged:(id)sender
{
    int which = [[remoteProgramPopup titleOfSelectedItem] isEqualToString:OPENSSH_ITEM] ? 1 : 0;

    [Appearance setRemotePath:ui_trim([remotePathField stringValue]) for:[Appearance remoteProgram]];     /* what was typed for the one we leave */
    [Appearance setRemoteProgram:which];                     /* the paths of both are kept; only the one shown changes */
    [remotePathField setStringValue:[Appearance remotePathFor:which]];
    [Appearance saveSettings];
}

- (void)closeRemotePanel:(id)sender
{
    [self remoteFieldsChanged:nil];
    [remotePanel orderOut:nil];
}

/* ---- the Markdown panel ---- */

- (void)buildMarkdownPanel
{
    NSView *cv;

    mdPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 190)
                                         styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                           backing:NSBackingStoreBuffered defer:NO];
    [mdPanel setTitle:@"Markdown Preview"];
    [mdPanel setReleasedWhenClosed:NO];
    cv = [mdPanel contentView];
    [cv addSubview:ui_label(@"Accents:", NSMakeRect(16, 154, 90, 18))];
    mdCharsetPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(110, 150, 250, 24) pullsDown:NO] autorelease];
    [mdCharsetPopup addItemWithTitle:@"Windows-1252"];
    [mdCharsetPopup addItemWithTitle:@"NeXTSTEP"];
    [mdCharsetPopup addItemWithTitle:@"ASCII only (\\u escapes)"];
    [mdCharsetPopup setTarget:self];
    [mdCharsetPopup setAction:@selector(markdownChanged:)];
    [cv addSubview:mdCharsetPopup];
    [cv addSubview:ui_label(@"Links:", NSMakeRect(16, 120, 90, 18))];
    mdLinksPopup = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(110, 116, 250, 24) pullsDown:NO] autorelease];
    [mdLinksPopup addItemWithTitle:@"Show the text"];
    [mdLinksPopup addItemWithTitle:@"Show the address"];
    [mdLinksPopup addItemWithTitle:@"Text (address)"];
    [mdLinksPopup setTarget:self];
    [mdLinksPopup setAction:@selector(markdownChanged:)];
    [cv addSubview:mdLinksPopup];
    [cv addSubview:ui_wrapping_label(@"If accented letters come out wrong in the preview, try the other encoding. The preview opens from Windows > Markdown Preview.",
                                     NSMakeRect(16, 44, 348, 62), NO)];
    [cv addSubview:ui_button(@"Close", NSMakeRect(294, 8, 70, 28), self, @selector(closeMarkdownPanel:))];
    [mdPanel center];
}

- (void)showMarkdown:(id)sender
{
    [self showMarkdownPanel];
}

- (void)showMarkdownPanel
{
    if (mdPanel == nil) [self buildMarkdownPanel];
    [mdCharsetPopup selectItemAtIndex:[Appearance previewCharset]];
    [mdLinksPopup selectItemAtIndex:[Appearance previewLinks]];
    [mdPanel makeKeyAndOrderFront:nil];
}

- (void)markdownChanged:(id)sender
{
    [Appearance setPreviewCharset:[mdCharsetPopup indexOfSelectedItem]];
    [Appearance setPreviewLinks:[mdLinksPopup indexOfSelectedItem]];
    [Appearance saveSettings];
    if ([owner respondsToSelector:@selector(previewSettingsChanged)]) [owner previewSettingsChanged];
}

- (void)closeMarkdownPanel:(id)sender
{
    [mdPanel orderOut:nil];
}

@end
