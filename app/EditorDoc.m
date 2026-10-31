#import "EditorDoc.h"
#import "UIHelpers.h"
#import "AppController.h"
#import "LineNumberView.h"
#include "langmodes.h"
#include "eol.h"
#include "edit.h"
#include "brace.h"
#include "fill.h"
#include "rect.h"
#include "fold.h"
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
    if (rectOn) [self rectClear];
    if (![(EditorDoc *)editor newlineWithIndent]) [super insertNewline:sender];
}

- (void)insertTab:(id)sender
{
    if (![(EditorDoc *)editor tabInsertedSpaces]) [super insertTab:sender];
}

- (void)insertText:(id)str
{
    if (rectOn && [str isKindOfClass:[NSString class]]) { [(EditorDoc *)editor rectType:str]; return; }
    if ([str isKindOfClass:[NSString class]]) [(EditorDoc *)editor willInsertText:str];
    [super insertText:str];
}

/* ---- rectangular selection: Option-drag; everything is done in columns of a fixed-pitch font ---- */

- (BOOL)mouseActive { return mouseActive; }

- (BOOL)rectActive { return rectOn; }

- (void)rectClear
{
    if (rectOn) {
        rectOn = NO;
        [self setNeedsDisplay:YES];
    }
}

- (void)rectSelectionMoved
{
    if (rectOn && !rectBusy) [self rectClear];
}

- (float)rectCharWidth
{
    float w = [[self font] widthOfString:@"0"];

    return w >= 1.0 ? w : 7.0;
}

- (float)rectLeft
{
    return [self textContainerOrigin].x + [[self textContainer] lineFragmentPadding];
}

/* The line (its first character) and the column at a point of this view. */
- (void)rectPoint:(NSPoint)p line:(unsigned int *)ls column:(unsigned int *)col
{
    NSString *s = [self string];
    NSLayoutManager *lm = [self layoutManager];
    NSPoint o = [self textContainerOrigin];
    NSRange g;
    unsigned int ci, n = [s length];
    float c;

    g = [lm glyphRangeForBoundingRect:NSMakeRect(0.0, p.y - o.y, 1.0, 1.0) inTextContainer:[self textContainer]];
    if (g.length == 0 || ![lm respondsToSelector:@selector(characterIndexForGlyphAtIndex:)]) ci = p.y - o.y < 0.0 ? 0 : n;
    else ci = [lm characterIndexForGlyphAtIndex:g.location];
    if (ci > n) ci = n;
    *ls = [s lineRangeForRange:NSMakeRange(ci, 0)].location;
    c = (p.x - [self rectLeft]) / [self rectCharWidth] + 0.5;
    *col = c < 0.0 ? 0 : (unsigned int)c;
}

- (void)mouseDown:(NSEvent *)event
{
    if (([event modifierFlags] & NSAlternateKeyMask) == 0) {
        [self rectClear];
        mouseActive = YES;
        [super mouseDown:event];
        mouseActive = NO;
        [(EditorDoc *)editor mouseSelectionDone];
        return;
    }
    if ([(EditorDoc *)editor hasFolds]) [(EditorDoc *)editor expandAllFolds];       /* columns of folded text mean nothing */
    {
        NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
        unsigned int ls, col;

        rectBusy = YES;
        [self rectPoint:p line:&ls column:&col];
        rectAnchorLine = rectCurLine = ls;
        rectAnchorCol = rectCurCol = col;
        rectOn = YES;
        [self setSelectedRange:NSMakeRange(ls, 0)];
        for (;;) {
            NSEvent *e = [[self window] nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)];

            if ([e type] == NSLeftMouseUp) break;
            [self autoscroll:e];
            p = [self convertPoint:[e locationInWindow] fromView:nil];
            [self rectPoint:p line:&rectCurLine column:&rectCurCol];
            [self setNeedsDisplay:YES];
        }
        [self setNeedsDisplay:YES];
        rectBusy = NO;
    }
}

