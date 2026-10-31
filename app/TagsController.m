#import "TagsController.h"
#import "EditorDoc.h"
#import "UIHelpers.h"
#import "Appearance.h"
#include "tags.h"
#include <stdlib.h>
#include <string.h>

#define MAX_JUMPS 50
#define TIP_SECONDS 12.0

/* One tags file that is loaded. */
@interface TagSet : NSObject
{
    NSString *path;
    NSDate   *stamp;
    Tags     *tags;
}
- (id)initWithPath:(NSString *)aPath;
- (NSString *)path;
- (NSString *)baseDirectory;
- (void)reloadIfChanged;
- (Tags *)tags;
@end

@implementation TagSet

- (NSDate *)modificationDate
{
    return [[[NSFileManager defaultManager] fileAttributesAtPath:path traverseLink:YES] fileModificationDate];
}

- (id)initWithPath:(NSString *)aPath
{
    self = [super init];
    if (self) {
        path = [aPath copy];
        stamp = [[self modificationDate] retain];
        tags = tags_load(UI_CPATH(path));
    }
    return self;
}

- (void)dealloc
{
    tags_free(tags);
    [path release];
    [stamp release];
    [super dealloc];
}

- (NSString *)path { return path; }
- (NSString *)baseDirectory { return [path stringByDeletingLastPathComponent]; }
- (Tags *)tags { return tags; }

- (void)reloadIfChanged
{
    NSDate *now = [self modificationDate];

    if (now != nil && (stamp == nil || ![now isEqual:stamp])) {
        tags_free(tags);
        tags = tags_load(UI_CPATH(path));
        [stamp release];
        stamp = [now retain];
    }
}

@end

@interface TagsController (Private)
- (BOOL)loadFileAtPath:(NSString *)p;
- (void)discoverFor:(EditorDoc *)d;
- (NSArray *)lookup:(NSString *)name;
- (void)jumpTo:(NSDictionary *)match;
- (void)showTipText:(NSString *)text nearChar:(unsigned int)idx in:(EditorDoc *)d;
- (void)choiceOK:(id)sender;
- (void)choiceCancel:(id)sender;
@end

@implementation TagsController

- (id)initWithOwner:(id)anOwner
{
    self = [super init];
    if (self) {
        owner = anOwner;
        sets = [[NSMutableArray alloc] init];
        jumps = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [sets release];
    [jumps release];
    [tipPanel release];
    [super dealloc];
}

/* ---- loading ---- */

- (BOOL)loadFileAtPath:(NSString *)p
{
    unsigned int i;
    TagSet *set;

    p = [p stringByStandardizingPath];
    for (i = 0; i < [sets count]; i++)
        if ([[[sets objectAtIndex:i] path] isEqualToString:p]) { [[sets objectAtIndex:i] reloadIfChanged]; return YES; }
    set = [[[TagSet alloc] initWithPath:p] autorelease];
    if ([set tags] == NULL) return NO;
    [sets addObject:set];
    return YES;
}

- (void)loadTagsFile
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    EditorDoc *d = [owner frontDocument];

    [panel setAllowsMultipleSelection:NO];
    if ([panel runModalForDirectory:(d != nil && [d path] != nil ? [[d path] stringByDeletingLastPathComponent] : NSHomeDirectory())
                               file:@"tags" types:nil] != NSOKButton) return;
    if (![self loadFileAtPath:[panel filename]])
        NSRunAlertPanel(@"Load Tags File", @"%@ could not be read.", @"OK", nil, nil, [panel filename]);
}

/* A file called `tags` in the document's folder or one above it (as far as eight levels up). */
- (void)discoverFor:(EditorDoc *)d
{
    NSString *dir;
    int level;

    if ([d path] == nil) return;
    dir = [[d path] stringByDeletingLastPathComponent];
    for (level = 0; level < 8 && [dir length] > 0; level++) {
        NSString *cand = [dir stringByAppendingPathComponent:@"tags"];
        BOOL isDir = NO;

        if ([[NSFileManager defaultManager] fileExistsAtPath:cand isDirectory:&isDir] && !isDir) {
            [self loadFileAtPath:cand];
            return;
        }
        if ([dir isEqualToString:@"/"]) break;
        dir = [dir stringByDeletingLastPathComponent];
    }
}

/* ---- lookup ---- */

