#import "FindController.h"
#import "AppController.h"
#import "EditorDoc.h"
#import "UIHelpers.h"
#include <stdlib.h>
#include <string.h>

@interface FindController (Private)
- (void)buildPanel;
- (EditorDoc *)document;
- (Search *)compiledSearch;
- (BOOL)doFind:(BOOL)forward;
- (int)flags;
- (BOOL)literalReplacement;
- (void)replaceBetween:(unsigned int)lo and:(unsigned int)hi what:(NSString *)what;
- (void)say:(NSString *)text;
- (void)findNext:(id)sender;
- (void)findPrev:(id)sender;
- (void)replaceOne:(id)sender;
- (void)replaceAndFind:(id)sender;
- (void)replaceAll:(id)sender;
- (void)replaceInSelection:(id)sender;
- (void)closePanel:(id)sender;
@end

/* An NSString as a malloc'd array of UTF-16 units (the caller frees it). */
static u16 *units_of(NSString *s, unsigned int *n)
{
    u16 *buf;

    *n = [s length];
    buf = (u16 *)malloc((*n + 1) * sizeof(u16));
    if (buf != NULL && *n > 0) [s getCharacters:buf];
    return buf;
}

@implementation FindController

- (id)initWithOwner:(id)anOwner
{
    self = [super init];
    owner = anOwner;
    return self;
}

- (void)dealloc
{
    search_free(cached);
    [cachedPattern release];
    [super dealloc];
}

- (EditorDoc *)document
{
    return [(AppController *)owner frontDocument];
}

- (void)say:(NSString *)text
{
    if (message != nil) [message setStringValue:text];
}

- (void)buildPanel
{
    NSView *c;

    if (panel != nil) return;
    panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 470, 226)
                                       styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                         backing:NSBackingStoreBuffered defer:NO];
    [panel setTitle:@"Find and Replace"];
    [panel setFloatingPanel:YES];
    [panel setReleasedWhenClosed:NO];
    c = [panel contentView];
    [c addSubview:ui_label(@"Find:", NSMakeRect(14, 192, 70, 18))];
    findField = ui_field(NSMakeRect(90, 190, 366, 22));
    [findField setTarget:self];
    [findField setAction:@selector(findNext:)];
    [c addSubview:findField];
    [c addSubview:ui_label(@"Replace with:", NSMakeRect(14, 160, 76, 18))];
    replaceField = ui_field(NSMakeRect(90, 158, 366, 22));
    [c addSubview:replaceField];
    caseSwitch = ui_switch(@"Case sensitive", NSMakeRect(14, 128, 140, 20));
    regexSwitch = ui_switch(@"Regular expression", NSMakeRect(160, 128, 160, 20));
    wordSwitch = ui_switch(@"Whole word", NSMakeRect(326, 128, 130, 20));
    wrapSwitch = ui_switch(@"Wrap around", NSMakeRect(14, 102, 140, 20));
    [wrapSwitch setState:NSOnState];
    [c addSubview:caseSwitch];
    [c addSubview:regexSwitch];
    [c addSubview:wordSwitch];
    [c addSubview:wrapSwitch];
    [c addSubview:ui_button(@"Find Next", NSMakeRect(14, 62, 106, 28), self, @selector(findNext:))];
    [c addSubview:ui_button(@"Find Previous", NSMakeRect(124, 62, 106, 28), self, @selector(findPrev:))];
    [c addSubview:ui_button(@"Replace", NSMakeRect(234, 62, 106, 28), self, @selector(replaceOne:))];
    [c addSubview:ui_button(@"Replace & Find", NSMakeRect(344, 62, 112, 28), self, @selector(replaceAndFind:))];
    [c addSubview:ui_button(@"Replace All", NSMakeRect(14, 28, 106, 28), self, @selector(replaceAll:))];
    [c addSubview:ui_button(@"In Selection", NSMakeRect(124, 28, 106, 28), self, @selector(replaceInSelection:))];
    [c addSubview:ui_button(@"Close", NSMakeRect(350, 28, 106, 28), self, @selector(closePanel:))];
    message = ui_label(@"", NSMakeRect(14, 6, 442, 18));
    [c addSubview:message];
    [panel center];
}

