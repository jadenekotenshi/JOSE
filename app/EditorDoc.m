#import "EditorDoc.h"
#import "UIHelpers.h"
#import "AppController.h"
#include "langmodes.h"
#include "eol.h"
#include <stdlib.h>
#include <string.h>

#define STATUS_H 18.0
#define WINDOW_W 640.0
#define WINDOW_H 480.0

@implementation EditTextView

- (void)setHighlighter:(HKSyntaxHighlighter *)h
{
    highlighter = h;
}

/* Colour what is about to be drawn (and only that: a big file is never coloured as a whole). */
- (void)drawRect:(NSRect)frame
{
    if (highlighter != nil) {
        NSLayoutManager *lm = [self layoutManager];
        NSRange drawn;

        SSTrace("draw: layout for y=%d h=%d ...", (int)frame.origin.y, (int)frame.size.height);
        drawn = [lm glyphRangeForBoundingRect:frame inTextContainer:[self textContainer]];
        SSTrace("draw: glyphs %u+%u laid out, highlighting", drawn.location, drawn.length);
        [highlighter highlightRange:drawn];
        SSTrace("draw: highlighted");
    }
    [super drawRect:frame];
}

@end

/* The 1-based line and column of an offset (a tab counts as one column). */
static void line_col(NSString *s, unsigned int loc, unsigned int *line, unsigned int *col)
{
    unichar buf[512];
    unsigned int pos = 0, n = [s length], l = 1, lineStart = 0, got, i;

    if (loc > n) loc = n;
    while (pos < loc) {
        got = loc - pos;
        if (got > 512) got = 512;
        [s getCharacters:buf range:NSMakeRange(pos, got)];
        for (i = 0; i < got; i++)
            if (buf[i] == '\n') { l++; lineStart = pos + i + 1; }
        pos += got;
    }
    *line = l;
    *col = loc - lineStart + 1;
}

@interface EditorDoc (Private)
- (void)applyStep:(const UndoStep *)step undoing:(BOOL)undoing;
- (void)markEdited;
- (unsigned long)nowMillis;
- (void)recordEditInRange:(NSRange)range replacement:(NSString *)replacement;
- (void)updateTitle;
- (void)updateStatus;
- (void)buildWindow;
- (void)applyFont;
- (BOOL)writeTo:(NSString *)aPath;
- (void)textDidChange:(NSNotification *)notification;
- (void)textViewDidChangeSelection:(NSNotification *)notification;
- (BOOL)windowShouldClose:(id)sender;
- (void)windowWillClose:(NSNotification *)notification;
@end

@implementation EditorDoc

- (id)initWithOwner:(id)anOwner
{
    self = [super init];
    if (self) {
        owner = anOwner;
        wrap = NO;
        undo = undo_new(2000, 2000000UL);
        clockBase = [NSDate timeIntervalSinceReferenceDate];
        [self buildWindow];
        [self setMode:nil];
        [self updateTitle];
        [self updateStatus];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [highlighter detach];
    [highlighter release];
    undo_free(undo);
    [path release];
    [mode release];
    [super dealloc];
}

- (void)buildWindow
{
    NSRect content = NSMakeRect(0, 0, WINDOW_W, WINDOW_H);
    NSSize cs;
    NSRect tvFrame;

    window = [[NSWindow alloc] initWithContentRect:content
                                         styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    [window setReleasedWhenClosed:NO];
    [window setDelegate:self];

    scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, STATUS_H, WINDOW_W, WINDOW_H - STATUS_H)] autorelease];
    [scroll setHasVerticalScroller:YES];
    [scroll setHasHorizontalScroller:YES];
    [scroll setBorderType:NSNoBorder];
    [scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

    cs = [scroll contentSize];
    tvFrame = NSMakeRect(0, 0, cs.width, cs.height);
    textView = [[[EditTextView alloc] initWithFrame:tvFrame] autorelease];
    [textView setMinSize:NSMakeSize(0.0, cs.height)];
    [textView setMaxSize:NSMakeSize(1.0e7, 1.0e7)];
    [textView setVerticallyResizable:YES];
    [textView setHorizontallyResizable:YES];
    [textView setAutoresizingMask:NSViewNotSizable];
    [[textView textContainer] setContainerSize:NSMakeSize(1.0e7, 1.0e7)];
    [[textView textContainer] setWidthTracksTextView:NO];
    [textView setRichText:NO];
    [textView setDelegate:self];
    [scroll setDocumentView:textView];
    [self applyFont];
    [[window contentView] addSubview:scroll];

    status = ui_label(@"", NSMakeRect(4.0, 0.0, WINDOW_W - 8.0, STATUS_H));
    [status setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
    [[window contentView] addSubview:status];
    [window makeFirstResponder:textView];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowWillClose:)
                                                 name:NSWindowWillCloseNotification object:window];
}