- (BOOL)rectLines:(NSRange *)lines columns:(unsigned int *)c0 :(unsigned int *)c1
{
    NSString *s = [self string];
    unsigned int a = rectAnchorLine < rectCurLine ? rectAnchorLine : rectCurLine;
    unsigned int b = rectAnchorLine < rectCurLine ? rectCurLine : rectAnchorLine;
    NSRange last;

    if (!rectOn || b > [s length]) return NO;
    last = [s lineRangeForRange:NSMakeRange(b, 0)];
    if (last.length > 0 && [s characterAtIndex:NSMaxRange(last) - 1] == '\n') last.length--;
    *lines = NSMakeRange(a, NSMaxRange(last) - a);
    *c0 = rectAnchorCol < rectCurCol ? rectAnchorCol : rectCurCol;
    *c1 = rectAnchorCol < rectCurCol ? rectCurCol : rectAnchorCol;
    return YES;
}

- (void)rectShowLines:(NSRange)region columns:(unsigned int)c0 :(unsigned int)c1
{
    NSString *s = [self string];
    unsigned int end = NSMaxRange(region);

    if (end > [s length]) end = [s length];
    rectAnchorLine = region.location;
    rectCurLine = [s lineRangeForRange:NSMakeRange(end, 0)].location;
    rectAnchorCol = c0;
    rectCurCol = c1;
    rectOn = YES;
    rectBusy = YES;
    [self setSelectedRange:NSMakeRange(region.location, 0)];
    rectBusy = NO;
    [self setNeedsDisplay:YES];
}

- (void)copy:(id)sender
{
    if (rectOn) [(EditorDoc *)editor rectCopyAndCut:NO];
    else if (![(EditorDoc *)editor copyExpandedSelectionAndCut:NO]) [super copy:sender];
}

- (void)cut:(id)sender
{
    if (rectOn) [(EditorDoc *)editor rectCopyAndCut:YES];
    else if (![(EditorDoc *)editor copyExpandedSelectionAndCut:YES]) [super cut:sender];
}

- (void)delete:(id)sender
{
    if (rectOn) [(EditorDoc *)editor rectDeleteBackward:NO]; else [super delete:sender];
}

- (void)deleteBackward:(id)sender
{
    if (rectOn) [(EditorDoc *)editor rectDeleteBackward:YES]; else [super deleteBackward:sender];
}

- (void)deleteForward:(id)sender
{
    if (rectOn) [(EditorDoc *)editor rectDeleteBackward:NO]; else [super deleteForward:sender];
}

- (void)paste:(id)sender
{
    if ((rectOn || [(EditorDoc *)editor pasteIsRectangle]) && [(EditorDoc *)editor rectPaste]) return;
    [super paste:sender];
}