/* The tags named `name` in every loaded file: dictionaries with name, path (full), line, pattern and tip. */
- (NSArray *)lookup:(NSString *)name
{
    NSMutableArray *found = [NSMutableArray array];
    const char *cname = UI_CPATH(name);
    unsigned int i;

    for (i = 0; i < [sets count]; i++) {
        TagSet *set = [sets objectAtIndex:i];
        unsigned int first, n, k;

        [set reloadIfChanged];
        if ([set tags] == NULL) continue;
        n = tags_find([set tags], cname, &first);
        for (k = 0; k < n; k++) {
            const Tag *tag = tags_at([set tags], first + k);
            char tip[256];
            NSMutableDictionary *m = [NSMutableDictionary dictionary];

            tags_tip(tag, tip, sizeof tip);
            [m setObject:name forKey:@"name"];
            [m setObject:[[[set baseDirectory] stringByAppendingPathComponent:ui_string_from_utf8(tag->file)] stringByStandardizingPath] forKey:@"path"];
            [m setObject:[NSNumber numberWithInt:tag->line] forKey:@"line"];
            if (tag->pattern != NULL) [m setObject:ui_string_from_utf8(tag->pattern) forKey:@"pattern"];
            [m setObject:ui_string_from_utf8(tip) forKey:@"tip"];
            [found addObject:m];
        }
    }
    return found;
}

/* ---- Find Definition ---- */

- (void)choiceOK:(id)sender { chosen = YES; [NSApp stopModalWithCode:NSOKButton]; }
- (void)choiceCancel:(id)sender { chosen = NO; [NSApp stopModalWithCode:NSCancelButton]; }

/* Which of several definitions?  A small modal panel with a pop-up; -1 if cancelled. */
- (int)chooseAmong:(NSArray *)matches
{
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 560, 100)
                                                styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                  backing:NSBackingStoreBuffered defer:NO];
    int result = -1;
    unsigned int i;

    [panel setTitle:@"Find Definition"];
    [[panel contentView] addSubview:ui_label([NSString stringWithFormat:@"%u definitions of %@:", (unsigned)[matches count],
                                              [[matches objectAtIndex:0] objectForKey:@"name"]], NSMakeRect(16, 72, 528, 18))];
    choice = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 44, 528, 24) pullsDown:NO] autorelease];
    for (i = 0; i < [matches count]; i++) {
        NSDictionary *m = [matches objectAtIndex:i];
        NSString *tip = [m objectForKey:@"tip"];
        NSString *title = [NSString stringWithFormat:@"%@: %@", [[m objectForKey:@"path"] lastPathComponent], tip];

        if ([title length] > 90) title = [title substringToIndex:90];
        [choice addItemWithTitle:[NSString stringWithFormat:@"%u. %@", i + 1, title]];      /* the number keeps equal titles apart */
    }
    [[panel contentView] addSubview:choice];
    [[panel contentView] addSubview:ui_button(@"Go", NSMakeRect(474, 8, 70, 28), self, @selector(choiceOK:))];
    [[panel contentView] addSubview:ui_button(@"Cancel", NSMakeRect(394, 8, 70, 28), self, @selector(choiceCancel:))];
    [panel center];
    chosen = NO;
    [NSApp runModalForWindow:panel];
    if (chosen) result = [choice indexOfSelectedItem];
    [panel close];
    [panel release];
    choice = nil;
    return result;
}

- (void)jumpTo:(NSDictionary *)m
{
    EditorDoc *from = [owner frontDocument], *to;
    int line = [[m objectForKey:@"line"] intValue];

    if (from != nil && [from path] != nil) {
        NSMutableDictionary *j = [NSMutableDictionary dictionary];

        [j setObject:[from path] forKey:@"path"];
        [j setObject:[NSNumber numberWithUnsignedInt:[[from textView] selectedRange].location] forKey:@"loc"];
        [jumps addObject:j];
        if ([jumps count] > MAX_JUMPS) [jumps removeObjectAtIndex:0];
    }
    to = [owner openPath:[m objectForKey:@"path"]];
    if (to == nil) { NSRunAlertPanel(@"Find Definition", @"%@ could not be opened.", @"OK", nil, nil, [m objectForKey:@"path"]); return; }
    [to revealLine:line pattern:[m objectForKey:@"pattern"] name:[m objectForKey:@"name"]];
}

- (void)findDefinition
{
    EditorDoc *d = [owner frontDocument];
    NSString *name;
    NSArray *matches;
    int pick = 0;

    if (d == nil) return;
    name = [d selectedString];
    if (name == nil || [name length] > 200 || [name rangeOfString:@"\n"].length > 0) name = [d wordAtCaret];
    name = ui_trim(name != nil ? name : @"");
    if ([name length] == 0) { NSBeep(); return; }
    [self discoverFor:d];
    matches = [self lookup:name];
    if ([matches count] == 0) {
        NSRunAlertPanel(@"Find Definition", @"No tag named \"%@\"%@", @"OK", nil, nil, name,
                        [sets count] == 0 ? @".\n\nThere is no tags file: make one with ctags in the project's folder, or use Load Tags File." : @".");
        return;
    }
    if ([matches count] > 1) pick = [self chooseAmong:matches];
    if (pick >= 0) [self jumpTo:[matches objectAtIndex:pick]];
}