- (void)applyFont
{
    [textView setFont:[HKSyntaxHighlighter defaultFont]];
}

- (void)showWindow
{
    [window makeKeyAndOrderFront:nil];
}

- (NSWindow *)window { return window; }
- (EditTextView *)textView { return textView; }
- (NSString *)path { return path; }
- (NSString *)mode { return mode; }
- (BOOL)isDirty { return dirty; }
- (BOOL)wrap { return wrap; }

- (void)updateTitle
{
    NSString *name = path != nil ? [path lastPathComponent] : @"Untitled";

    if (path != nil) [window setTitleWithRepresentedFilename:path];
    else [window setTitle:name];
    [window setDocumentEdited:dirty];
}

- (void)updateStatus
{
    unsigned int line, col;
    NSRange sel = [textView selectedRange];

    line_col([textView string], sel.location, &line, &col);
    [status setStringValue:[NSString stringWithFormat:@"Line %u, col %u    %@    %@", line, col,
                            mode != nil ? mode : @"Plain Text", eol == 1 ? @"CRLF" : (eol == 2 ? @"CR" : @"LF")]];
}

- (unsigned long)nowMillis
{
    return (unsigned long)(([NSDate timeIntervalSinceReferenceDate] - clockBase) * 1000.0);
}

/* The change is about to happen: remember what it replaces, so that it can be undone. */
/* Remembers an edit that is about to happen on the history. */
- (void)recordEditInRange:(NSRange)range replacement:(NSString *)replacement
{
    unsigned int nrem = range.length, nins = replacement != nil ? [replacement length] : 0;
    u16 *rem = NULL, *ins = NULL;

    if (nrem > 0) {
        rem = (u16 *)malloc(nrem * sizeof(u16));
        if (rem != NULL) [[textView string] getCharacters:rem range:range];
        else nrem = 0;
    }
    if (nins > 0) {
        ins = (u16 *)malloc(nins * sizeof(u16));
        if (ins != NULL) [replacement getCharacters:ins];
        else nins = 0;
    }
    undo_record(undo, range.location, rem, nrem, ins, nins, [self nowMillis]);
    free(rem);
    free(ins);
    expectedCaret = range.location + nins;
}

- (BOOL)textView:(NSTextView *)tv shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)replacement
{
    if (replacement == nil) return YES;                        /* attributes only */
    [self recordEditInRange:range replacement:replacement];
    return YES;
}

- (void)markEdited
{
    BOOL d = undo_version(undo) != savedVersion;

    if (d != dirty) {
        dirty = d;
        [self updateTitle];
    }
}

- (void)textDidChange:(NSNotification *)notification
{
    [self markEdited];
    [self updateStatus];
}

/* Moving the insertion point away from where the typing was ends the step being built. */
- (void)textViewDidChangeSelection:(NSNotification *)notification
{
    NSRange sel = [textView selectedRange];

    if (sel.length > 0 || sel.location != expectedCaret) undo_break(undo);
    [self updateStatus];
}

- (BOOL)canUndo { return undo_can_undo(undo); }
- (BOOL)canRedo { return undo_can_redo(undo); }

