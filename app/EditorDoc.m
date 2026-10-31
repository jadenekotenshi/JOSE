#import "EditorDoc.h"
#import "UIHelpers.h"
#import "AppController.h"
#import "LineNumberView.h"
#include "langmodes.h"
#include "eol.h"
#include "edit.h"
#include "brace.h"
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

- (void)setEditor:(id)anEditor
{
    editor = anEditor;
}

- (void)insertNewline:(id)sender
{
    if (![(EditorDoc *)editor newlineWithIndent]) [super insertNewline:sender];
}

- (void)insertTab:(id)sender
{
    if (![(EditorDoc *)editor tabInsertedSpaces]) [super insertTab:sender];
}

- (void)insertText:(id)str
{
    if ([str isKindOfClass:[NSString class]]) [(EditorDoc *)editor willInsertText:str];
    [super insertText:str];
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
- (unsigned int)lineBeforeCaret:(u16 **)prefix;
- (NSRange)selectedLines:(NSRange)sel;
- (void)replaceLines:(NSRange)region with:(u16 *)buf length:(unsigned int)n selection:(NSRange)sel;
- (void)markEdited;
- (unsigned long)nowMillis;
- (void)recordEditInRange:(NSRange)range replacement:(NSString *)replacement;
- (void)noteLineChangeAt:(unsigned int)loc removed:(const u16 *)rem count:(unsigned int)nrem inserted:(const u16 *)ins count:(unsigned int)nins;
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
        autoIndent = YES;
        useSpaces = NO;
        indentWidth = 4;
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
    [ruler release];
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
    [textView setEditor:self];
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
/* Tells the line-number ruler (if there is one) that text changed. */
- (void)noteLineChangeAt:(unsigned int)loc removed:(const u16 *)rem count:(unsigned int)nrem inserted:(const u16 *)ins count:(unsigned int)nins
{
    unsigned int i, r = 0, a = 0;

    if (ruler == nil) return;
    for (i = 0; i < nrem; i++) if (rem[i] == '\n') r++;
    for (i = 0; i < nins; i++) if (ins[i] == '\n') a++;
    [ruler textChangedAt:loc removedNewlines:r insertedNewlines:a];
}

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
    [self noteLineChangeAt:range.location removed:rem count:nrem inserted:ins count:nins];
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
    [self noteLineChangeAt:step->pos removed:(undoing ? step->inserted : step->removed) count:nold inserted:with count:nwith];
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
    [ruler textReplaced];
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

/* ---- line numbers and brackets ---- */

- (BOOL)lineNumbers { return lineNumbers; }

- (void)setLineNumbers:(BOOL)flag
{
    lineNumbers = flag;
    if (flag && ruler == nil) {
        if (![scroll respondsToSelector:@selector(setVerticalRulerView:)]) { SSTrace("line numbers: no scroll view rulers here"); lineNumbers = NO; return; }
        ruler = [[LineNumberView alloc] initWithScrollView:scroll textView:textView];
        [scroll setVerticalRulerView:ruler];
        [scroll setHasVerticalRuler:YES];
        [ruler textReplaced];
    }
    if (ruler != nil) {
        [scroll setRulersVisible:flag];
        if (flag) [ruler textReplaced];
    }
}

- (void)gotoMatchingBracket:(BOOL)select
{
    NSString *s = [textView string];
    NSRange sel = [textView selectedRange];
    unsigned int n = [s length], pos, match;
    u16 *t;
    BOOL found = NO;

    if (n == 0) { NSBeep(); return; }
    t = (u16 *)malloc(n * sizeof(u16));
    if (t == NULL) return;
    [s getCharacters:t];
    pos = sel.location;
    if (pos < n && brace_is_bracket(t[pos])) found = YES;
    else if (pos > 0 && pos <= n && brace_is_bracket(t[pos - 1])) { pos--; found = YES; }
    if (found)
        found = brace_match(t, n, pos, lang_c_like(mode != nil ? [mode cString] : NULL), &match) != 0;
    free(t);
    if (!found) { NSBeep(); return; }
    if (select) {
        unsigned int lo = pos < match ? pos : match, hi = pos < match ? match : pos;
        [textView setSelectedRange:NSMakeRange(lo, hi + 1 - lo)];
    } else {
        [textView setSelectedRange:NSMakeRange(match > pos ? match + 1 : match, 0)];       /* ends where a second use returns */
    }
    [textView scrollRangeToVisible:[textView selectedRange]];
}

/* ---- indentation and commenting ---- */

- (void)setAutoIndent:(BOOL)flag { autoIndent = flag; }
- (BOOL)autoIndent { return autoIndent; }
- (void)setUseSpaces:(BOOL)flag { useSpaces = flag; }
- (BOOL)useSpaces { return useSpaces; }
- (void)setIndentWidth:(int)width { indentWidth = width < 1 ? 1 : (width > 16 ? 16 : width); }
- (int)indentWidth { return indentWidth; }

/* The text of the caret's line up to the caret (malloc'd, *prefix; the caller frees it); its length. */
- (unsigned int)lineBeforeCaret:(u16 **)prefix
{
    NSString *s = [textView string];
    NSRange sel = [textView selectedRange];
    NSRange lr = [s lineRangeForRange:NSMakeRange(sel.location, 0)];
    unsigned int n = sel.location - lr.location;

    *prefix = (u16 *)malloc((n + 1) * sizeof(u16));
    if (*prefix == NULL) return 0;
    if (n > 0) [s getCharacters:*prefix range:NSMakeRange(lr.location, n)];
    return n;
}

- (BOOL)newlineWithIndent
{
    u16 *before, *out;
    unsigned int n, k;
    int smart = lang_smart_indent(mode != nil ? [mode cString] : NULL);
    NSString *str;

    if (!autoIndent) return NO;
    n = [self lineBeforeCaret:&before];
    if (before == NULL) return NO;
    out = (u16 *)malloc((n + (unsigned int)indentWidth + 2) * sizeof(u16));
    if (out == NULL) { free(before); return NO; }
    out[0] = '\n';
    k = edit_newline_indent(before, n, smart, useSpaces, (unsigned int)indentWidth, out + 1, n + (unsigned int)indentWidth + 1);
    str = [NSString stringWithCharacters:out length:k + 1];
    free(out);
    free(before);
    [textView insertText:str];
    return YES;
}

- (void)willInsertText:(NSString *)str
{
    u16 *before;
    unsigned int n, amount;
    NSRange sel = [textView selectedRange];

    if (!autoIndent || sel.length != 0 || [str length] != 1 || [str characterAtIndex:0] != '}') return;
    if (lang_smart_indent(mode != nil ? [mode cString] : NULL) != 'b') return;
    n = [self lineBeforeCaret:&before];
    if (before == NULL) return;
    amount = edit_outdent_amount(before, n, (unsigned int)indentWidth);
    free(before);
    if (amount > 0) [textView setSelectedRange:NSMakeRange(sel.location - amount, amount)];
}

- (BOOL)tabInsertedSpaces
{
    u16 *before;
    unsigned int n, col, count, i;
    NSMutableString *sp;
    NSRange sel = [textView selectedRange];

    if (!useSpaces) return NO;
    n = [self lineBeforeCaret:&before];
    if (before == NULL) return NO;
    col = edit_column(before, n);
    free(before);
    count = (unsigned int)indentWidth - col % (unsigned int)indentWidth;
    sp = [NSMutableString string];
    for (i = 0; i < count; i++) [sp appendString:@" "];
    if (sel.length > 0) return NO;
    [textView insertText:sp];
    return YES;
}

/* The whole lines the selection touches, without the newline that ends the last of them.  A selection that ends just after a
 * newline does not take in the following line. */
- (NSRange)selectedLines:(NSRange)sel
{
    NSString *s = [textView string];
    NSRange q = sel, region;

    if (q.length > 0 && [s characterAtIndex:NSMaxRange(q) - 1] == '\n') q.length--;
    region = [s lineRangeForRange:q];
    if (region.length > 0 && [s characterAtIndex:NSMaxRange(region) - 1] == '\n') region.length--;
    return region;
}

- (void)replaceLines:(NSRange)region with:(u16 *)buf length:(unsigned int)n selection:(NSRange)sel
{
    NSString *str = n > 0 ? [NSString stringWithCharacters:buf length:n] : @"";
    NSRange after;

    if (sel.length == 0) {                                          /* a caret stays about where it was in its line */
        int pos = (int)sel.location + (int)n - (int)region.length;
        if (pos < (int)region.location) pos = (int)region.location;
        after = NSMakeRange((unsigned int)pos, 0);
    } else {
        after = NSMakeRange(region.location, n);
    }
    [self replaceRange:region with:str select:after];
}

- (void)shiftSelection:(int)direction
{
    NSRange sel = [textView selectedRange];
    NSRange region = [self selectedLines:sel];
    u16 *text, *out = NULL;
    unsigned int outlen = 0;
    BOOL changed;

    if (region.length == 0) { NSBeep(); return; }
    text = (u16 *)malloc(region.length * sizeof(u16));
    if (text == NULL) return;
    [[textView string] getCharacters:text range:region];
    changed = edit_shift_lines(text, region.length, direction, useSpaces, (unsigned int)indentWidth, &out, &outlen) != 0;
    free(text);
    if (!changed) { NSBeep(); return; }
    [self replaceLines:region with:out length:outlen selection:sel];
    free(out);
}

- (void)commentSelection:(BOOL)comment
{
    NSRange sel = [textView selectedRange];
    NSRange region;
    const char *open, *close;
    u16 *text, *out = NULL, pre[16], suf[16];
    unsigned int npre = 0, nsuf = 0, outlen = 0;
    BOOL changed;

    if (mode == nil || !lang_comment_style([mode cString], &open, &close)) { NSBeep(); return; }
    while (open[npre] != '\0' && npre < 15) { pre[npre] = (u16)(unsigned char)open[npre]; npre++; }
    while (close[nsuf] != '\0' && nsuf < 15) { suf[nsuf] = (u16)(unsigned char)close[nsuf]; nsuf++; }
    region = [self selectedLines:sel];
    if (region.length == 0) { NSBeep(); return; }
    text = (u16 *)malloc(region.length * sizeof(u16));
    if (text == NULL) return;
    [[textView string] getCharacters:text range:region];
    changed = edit_comment_lines(text, region.length, pre, npre, suf, nsuf, comment ? 0 : 1, &out, &outlen) != 0;
    free(text);
    if (!changed) { NSBeep(); return; }
    [self replaceLines:region with:out length:outlen selection:sel];
    free(out);
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