- (void)showPanel
{
    EditorDoc *d = [self document];

    [self buildPanel];
    if (d != nil) {                                 /* start from the selected text, if there is one on a single line */
        NSRange sel = [[d textView] selectedRange];
        if (sel.length > 0 && sel.length < 200) {
            NSString *t = [[[d textView] string] substringWithRange:sel];
            if ([t rangeOfString:@"\n"].length == 0) [findField setStringValue:t];
        }
    }
    [self say:@""];
    [panel makeKeyAndOrderFront:nil];
    [panel makeFirstResponder:findField];
    [findField selectText:nil];
}

- (void)closePanel:(id)sender
{
    [panel orderOut:nil];
}

- (int)flags
{
    int f = 0;

    if ([regexSwitch state] == NSOnState) f |= SEARCH_REGEX;
    if ([caseSwitch state] != NSOnState) f |= SEARCH_ICASE;
    if ([wordSwitch state] == NSOnState) f |= SEARCH_WORD;
    return f;
}

/* The search for the panel's current text and switches, compiled (and kept for next time).  nil, with a message, if the
 * pattern is empty or not valid. */
- (Search *)compiledSearch
{
    NSString *pat;
    int flags;
    u16 *u;
    unsigned int n;
    char err[100];

    [self buildPanel];
    pat = [findField stringValue];
    flags = [self flags];
    if (cached != NULL && cachedFlags == flags && cachedPattern != nil && [cachedPattern isEqualToString:pat]) return cached;
    search_free(cached);
    cached = NULL;
    [cachedPattern release];
    cachedPattern = nil;
    if ([pat length] == 0) { [self say:@"Type the text to find."]; return NULL; }
    u = units_of(pat, &n);
    if (u == NULL) { [self say:@"Out of memory."]; return NULL; }
    cached = search_new(u, n, flags, err, sizeof err);
    free(u);
    if (cached == NULL) {
        [self say:[NSString stringWithFormat:@"Bad pattern: %s", err]];
        return NULL;
    }
    cachedPattern = [pat copy];
    cachedFlags = flags;
    return cached;
}

/* Finds the next (or previous) match from the selection and selects it.  NO if there is none. */
- (BOOL)doFind:(BOOL)forward
{
    EditorDoc *d = [self document];
    Search *s;
    NSRange sel;
    u16 *text;
    unsigned int n, from;
    SearchMatch m;
    BOOL found;

    if (d == nil) return NO;
    s = [self compiledSearch];
    if (s == NULL) return NO;
    text = units_of([[d textView] string], &n);
    if (text == NULL) { [self say:@"Out of memory."]; return NO; }
    sel = [[d textView] selectedRange];
    from = forward ? NSMaxRange(sel) : sel.location;
    found = search_find(s, text, n, from, forward ? 1 : 0, [wrapSwitch state] == NSOnState, &m) != 0;
    free(text);
    if (!found) {
        [self say:@"Not found."];
        NSBeep();
        return NO;
    }
    [[d textView] setSelectedRange:NSMakeRange(m.start[0], m.end[0] - m.start[0])];
    [[d textView] scrollRangeToVisible:NSMakeRange(m.start[0], m.end[0] - m.start[0])];
    [self say:@""];
    [[d window] makeKeyAndOrderFront:nil];
    return YES;
}

- (void)findNext:(id)sender { [self doFind:YES]; }
- (void)findPrev:(id)sender { [self doFind:NO]; }

- (void)findAgain
{
    [self buildPanel];
    if ([[findField stringValue] length] == 0) { [self showPanel]; return; }
    [self doFind:YES];
}

- (void)findPrevious
{
    [self buildPanel];
    if ([[findField stringValue] length] == 0) { [self showPanel]; return; }
    [self doFind:NO];
}