/* Puts the text back as the step describes: replace the units it inserted by the ones it removed (undoing), or the reverse. */
- (void)applyStep:(const UndoStep *)step undoing:(BOOL)undoing
{
    NSTextStorage *ts = [textView textStorage];
    const u16 *with = undoing ? step->removed : step->inserted;
    unsigned int nwith = undoing ? step->nremoved : step->ninserted;
    unsigned int nold = undoing ? step->ninserted : step->nremoved;
    NSString *str = nwith > 0 ? [NSString stringWithCharacters:with length:nwith] : @"";

    [ts replaceCharactersInRange:NSMakeRange(step->pos, nold) withString:str];
    expectedCaret = step->pos + nwith;
    [textView setSelectedRange:NSMakeRange(expectedCaret, 0)];
    [textView scrollRangeToVisible:NSMakeRange(expectedCaret, 0)];
    [self markEdited];
    [self updateStatus];
}

- (void)undo
{
    UndoStep step;

    if (undo_undo(undo, &step)) [self applyStep:&step undoing:YES];
}

- (void)redo
{
    UndoStep step;

    if (undo_redo(undo, &step)) [self applyStep:&step undoing:NO];
}

/* ---- language mode ---- */

- (void)setMode:(NSString *)aMode
{
    NSTextStorage *ts = [textView textStorage];

    [highlighter detach];
    [textView setHighlighter:nil];
    [highlighter release];
    highlighter = nil;
    [mode release];
    mode = [aMode copy];
    if ([ts length] > 0) {                      /* clear what the old mode coloured */
        NSRange all = NSMakeRange(0, [ts length]);
        [ts addAttribute:NSForegroundColorAttributeName value:[NSColor blackColor] range:all];
        [ts addAttribute:NSFontAttributeName value:[HKSyntaxHighlighter defaultFont] range:all];
    }
    if (mode != nil) {
        highlighter = [[HKSyntaxHighlighter alloc] initWithHighlighterType:mode textStorage:ts defaultTextColor:[NSColor blackColor]];
        if (highlighter == nil) { [mode release]; mode = nil; }
    }
    [textView setHighlighter:highlighter];
    [textView setNeedsDisplay:YES];
    [self updateStatus];
}

- (void)setWrap:(BOOL)flag
{
    NSSize cs = [scroll contentSize];

    wrap = flag;
    [scroll setHasHorizontalScroller:!flag];
    [[textView textContainer] setWidthTracksTextView:flag];
    if (flag) {
        [textView setHorizontallyResizable:NO];
        [textView setAutoresizingMask:NSViewWidthSizable];
        [[textView textContainer] setContainerSize:NSMakeSize(cs.width, 1.0e7)];
        [textView setFrameSize:NSMakeSize(cs.width, [textView frame].size.height)];
    } else {
        [textView setHorizontallyResizable:YES];
        [textView setAutoresizingMask:NSViewNotSizable];
        [[textView textContainer] setContainerSize:NSMakeSize(1.0e7, 1.0e7)];
    }
    [textView setNeedsDisplay:YES];
}

/* ---- reading and writing ---- */

/* The file's bytes as text: UTF-8 if it is, Latin-1 where it is not (see ui_string_from_utf8). */
- (BOOL)openFile:(NSString *)aPath
{
    NSData *data = [NSData dataWithContentsOfFile:aPath];
    NSString *text;
    NSString *firstLine;
    NSRange r;
    char *bytes;
    unsigned int n;
    int mixed = 0;
    const char *m;

    if (data == nil) {
        NSRunAlertPanel(@"Open", @"%@ could not be read.", @"OK", nil, nil, aPath);
        return NO;
    }
    n = [data length];
    bytes = (char *)malloc(n + 1);
    if (bytes == NULL) return NO;
    [data getBytes:bytes];
    eol = eol_detect(bytes, n, &mixed);
    n = eol_normalize(bytes, n);                               /* one LF per line; a NUL (which would cut the text short) becomes a space */
    bytes[n] = '\0';
    text = ui_string_from_utf8(bytes);
    free(bytes);

    [path release];
    path = [aPath copy];
    [textView setString:text];
    undo_clear(undo);
    savedVersion = undo_version(undo);
    dirty = NO;
    r = [text lineRangeForRange:NSMakeRange(0, 0)];
    firstLine = [text substringWithRange:r];
    m = lang_mode_for(UI_CPATH(path), UI_CPATH(firstLine));
    [self setMode:m != NULL ? [NSString stringWithCString:m] : nil];
    [self updateTitle];
    [self updateStatus];
    return YES;
}

