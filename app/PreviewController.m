#import "PreviewController.h"
#import "EditorDoc.h"
#import "Appearance.h"
#import "UIHelpers.h"
#include "md.h"
#include "url.h"
#include "remote.h"
#include "shellrun.h"
#include <stdlib.h>
#include <string.h>

#define PREVIEW_MAX_CHARS 3000000U            /* beyond this the preview says so instead */
#define PREVIEW_DELAY 0.5

/* The text view of a preview: a click on a web address in it runs the browser. */
@interface PreviewTextView : NSTextView
@end

@implementation PreviewTextView

/* The first click on a window that is not the active one is delivered too (it would otherwise only bring the window forward). */
- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    return YES;
}

- (void)mouseDown:(NSEvent *)event
{
    static NSString *lastURL = nil;
    static NSTimeInterval lastTime = 0.0;
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    NSPoint o = [self textContainerOrigin];
    NSLayoutManager *lm = [self layoutManager];
    NSString *s = [self string];
    unsigned int n = [s length], ci = 0, start = 0, len = 0;
    NSRange g;
    u16 *t;

    if (n > 0 && n < 2000000U) {
        ci = [PreviewController characterIndexAt:p inView:self];
        if (ci < n) {
            t = (u16 *)malloc((n + 1) * sizeof(u16));
            if (t != NULL) {
                [s getCharacters:t];
                len = url_at(t, n, ci, &start);
                free(t);
            }
        }
    }
    (void)o; (void)lm; (void)g;
    SSTrace("preview click: count %d at (%d,%d), character %u of %u, %s", (int)[event clickCount], (int)p.x, (int)p.y, ci, n, len > 0 ? "on an address" : "not on an address");
    if (len > 0) {
        NSString *url = [s substringWithRange:NSMakeRange(start, len)];
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

        if (lastURL != nil && [lastURL isEqualToString:url] && now - lastTime < 1.0) return;     /* the second click of a double-click */
        [lastURL release];
        lastURL = [url copy];
        lastTime = now;
        [PreviewController openURLString:url];
        return;
    }
    [super mouseDown:event];
}

@end

/* One preview: the document, its window, and the text view in it. */
@interface PreviewItem : NSObject
{
@public
    EditorDoc  *doc;                          /* not retained */
    NSWindow   *window;
    NSTextView *tv;
}
@end

@implementation PreviewItem
- (void)dealloc
{
    [window release];
    [super dealloc];
}
@end

@interface PreviewController (Private)
- (PreviewItem *)itemFor:(EditorDoc *)d;
- (void)refreshItem:(PreviewItem *)it;
- (void)refreshLater:(PreviewItem *)it;
- (void)previewWindowClosing:(NSNotification *)n;
@end

@implementation PreviewController