/* The rectangle, drawn over the text as a highlight. */
- (void)drawRectangle:(NSRect)frame
{
    NSLayoutManager *lm = [self layoutManager];
    NSString *s = [self string];
    NSRange lines, glyphs;
    unsigned int c0, c1, g;
    NSPoint o = [self textContainerOrigin];
    float cw = [self rectCharWidth], left = [self rectLeft];

    if (![self rectLines:&lines columns:&c0 :&c1]) return;
    if (![lm respondsToSelector:@selector(lineFragmentRectForGlyphAtIndex:effectiveRange:)] ||
        ![lm respondsToSelector:@selector(characterIndexForGlyphAtIndex:)]) return;
    glyphs = [lm glyphRangeForBoundingRect:NSMakeRect(frame.origin.x - o.x, frame.origin.y - o.y, frame.size.width, frame.size.height)
                           inTextContainer:[self textContainer]];
    g = glyphs.location;
    while (g < NSMaxRange(glyphs)) {
        NSRange eff;
        NSRect fr = [lm lineFragmentRectForGlyphAtIndex:g effectiveRange:&eff];
        unsigned int ch = [lm characterIndexForGlyphAtIndex:eff.location];

        if (ch >= lines.location && ch <= NSMaxRange(lines) && (ch == 0 || [s characterAtIndex:ch - 1] == '\n')) {
            NSRect r = NSMakeRect(left + c0 * cw, fr.origin.y + o.y, (c1 - c0) * cw, fr.size.height);

            if (c1 == c0) { r.size.width = 1.0; [[NSColor blackColor] set]; NSRectFill(r); }
            else NSHighlightRect(r);
        }
        if (eff.length == 0) break;
        g = NSMaxRange(eff);
    }
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
    if (rectOn) [self drawRectangle:frame];
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
- (unsigned int)hiddenLinesBefore:(unsigned int)loc;
- (NSString *)hiddenTextForNumber:(unsigned int)fid;
- (BOOL)editAllowedInRange:(NSRange)range;
- (void)foldReplaceRange:(NSRange)range with:(NSString *)str select:(NSRange)sel;
- (void)expandMarkerAt:(unsigned int)start;
- (void)expandMarkerAtNumber:(NSNumber *)start;
- (BOOL)markerStrictlyInside:(unsigned int)loc start:(unsigned int *)st;
- (void)checkFoldSelection;
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
        folds = [[NSMutableDictionary alloc] init];
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
    [folds release];
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
    if ([folds count] > 0) line += [self hiddenLinesBefore:sel.location];
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
    r += fold_hidden_lines(rem, nrem, nrem);               /* lines that a fold marker stands for are still lines */
    a += fold_hidden_lines(ins, nins, nins);
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
    if ([folds count] > 0 && ![self editAllowedInRange:range]) { NSBeep(); return NO; }
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
    [textView rectClear];
    [self markEdited];
    [self updateStatus];
}