- (BOOL)writeTo:(NSString *)aPath
{
    NSData *enc = ui_utf8_cstring([textView string]);          /* UTF-8, plus a NUL we do not write */
    unsigned int n = [enc length] - 1;
    size_t outn = eol_expanded_size((const char *)[enc bytes], n, eol);
    char *buf = (char *)malloc(outn + 1);
    NSData *out;
    BOOL ok;

    if (buf == NULL) return NO;
    outn = eol_expand((const char *)[enc bytes], n, eol, buf);
    out = [NSData dataWithBytes:buf length:outn];
    free(buf);
    ok = [out writeToFile:aPath atomically:YES];
    if (!ok) NSRunAlertPanel(@"Save", @"%@ could not be written.", @"OK", nil, nil, aPath);
    return ok;
}

- (BOOL)save
{
    if (path == nil) return [self saveAs];
    if (![self writeTo:path]) return NO;
    undo_break(undo);
    savedVersion = undo_version(undo);
    dirty = NO;
    [self updateTitle];
    return YES;
}

- (BOOL)saveAs
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    NSString *dir = path != nil ? [path stringByDeletingLastPathComponent] : NSHomeDirectory();
    NSString *file = path != nil ? [path lastPathComponent] : @"Untitled";

    if ([panel runModalForDirectory:dir file:file] != NSOKButton) return NO;
    if (![self writeTo:[panel filename]]) return NO;
    [path release];
    path = [[panel filename] copy];
    undo_break(undo);
    savedVersion = undo_version(undo);
    dirty = NO;
    if (mode == nil) {
        const char *m = lang_mode_for(UI_CPATH(path), NULL);
        if (m != NULL) [self setMode:[NSString stringWithCString:m]];
    }
    [self updateTitle];
    return YES;
}

- (BOOL)revert
{
    NSString *p = [[path copy] autorelease];

    if (p == nil) return NO;
    return [self openFile:p];
}

/* ---- closing ---- */

- (BOOL)confirmClose
{
    int answer;

    if (!dirty) return YES;
    answer = NSRunAlertPanel(@"Close", @"Save changes to %@?", @"Save", @"Don't Save", @"Cancel",
                             path != nil ? [path lastPathComponent] : @"Untitled");
    if (answer == NSAlertDefaultReturn) return [self save];
    if (answer == NSAlertAlternateReturn) return YES;
    return NO;
}

- (BOOL)windowShouldClose:(id)sender
{
    return [self confirmClose];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [window setDelegate:nil];
    [owner documentDidClose:self];
}

- (BOOL)closeWindow
{
    if (![self confirmClose]) return NO;
    dirty = NO;
    [window close];
    return YES;
}

/* A programmatic edit (search and replace): one undo step of its own, then the text selected. */
- (void)replaceRange:(NSRange)range with:(NSString *)str select:(NSRange)sel
{
    undo_break(undo);
    [self recordEditInRange:range replacement:str];
    undo_break(undo);
    [[textView textStorage] replaceCharactersInRange:range withString:str];
    expectedCaret = range.location + [str length];
    [textView setSelectedRange:sel];
    [textView scrollRangeToVisible:sel];
    [self markEdited];
    [self updateStatus];
}

- (void)goToLine:(int)line
{
    NSString *s = [textView string];
    unsigned int pos = 0, n = [s length];
    int l = 1;
    NSRange r;

    while (l < line && pos < n) {
        r = [s lineRangeForRange:NSMakeRange(pos, 0)];
        if (NSMaxRange(r) <= pos) break;
        pos = NSMaxRange(r);
        l++;
    }
    [textView setSelectedRange:NSMakeRange(pos, 0)];
    [textView scrollRangeToVisible:NSMakeRange(pos, 0)];
    [window makeFirstResponder:textView];
}

@end