- (id)initWithOwner:(id)anOwner
{
    self = [super init];
    if (self) {
        owner = anOwner;
        items = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [items release];
    [super dealloc];
}

- (PreviewItem *)itemFor:(EditorDoc *)d
{
    unsigned int i;

    for (i = 0; i < [items count]; i++)
        if (((PreviewItem *)[items objectAtIndex:i])->doc == d) return [items objectAtIndex:i];
    return nil;
}

- (BOOL)hasPreviewFor:(EditorDoc *)d { return [self itemFor:d] != nil; }

- (NSTextView *)previewViewFor:(EditorDoc *)d
{
    PreviewItem *it = [self itemFor:d];

    return it != nil ? it->tv : nil;
}

- (NSString *)previewStringFor:(EditorDoc *)d
{
    PreviewItem *it = [self itemFor:d];

    return it != nil ? [it->tv string] : nil;
}

/* ---- making the RTF ---- */

static NSData *rtf_of(NSString *markdown)
{
    NSData *enc = ui_utf8_cstring(markdown);
    MdDoc *doc = md_parse((const char *)[enc bytes], [enc length] - 1);
    MdRtfOptions o;
    char *rtf;
    size_t n = 0;
    NSData *out;
    int links = [Appearance previewLinks];

    if (doc == NULL) return nil;
    md_rtf_defaults(&o);
    o.charset = [Appearance previewCharset] == 1 ? MD_CHARSET_NEXTSTEP : ([Appearance previewCharset] == 2 ? MD_CHARSET_ASCII : MD_CHARSET_CP1252);
    o.links = links == 0 ? MD_LINKS_TEXT : (links == 1 ? MD_LINKS_URL : MD_LINKS_BOTH);
    rtf = md_to_rtf(doc, &o, &n);
    md_free(doc);
    if (rtf == NULL) return nil;
    out = [NSData dataWithBytes:rtf length:n];
    free(rtf);
    return out;
}

- (void)refreshItem:(PreviewItem *)it
{
    EditorDoc *d = it->doc;
    NSString *text = [d expandedString:[[d textView] string]];
    NSData *rtf;
    float ratio = 0.0, avail;
    NSScrollView *esv = [[d textView] enclosingScrollView];

    if (esv != nil) {                                              /* how far down the document is scrolled */
        avail = [[esv documentView] frame].size.height - [esv contentSize].height;
        if (avail > 1.0) ratio = [[esv contentView] bounds].origin.y / avail;
        if (ratio < 0.0) ratio = 0.0;
        if (ratio > 1.0) ratio = 1.0;
    }
    if ([text length] > PREVIEW_MAX_CHARS) {
        [it->tv setString:@"This document is too large to preview."];
        return;
    }
    rtf = rtf_of(text);
    if (rtf == nil) return;
    [it->tv replaceCharactersInRange:NSMakeRange(0, [[it->tv string] length]) withRTF:rtf];
    {   /* web addresses show in blue: they can be clicked */
        NSString *shown = [it->tv string];
        unsigned int sn = [shown length], from = 0, st, ln;
        u16 *st16 = sn > 0 && sn < 2000000U ? (u16 *)malloc((sn + 1) * sizeof(u16)) : NULL;

        if (st16 != NULL) {
            [shown getCharacters:st16];
            while ((ln = url_next(st16, sn, from, &st)) > 0) {
                [[it->tv textStorage] addAttribute:NSForegroundColorAttributeName value:[NSColor blueColor] range:NSMakeRange(st, ln)];
                from = st + ln;
            }
            free(st16);
        }
    }
    if ([it->tv respondsToSelector:@selector(sizeToFit)]) [it->tv sizeToFit];
    {
        NSScrollView *psv = [it->tv enclosingScrollView];
        float pavail = [it->tv frame].size.height - [psv contentSize].height;

        if (pavail > 1.0) {
            [[psv contentView] scrollToPoint:NSMakePoint(0.0, pavail * ratio)];
            [psv reflectScrolledClipView:[psv contentView]];
        }
    }
}

- (void)refreshNowFor:(EditorDoc *)d
{
    PreviewItem *it = [self itemFor:d];

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshItem:) object:it];
    if (it != nil) [self refreshItem:it];
}

- (void)refreshLater:(PreviewItem *)it
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshItem:) object:it];
    [self performSelector:@selector(refreshItem:) withObject:it afterDelay:PREVIEW_DELAY];
}

- (void)documentChanged:(EditorDoc *)d
{
    PreviewItem *it = [self itemFor:d];

    if (it != nil) [self refreshLater:it];
}

- (void)settingsChanged
{
    unsigned int i;

    for (i = 0; i < [items count]; i++) [self refreshItem:[items objectAtIndex:i]];
}

/* ---- the windows ---- */

- (void)toggleFor:(EditorDoc *)d
{
    PreviewItem *it = [self itemFor:d];
    NSRect dr, fr;
    NSScrollView *sv;
    NSScreen *scr;

    if (it != nil) {
        [[it retain] autorelease];
        [it->window close];                                      /* windowWillClose removes it */
        return;
    }
    it = [[[PreviewItem alloc] init] autorelease];
    it->doc = d;
    dr = [[d window] frame];
    fr = NSMakeRect(NSMaxX(dr) + 6.0, dr.origin.y, 520.0, dr.size.height);
    scr = [NSScreen mainScreen];
    if (scr != nil && NSMaxX(fr) > NSMaxX([scr frame])) fr.origin.x = dr.origin.x + 30.0, fr.origin.y = dr.origin.y - 30.0;   /* no room beside it */
    it->window = [[NSWindow alloc] initWithContentRect:fr
                                             styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
                                               backing:NSBackingStoreBuffered defer:NO];
    [it->window setReleasedWhenClosed:NO];
    [it->window setTitle:[NSString stringWithFormat:@"Preview: %@", [[d window] title]]];
    sv = [[[NSScrollView alloc] initWithFrame:[[it->window contentView] bounds]] autorelease];
    [sv setHasVerticalScroller:YES];
    [sv setHasHorizontalScroller:NO];
    [sv setBorderType:NSNoBorder];
    [sv setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    it->tv = [[[PreviewTextView alloc] initWithFrame:NSMakeRect(0, 0, [sv contentSize].width, [sv contentSize].height)] autorelease];
    [it->tv setMinSize:NSMakeSize(0.0, [sv contentSize].height)];
    [it->tv setMaxSize:NSMakeSize(1.0e7, 1.0e7)];
    [it->tv setVerticallyResizable:YES];
    [it->tv setHorizontallyResizable:NO];
    [it->tv setAutoresizingMask:NSViewWidthSizable];
    [[it->tv textContainer] setWidthTracksTextView:YES];
    [it->tv setRichText:YES];
    [it->tv setEditable:NO];
    [it->tv setSelectable:YES];
    [it->tv setDrawsBackground:YES];
    [it->tv setBackgroundColor:[NSColor whiteColor]];
    [sv setDocumentView:it->tv];
    [[it->window contentView] addSubview:sv];
    [items addObject:it];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(previewWindowClosing:)
                                                 name:NSWindowWillCloseNotification object:it->window];
    [self refreshItem:it];
    if ([[d window] isVisible]) [it->window orderFront:nil];
}

