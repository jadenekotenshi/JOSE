#import "PreviewController.h"
#import "EditorDoc.h"
#import "Appearance.h"
#import "UIHelpers.h"
#include "md.h"
#include <stdlib.h>
#include <string.h>

#define PREVIEW_MAX_CHARS 3000000U            /* beyond this the preview says so instead */
#define PREVIEW_DELAY 0.5

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
    it->tv = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, [sv contentSize].width, [sv contentSize].height)] autorelease];
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

@end