/* Moving the insertion point away from where the typing was ends the step being built. */
- (void)textViewDidChangeSelection:(NSNotification *)notification
{
    NSRange sel = [textView selectedRange];

    if (sel.length > 0 || sel.location != expectedCaret) undo_break(undo);
    [textView rectSelectionMoved];
    [self checkFoldSelection];
    prevSel = [textView selectedRange];
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
    [folds removeAllObjects];
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
    NSData *enc = ui_utf8_cstring([self expandedString:[textView string]]);   /* UTF-8, plus a NUL we do not write; folded code goes in full */
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
    if ([folds count] > 0 && ![self editAllowedInRange:range]) { NSBeep(); return; }     /* it would cut a fold marker in two */
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

/* ---- fill paragraph ---- */

- (void)fillWithWidth:(int)width
{
    NSString *s = [textView string];
    NSRange sel = [textView selectedRange], region;
    u16 *text, *out = NULL;
    unsigned int n = [s length], outlen = 0, ps, pe;
    NSString *str;
    BOOL changed;

    if (n == 0) { NSBeep(); return; }
    text = (u16 *)malloc(n * sizeof(u16));
    if (text == NULL) return;
    [s getCharacters:text];
    if (sel.length > 0) {
        region = [self selectedLines:sel];
    } else if (fill_find_paragraph(text, n, sel.location, &ps, &pe)) {
        region = NSMakeRange(ps, pe - ps);
    } else {
        free(text);
        NSBeep();
        return;
    }
    changed = fill_text(text + region.location, region.length, (unsigned int)width, &out, &outlen) != 0;
    free(text);
    if (!changed) { NSBeep(); return; }
    str = [NSString stringWithCharacters:out length:outlen];
    free(out);
    [self replaceRange:region with:str
                select:sel.length > 0 ? NSMakeRange(region.location, outlen) : NSMakeRange(region.location + outlen, 0)];
}

/* ---- rectangular selection ---- */

static NSString *rect_clip;                 /* what Copy last took from a rectangle: pasting it again puts back a rectangle */

- (BOOL)rectActive { return [textView rectActive]; }

- (NSString *)pasteboardString
{
    NSPasteboard *pb = [NSPasteboard generalPasteboard];

    if ([[pb types] indexOfObject:NSStringPboardType] == NSNotFound) return nil;
    return [pb stringForType:NSStringPboardType];
}

- (BOOL)pasteIsRectangle
{
    NSString *clip = [self pasteboardString];

    return rect_clip != nil && clip != nil && [clip isEqualToString:rect_clip];
}

/* The text of the lines the rectangle covers (malloc'd; the caller frees it), its range, and its columns. */
- (u16 *)rectText:(NSRange *)lines columns:(unsigned int *)c0 :(unsigned int *)c1
{
    u16 *t;

    if (![textView rectLines:lines columns:c0 :c1]) return NULL;
    t = (u16 *)malloc((lines->length + 1) * sizeof(u16));
    if (t == NULL) return NULL;
    if (lines->length > 0) [[textView string] getCharacters:t range:*lines];
    return t;
}

/* Replaces what the rectangle covers by `ins` (on every line, or line by line), as one edit, and shows the rectangle again
 * with the columns given. */
- (void)rectReplaceInLines:(NSRange)lines text:(u16 *)t columns:(unsigned int)c0 :(unsigned int)c1
                    insert:(NSString *)ins perLine:(BOOL)perLine result:(unsigned int)r0 :(unsigned int)r1
{
    unsigned int nins = [ins length], outlen = 0;
    u16 *iu = (u16 *)malloc((nins + 1) * sizeof(u16)), *out = NULL;
    NSString *str;

    if (iu == NULL) return;
    if (nins > 0) [ins getCharacters:iu];
    if (!rect_replace(t, lines.length, c0, c1, iu, nins, perLine, &out, &outlen)) { free(iu); return; }
    free(iu);
    str = [NSString stringWithCharacters:out length:outlen];
    free(out);
    [self replaceRange:lines with:str select:NSMakeRange(lines.location, 0)];
    [textView rectShowLines:NSMakeRange(lines.location, outlen) columns:r0 :r1];
}

- (BOOL)rectCopyAndCut:(BOOL)cut
{
    NSRange lines;
    unsigned int c0, c1, outlen = 0;
    u16 *t = [self rectText:&lines columns:&c0 :&c1], *out = NULL;
    NSString *str;
    NSPasteboard *pb;

    if (t == NULL) return NO;
    if (!rect_extract(t, lines.length, c0, c1, &out, &outlen)) { free(t); return NO; }
    str = [NSString stringWithCharacters:out length:outlen];
    free(out);
    pb = [NSPasteboard generalPasteboard];
    [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pb setString:str forType:NSStringPboardType];
    [rect_clip release];
    rect_clip = [str copy];
    if (cut) [self rectReplaceInLines:lines text:t columns:c0 :c1 insert:@"" perLine:NO result:c0 :c0];
    free(t);
    return YES;
}

- (void)rectType:(NSString *)str
{
    NSRange lines;
    unsigned int c0, c1, i, col;
    u16 *t = [self rectText:&lines columns:&c0 :&c1];

    if (t == NULL) return;
    if ([str rangeOfString:@"\n"].length > 0 || [str rangeOfString:@"\r"].length > 0) { free(t); [textView rectClear]; return; }
    col = c0;
    for (i = 0; i < [str length]; i++) col = [str characterAtIndex:i] == '\t' ? (col / 8 + 1) * 8 : col + 1;
    [self rectReplaceInLines:lines text:t columns:c0 :c1 insert:str perLine:NO result:col :col];
    free(t);
}

- (void)rectDeleteBackward:(BOOL)backward
{
    NSRange lines;
    unsigned int c0, c1;
    u16 *t = [self rectText:&lines columns:&c0 :&c1];

    if (t == NULL) return;
    if (c0 == c1) {                                             /* no width: the column before (Backspace) or after (Delete) */
        if (backward && c0 == 0) { free(t); NSBeep(); return; }
        if (backward) c0--; else c1++;
        [self rectReplaceInLines:lines text:t columns:c0 :c1 insert:@"" perLine:NO result:c0 :c0];
    } else {
        [self rectReplaceInLines:lines text:t columns:c0 :c1 insert:@"" perLine:NO result:c0 :c0];
    }
    free(t);
}

- (BOOL)rectPaste
{
    NSString *clip = [self pasteboardString];
    NSString *s = [textView string];
    NSRange lines;
    unsigned int c0, c1, nl = 1, i, width = 0, run = 0, k;
    u16 *t;

    if (clip == nil || [clip length] == 0) return NO;
    if ([clip characterAtIndex:[clip length] - 1] == '\n') clip = [clip substringToIndex:[clip length] - 1];
    for (i = 0; i < [clip length]; i++) {
        if ([clip characterAtIndex:i] == '\n') { nl++; run = 0; }
        else if (++run > width) width = run;
    }
    if ([textView rectLines:&lines columns:&c0 :&c1]) {
        /* it goes where the rectangle is, in place of what that covers */
    } else {
        NSRange sel = [textView selectedRange];
        NSRange lr = [s lineRangeForRange:NSMakeRange(sel.location, 0)];
        unsigned int end;

        c0 = c1 = 0;
        for (i = lr.location; i < sel.location; i++) c0 = [s characterAtIndex:i] == '\t' ? (c0 / 8 + 1) * 8 : c0 + 1;
        c1 = c0;
        end = lr.location;
        for (k = 0; k < nl; k++) {                              /* as many lines as the block has, if the text has that many */
            NSRange l = [s lineRangeForRange:NSMakeRange(end, 0)];
            end = NSMaxRange(l);
            if (end >= [s length]) break;
        }
        if (end > lr.location && [s characterAtIndex:end - 1] == '\n') end--;
        lines = NSMakeRange(lr.location, end - lr.location);
    }
    t = (u16 *)malloc((lines.length + 1) * sizeof(u16));
    if (t == NULL) return NO;
    if (lines.length > 0) [s getCharacters:t range:lines];
    [self rectReplaceInLines:lines text:t columns:c0 :c1 insert:clip perLine:YES result:c0 :c0 + width];
    free(t);
    return YES;
}

- (NSString *)workingDirectory
{
    return path != nil ? [path stringByDeletingLastPathComponent] : NSHomeDirectory();
}

/* ---- code folding ----
 * A folded block is replaced in the text by a marker (see core/fold.h) and the code it hides is kept in `folds`.  Entries are
 * never removed, so undo and redo, which only move text about, always find what a marker stands for. */

- (BOOL)hasFolds { return [folds count] > 0; }

- (NSString *)hiddenTextForNumber:(unsigned int)fid
{
    return [folds objectForKey:[NSNumber numberWithUnsignedInt:fid]];
}

/* The text with every marker we know replaced, over and over, by the code it hides. */
- (NSString *)expandedString:(NSString *)s
{
    int depth;

    if ([folds count] == 0) return s;
    for (depth = 0; depth < 64; depth++) {
        unsigned int n = [s length], pos = 0, from = 0, st, en, lines, fid;
        u16 *t = (u16 *)malloc((n + 1) * sizeof(u16));
        NSMutableString *out = nil;

        if (t == NULL) return s;
        if (n > 0) [s getCharacters:t];
        while (fold_token_find(t, n, from, &st, &en, &lines, &fid)) {
            NSString *hidden = [self hiddenTextForNumber:fid];

            if (hidden == nil) { from = st + 1; continue; }
            if (out == nil) out = [NSMutableString stringWithCapacity:n];
            if (st > pos) [out appendString:[s substringWithRange:NSMakeRange(pos, st - pos)]];
            [out appendString:hidden];
            pos = en;
            from = en;
        }
        free(t);
        if (out == nil) return s;
        if (pos < n) [out appendString:[s substringWithRange:NSMakeRange(pos, n - pos)]];
        s = out;
    }
    return s;
}

/* The line breaks that fold markers before `loc` stand for. */
- (unsigned int)hiddenLinesBefore:(unsigned int)loc
{
    NSString *s = [textView string];
    unsigned int total = [s length], pos = 0, sum = 0;
    unichar buf[1024 + 64];

    if (loc > total) loc = total;
    while (pos < loc) {
        unsigned int got = loc - pos, avail;

        if (got > 1024) got = 1024;
        avail = total - pos < got + 64 ? total - pos : got + 64;
        [s getCharacters:buf range:NSMakeRange(pos, avail)];
        sum += fold_hidden_lines((const u16 *)buf, avail, got);
        pos += got;
    }
    return sum;
}

/* Would an edit of `range` leave every marker whole?  An edit may touch the ends of a marker, or take it away altogether
 * (deleting the block it stands for), but not change part of it. */
- (BOOL)editAllowedInRange:(NSRange)range
{
    NSString *s = [textView string];
    unsigned int n = [s length], lo, hi, from = 0, st, en, lines, fid, len;
    u16 *t;

    if (range.location > n) return YES;
    lo = range.location > 64 ? range.location - 64 : 0;
    hi = NSMaxRange(range) + 64 > n ? n : NSMaxRange(range) + 64;
    len = hi - lo;
    t = (u16 *)malloc((len + 1) * sizeof(u16));
    if (t == NULL) return YES;
    if (len > 0) [s getCharacters:t range:NSMakeRange(lo, len)];
    while (fold_token_find(t, len, from, &st, &en, &lines, &fid)) {
        unsigned int a = lo + st, b = lo + en;

        from = st + 1;
        if ([self hiddenTextForNumber:fid] == nil) continue;
        if (range.length == 0) {
            if (range.location > a && range.location < b) { free(t); return NO; }
        } else if (range.location < b && NSMaxRange(range) > a) {
            if (!(range.location <= a && NSMaxRange(range) >= b)) { free(t); return NO; }
        }
    }
    free(t);
    return YES;
}

/* A fold or unfold: an edit like any other (so it can be undone), except that it does not make a clean document dirty. */
- (void)foldReplaceRange:(NSRange)range with:(NSString *)str select:(NSRange)sel
{
    BOOL wasClean = !dirty;

    [self replaceRange:range with:str select:sel];
    [ruler textReplaced];
    if (wasClean) {
        savedVersion = undo_version(undo);
        dirty = NO;
        [self updateTitle];
    }
    [self updateStatus];
}

- (void)toggleFold
{
    NSString *s = [textView string];
    NSRange sel = [textView selectedRange];
    unsigned int n = [s length], ls, le, st, en, lines, fid, open, close, from;
    NSRange lr = [s lineRangeForRange:NSMakeRange(sel.location, 0)];
    u16 *t;
    BOOL ok;

    if (n == 0) { NSBeep(); return; }
    t = (u16 *)malloc((n + 1) * sizeof(u16));
    if (t == NULL) return;
    [s getCharacters:t];
    ls = lr.location;
    le = NSMaxRange(lr);
    while (le > ls && t[le - 1] == '\n') le--;
    from = ls;
    /* a marker on this line opens */
    while (fold_token_find(t, le, from, &st, &en, &lines, &fid)) {
        if (st >= ls && [self hiddenTextForNumber:fid] != nil) { free(t); [self expandMarkerAt:st]; return; }
        from = st + 1;
    }
    ok = fold_find_block(t, n, sel.location, lang_c_like(mode != nil ? [mode cString] : NULL), &open, &close) != 0;
    if (ok) {
        NSRange inner = NSMakeRange(open + 1, close - open - 1);
        NSString *hidden = [s substringWithRange:inner];
        NSString *full = [self expandedString:hidden];
        unsigned int k, nl = 0, fl = [full length];
        u16 tok[FOLD_MAX_TOKEN];

        for (k = 0; k < fl; k++) if ([full characterAtIndex:k] == '\n') nl++;
        if (nl == 0) ok = NO;
        else {
            unsigned int tn;

            foldNext++;
            [folds setObject:hidden forKey:[NSNumber numberWithUnsignedInt:foldNext]];
            tn = fold_make_token(tok, nl, foldNext);
            [self foldReplaceRange:inner with:[NSString stringWithCharacters:tok length:tn]
                            select:NSMakeRange(open + 1 + tn, 0)];
        }
    }
    free(t);
    if (!ok) NSBeep();
}

- (void)foldAll
{
    NSString *s = [textView string];
    unsigned int n = [s length], count, i, pos, *opens, *closes;
    u16 *t;
    NSMutableString *out;
    NSRange region;

    if (n == 0) { NSBeep(); return; }
    t = (u16 *)malloc((n + 1) * sizeof(u16));
    if (t == NULL) return;
    [s getCharacters:t];
    count = fold_top_blocks(t, n, lang_c_like(mode != nil ? [mode cString] : NULL), &opens, &closes);
    free(t);
    if (count == 0) { NSBeep(); return; }
    region = NSMakeRange(opens[0] + 1, closes[count - 1] - opens[0] - 1);
    out = [NSMutableString stringWithCapacity:region.length];
    pos = region.location;
    for (i = 0; i < count; i++) {
        NSRange inner = NSMakeRange(opens[i] + 1, closes[i] - opens[i] - 1);
        NSString *hidden = [s substringWithRange:inner], *full = [self expandedString:hidden];
        unsigned int k, nl = 0, fl = [full length], tn;
        u16 tok[FOLD_MAX_TOKEN];

        for (k = 0; k < fl; k++) if ([full characterAtIndex:k] == '\n') nl++;
        [out appendString:[s substringWithRange:NSMakeRange(pos, inner.location - pos)]];
        foldNext++;
        [folds setObject:hidden forKey:[NSNumber numberWithUnsignedInt:foldNext]];
        tn = fold_make_token(tok, nl, foldNext);
        [out appendString:[NSString stringWithCharacters:tok length:tn]];
        pos = NSMaxRange(inner);
    }
    free(opens);
    free(closes);
    [self foldReplaceRange:region with:out select:NSMakeRange(region.location, 0)];
}

- (void)expandAllFolds
{
    NSString *s = [textView string];
    unsigned int n = [s length], from = 0, st, en, lines, fid, first = 0, last = 0;
    BOOL any = NO;
    u16 *t;

    if ([folds count] == 0 || n == 0) return;
    t = (u16 *)malloc((n + 1) * sizeof(u16));
    if (t == NULL) return;
    [s getCharacters:t];
    while (fold_token_find(t, n, from, &st, &en, &lines, &fid)) {
        from = st + 1;
        if ([self hiddenTextForNumber:fid] == nil) continue;
        if (!any) first = st;
        any = YES;
        last = en;
    }
    free(t);
    if (!any) return;
    {
        NSRange region = NSMakeRange(first, last - first);
        NSString *full = [self expandedString:[s substringWithRange:region]];

        [self foldReplaceRange:region with:full select:NSMakeRange(first, 0)];
    }
}

/* The marker that starts at `start` is replaced by the code it hides. */
- (void)expandMarkerAt:(unsigned int)start
{
    NSString *s = [textView string];
    unsigned int n = [s length], st, en, lines, fid;
    unsigned int len = n - start < FOLD_MAX_TOKEN ? n - start : FOLD_MAX_TOKEN;
    u16 t[FOLD_MAX_TOKEN];
    NSString *hidden;

    if (start >= n) return;
    [s getCharacters:t range:NSMakeRange(start, len)];
    if (!fold_token_find(t, len, 0, &st, &en, &lines, &fid) || st != 0) return;
    hidden = [self hiddenTextForNumber:fid];
    if (hidden == nil) return;
    [self foldReplaceRange:NSMakeRange(start, en) with:hidden select:NSMakeRange(start, 0)];
}

- (void)expandMarkerAtNumber:(NSNumber *)start
{
    [self expandMarkerAt:[start unsignedIntValue]];
}

/* Is `loc` strictly inside a marker (not at either end)?  *st is where the marker starts. */
- (BOOL)markerStrictlyInside:(unsigned int)loc start:(unsigned int *)st
{
    NSString *s = [textView string];
    unsigned int n = [s length], lo = loc > 64 ? loc - 64 : 0, hi = loc + 64 > n ? n : loc + 64, len = hi - lo;
    unsigned int from = 0, a, b, lines, fid;
    u16 *t;
    BOOL found = NO;

    if (loc > n) return NO;
    t = (u16 *)malloc((len + 1) * sizeof(u16));
    if (t == NULL) return NO;
    if (len > 0) [s getCharacters:t range:NSMakeRange(lo, len)];
    while (fold_token_find(t, len, from, &a, &b, &lines, &fid)) {
        from = a + 1;
        if (lo + a < loc && loc < lo + b && [self hiddenTextForNumber:fid] != nil) { *st = lo + a; found = YES; break; }
    }
    free(t);
    return found;
}

/* The selection moved.  A caret that arrives inside a marker by the keyboard steps over it; a selection that cuts into one
 * (a search hit, Shift-arrow) opens it.  Clicks are dealt with when the mouse goes up. */
- (void)checkFoldSelection
{
    NSRange sel = [textView selectedRange];
    unsigned int st, en = NSMaxRange(sel);

    if ([folds count] == 0 || snapping || [textView mouseActive]) return;
    if (sel.length == 0) {
        if ([self markerStrictlyInside:sel.location start:&st]) {
            unsigned int mid = sel.location, to;
            NSString *s = [textView string];
            unsigned int lines, fid, e2, s2;
            u16 t[FOLD_MAX_TOKEN];
            unsigned int len = [s length] - st < FOLD_MAX_TOKEN ? [s length] - st : FOLD_MAX_TOKEN;

            [s getCharacters:t range:NSMakeRange(st, len)];
            if (!fold_token_find(t, len, 0, &s2, &e2, &lines, &fid)) return;
            to = mid < prevSel.location ? st : st + e2;                   /* the way the caret was going */
            snapping = YES;
            [textView setSelectedRange:NSMakeRange(to, 0)];
            snapping = NO;
        }
    } else if ([self markerStrictlyInside:sel.location start:&st]) {
        [self performSelector:@selector(expandMarkerAtNumber:) withObject:[NSNumber numberWithUnsignedInt:st] afterDelay:0.0];
    } else if ([self markerStrictlyInside:en start:&st]) {
        [self performSelector:@selector(expandMarkerAtNumber:) withObject:[NSNumber numberWithUnsignedInt:st] afterDelay:0.0];
    }
}

- (void)mouseSelectionDone
{
    NSRange sel = [textView selectedRange];
    unsigned int st;

    if ([folds count] == 0) return;
    if ([self markerStrictlyInside:sel.location start:&st] || [self markerStrictlyInside:NSMaxRange(sel) start:&st])
        [self expandMarkerAt:st];
}

- (BOOL)copyExpandedSelectionAndCut:(BOOL)cut
{
    NSRange sel = [textView selectedRange];
    NSString *text, *full;
    NSPasteboard *pb;

    if ([folds count] == 0 || sel.length == 0) return NO;
    text = [[textView string] substringWithRange:sel];
    full = [self expandedString:text];
    if ([full isEqualToString:text]) return NO;
    pb = [NSPasteboard generalPasteboard];
    [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pb setString:full forType:NSStringPboardType];
    if (cut) [textView delete:nil];
    return YES;
}

- (void)goToLine:(int)line
{
    NSString *s;
    unsigned int pos = 0, n;
    int l = 1;
    NSRange r;

    [self expandAllFolds];                       /* line numbers are those of the whole text */
    s = [textView string];
    n = [s length];
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