- (void)previewWindowClosing:(NSNotification *)n
{
    unsigned int i;

    for (i = 0; i < [items count]; i++) {
        PreviewItem *it = [items objectAtIndex:i];

        if (it->window == [n object]) {
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshItem:) object:it];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:it->window];
            [items removeObjectAtIndex:i];
            return;
        }
    }
}

- (void)documentClosed:(EditorDoc *)d
{
    PreviewItem *it = [self itemFor:d];

    if (it != nil) {
        [[it retain] autorelease];
        [it->window close];
    }
}

/* ---- the character under the pointer ---- */

/* glyphRangeForBoundingRect: answers with a whole line, so the glyph under the pointer is found by looking at the boxes of the line's
 * glyphs. */
+ (unsigned int)characterIndexAt:(NSPoint)p inView:(NSTextView *)tv
{
    NSLayoutManager *lm = [tv layoutManager];
    NSPoint o = [tv textContainerOrigin];
    NSTextContainer *tc = [tv textContainer];
    unsigned int n = [[tv string] length], k, last;
    float x = p.x - o.x, y = p.y - o.y;
    NSRange g;

    if (n == 0 || ![lm respondsToSelector:@selector(characterIndexForGlyphAtIndex:)]) return n;
    g = [lm glyphRangeForBoundingRect:NSMakeRect(x, y, 1.0, 1.0) inTextContainer:tc];
    if (g.length == 0) return n;
    last = NSMaxRange(g);
    if (g.length > 4000) last = g.location + 4000;
    for (k = g.location; k < last; k++) {
        NSRect r = [lm boundingRectForGlyphRange:NSMakeRange(k, 1) inTextContainer:tc];

        if (x >= r.origin.x && x < NSMaxX(r) && y >= r.origin.y && y < NSMaxY(r)) return [lm characterIndexForGlyphAtIndex:k];
    }
    return n;
}

/* ---- the browser ---- */

+ (BOOL)openURLString:(NSString *)url
{
    NSString *path = [Appearance browserPath], *args = [Appearance browserArgs], *exe = path;
    NSData *ed, *ud, *ad;
    char eq[2200], uq[4200], *cmd;
    size_t need;
    ShellResult r;
    NSString *spec;

    if ([[path pathExtension] isEqualToString:@"app"]) exe = [path stringByAppendingPathComponent:[[path lastPathComponent] stringByDeletingPathExtension]];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:exe]) {
        NSRunAlertPanel(@"Open Link", @"The browser %@ was not found. Set it in Preferences > Markdown.", @"OK", nil, nil, path);
        return NO;
    }
    ed = ui_utf8_cstring(exe);
    ud = ui_utf8_cstring(url);
    ad = ui_utf8_cstring(args);
    if ([ed length] > 2000 || [ud length] > 4000) return NO;
    remote_shq((const char *)[ed bytes], eq, sizeof eq);
    remote_shq((const char *)[ud bytes], uq, sizeof uq);
    if ([args rangeOfString:@"%u"].length > 0) {
        NSMutableString *a = [NSMutableString stringWithString:args];

        [a replaceOccurrencesOfString:@"%u" withString:ui_string_from_utf8(uq) options:0 range:NSMakeRange(0, [a length])];
        spec = [NSString stringWithFormat:@"( %s %@ ) >/dev/null 2>&1 &", eq, a];
    } else {
        spec = [NSString stringWithFormat:@"( %s %@ %s ) >/dev/null 2>&1 &", eq, args, uq];
    }
    (void)ad;
    need = [ui_utf8_cstring(spec) length];
    cmd = (char *)malloc(need + 1);
    if (cmd == NULL) return NO;
    memcpy(cmd, [ui_utf8_cstring(spec) bytes], need);
    SSTrace("browser: %s", cmd);
    if (!shell_run(cmd, NULL, NULL, 0, 5000, 0, &r)) { free(cmd); shell_result_free(&r); return NO; }
    free(cmd);
    shell_result_free(&r);
    return YES;
}

@end