- (void)findSelection
{
    EditorDoc *d = [self document];
    NSRange sel;

    if (d == nil) return;
    sel = [[d textView] selectedRange];
    [self buildPanel];
    if (sel.length > 0) {
        [findField setStringValue:[[[d textView] string] substringWithRange:sel]];
        [regexSwitch setState:NSOffState];              /* the selected text is literal text */
    }
    [self doFind:YES];
}

- (BOOL)literalReplacement
{
    return ([self flags] & SEARCH_REGEX) == 0;
}

/* Replaces the selection if it is a match of the search; otherwise looks for the next one. */
- (void)replaceOne:(id)sender
{
    EditorDoc *d = [self document];
    Search *s;
    NSRange sel;
    u16 *text, *repl, *out;
    unsigned int n, nrepl, nout;
    SearchMatch m;

    if (d == nil) return;
    s = [self compiledSearch];
    if (s == NULL) return;
    sel = [[d textView] selectedRange];
    text = units_of([[d textView] string], &n);
    repl = units_of([replaceField stringValue], &nrepl);
    if (text == NULL || repl == NULL) { free(text); free(repl); [self say:@"Out of memory."]; return; }
    if (search_match_at(s, text, n, sel.location, &m) && m.end[0] == NSMaxRange(sel)) {
        NSString *str;
        nout = search_expand(&m, text, repl, nrepl, [self literalReplacement], NULL, 0);
        out = (u16 *)malloc((nout + 1) * sizeof(u16));
        if (out != NULL) {
            search_expand(&m, text, repl, nrepl, [self literalReplacement], out, nout);
            str = nout > 0 ? [NSString stringWithCharacters:out length:nout] : @"";
            free(out);
            [d replaceRange:sel with:str select:NSMakeRange(sel.location + nout, 0)];
            [self say:@"Replaced."];
        }
    } else {
        free(text);
        free(repl);
        [self doFind:YES];
        return;
    }
    free(text);
    free(repl);
}

- (void)replaceAndFind:(id)sender
{
    [self replaceOne:sender];
    [self doFind:YES];
}

/* Replaces every match in [lo, hi) of the front document as one undoable edit. */
- (void)replaceBetween:(unsigned int)lo and:(unsigned int)hi what:(NSString *)what
{
    EditorDoc *d = [self document];
    Search *s;
    u16 *text, *repl, *out = NULL;
    unsigned int n, nrepl, nout = 0, first = 0, last = 0, count = 0;

    if (d == nil) return;
    s = [self compiledSearch];
    if (s == NULL) return;
    text = units_of([[d textView] string], &n);
    repl = units_of([replaceField stringValue], &nrepl);
    if (text == NULL || repl == NULL) { free(text); free(repl); [self say:@"Out of memory."]; return; }
    if (search_replace_all(s, text, n, lo, hi, repl, nrepl, [self literalReplacement], &out, &nout, &first, &last, &count)) {
        NSString *str = nout > 0 ? [NSString stringWithCharacters:out length:nout] : @"";
        [d replaceRange:NSMakeRange(first, last - first) with:str select:NSMakeRange(first, nout)];
        [self say:[NSString stringWithFormat:@"Replaced %u %@.", count, count == 1 ? @"match" : @"matches"]];
        [[d window] makeKeyAndOrderFront:nil];
    } else {
        [self say:[NSString stringWithFormat:@"Not found%@.", what]];
        NSBeep();
    }
    free(out);
    free(text);
    free(repl);
}

- (void)replaceAll:(id)sender
{
    EditorDoc *d = [self document];

    if (d != nil) [self replaceBetween:0 and:[[[d textView] string] length] what:@""];
}

- (void)replaceInSelection:(id)sender
{
    EditorDoc *d = [self document];
    NSRange sel;

    if (d == nil) return;
    sel = [[d textView] selectedRange];
    if (sel.length == 0) { [self say:@"Select the text to change first."]; NSBeep(); return; }
    [self replaceBetween:sel.location and:NSMaxRange(sel) what:@" in the selection"];
}

@end