- (void)returnFromDefinition
{
    NSDictionary *j;
    EditorDoc *d;
    unsigned int loc;

    if ([jumps count] == 0) { NSBeep(); return; }
    j = [[[jumps lastObject] retain] autorelease];
    [jumps removeLastObject];
    d = [owner openPath:[j objectForKey:@"path"]];
    if (d == nil) return;
    loc = [[j objectForKey:@"loc"] unsignedIntValue];
    if (loc > [[[d textView] string] length]) loc = [[[d textView] string] length];
    [[d textView] setSelectedRange:NSMakeRange(loc, 0)];
    [[d textView] scrollRangeToVisible:NSMakeRange(loc, 0)];
}

/* ---- call tips ---- */

- (void)hideCallTip
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideCallTip) object:nil];
    if (tipPanel != nil && [tipPanel isVisible]) [tipPanel orderOut:nil];
}

- (void)showTipText:(NSString *)text nearChar:(unsigned int)idx in:(EditorDoc *)d
{
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    NSFont *font = [NSFont userFixedPitchFontOfSize:11.0];
    float w = 40.0, lh = 15.0;
    unsigned int i;
    NSRect at = [d screenRectForCharAt:idx], r;

    for (i = 0; i < [lines count]; i++) {
        float lw = [font widthOfString:[lines objectAtIndex:i]];
        if (lw > w) w = lw;
    }
    if (w > 640.0) w = 640.0;
    w += 12.0;
    if (tipPanel == nil) {
        tipPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 100, 20) styleMask:NSBorderlessWindowMask
                                                backing:NSBackingStoreBuffered defer:NO];
        [tipPanel setReleasedWhenClosed:NO];
        [tipPanel setLevel:NSFloatingWindowLevel];
        tipField = ui_wrapping_label(@"", NSMakeRect(0, 0, 100, 20), NO);
        [tipField setBackgroundColor:[NSColor colorWithCalibratedRed:1.0 green:1.0 blue:0.78 alpha:1.0]];
        [tipField setTextColor:[NSColor blackColor]];
        [tipField setDrawsBackground:YES];
        [tipField setFont:font];
        [[tipPanel contentView] addSubview:tipField];
    }
    r = NSMakeRect(at.origin.x, at.origin.y - lh * (float)[lines count] - 8.0, w, lh * (float)[lines count] + 6.0);
    [tipPanel setFrame:r display:NO];
    [tipField setFrame:NSMakeRect(0, 0, r.size.width, r.size.height)];
    [tipField setStringValue:text];
    [tipPanel orderFront:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideCallTip) object:nil];
    [self performSelector:@selector(hideCallTip) withObject:nil afterDelay:TIP_SECONDS];
}

/* The tips for `name` (the different declarations, up to four) shown under character `idx`. */
- (BOOL)showTipForName:(NSString *)name near:(unsigned int)idx in:(EditorDoc *)d
{
    NSArray *matches;
    NSMutableArray *tips = [NSMutableArray array];
    unsigned int i;

    [self discoverFor:d];
    matches = [self lookup:name];
    for (i = 0; i < [matches count] && [tips count] < 4; i++) {
        NSString *tip = [[matches objectAtIndex:i] objectForKey:@"tip"];
        if (![tips containsObject:tip]) [tips addObject:tip];
    }
    if ([tips count] == 0) return NO;
    [self showTipText:[tips componentsJoinedByString:@"\n"] nearChar:idx in:d];
    return YES;
}

- (void)showCallTip
{
    EditorDoc *d = [owner frontDocument];
    NSString *name;
    unsigned int at;

    if (d == nil) return;
    name = [d wordBeforeParenAt:&at];
    if (name == nil) name = [d wordAtCaret];
    if (name == nil || [name length] == 0 || ![self showTipForName:name near:at in:d]) NSBeep();
}

- (void)showCallTipAfterParenIn:(EditorDoc *)d
{
    NSString *name;
    unsigned int at;

    if (![Appearance callTips] || d == nil) return;
    name = [d wordBeforeParenAt:&at];
    if (name != nil) [self showTipForName:name near:at in:d];
}

@end
