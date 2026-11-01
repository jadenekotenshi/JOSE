#import "UnicodeController.h"
#import "EditorDoc.h"
#import "Appearance.h"
#import "UIHelpers.h"
#include "uview.h"
#include <stdlib.h>
#include <string.h>

#define VIEW_DELAY 0.5
#define VIEW_MARGIN 4

/* The view: draws the part of the text that is showing, through FreeType, into a framebuffer, and hands that to the screen. */
@interface UnicodeView : NSView
{
    ULayout  layout;
    BOOL     haveLayout;
    u16     *text;
    size_t   textLen;
    UGlyphs *glyphs;
    FBuf    *fb;
    unsigned char *upload;
    size_t   uploadSize;
    unsigned long fg, bg;
}
- (int)setFonts:(NSString *)paths size:(int)px;     /* how many of the files were usable */
- (void)setString:(NSString *)s;
- (void)fitToSuperview;
@end

static unsigned long rgb_of(NSColor *c)
{
    NSColor *r = [c colorUsingColorSpaceName:NSCalibratedRGBColorSpace];

    if (r == nil) return 0;
    return (((unsigned long)(255.0 * [r redComponent] + 0.5)) << 16) | (((unsigned long)(255.0 * [r greenComponent] + 0.5)) << 8) |
           (unsigned long)(255.0 * [r blueComponent] + 0.5);
}

@implementation UnicodeView

- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }

- (void)dropLayout
{
    if (haveLayout) ulayout_free(&layout);
    haveLayout = NO;
}

- (void)dealloc
{
    [self dropLayout];
    free(text);
    if (glyphs != NULL) uglyphs_free(glyphs);
    fbuf_free(fb);
    free(upload);
    [super dealloc];
}

- (int)setFonts:(NSString *)paths size:(int)px
{
    NSArray *list = [paths componentsSeparatedByString:@":"];
    unsigned int i;
    int ok = 0;

    [self dropLayout];
    if (glyphs != NULL) uglyphs_free(glyphs);
    glyphs = uglyphs_new(px);
    for (i = 0; glyphs != NULL && i < [list count]; i++) {
        NSString *p = [list objectAtIndex:i];
        NSRange hash = [p rangeOfString:@"#"];
        long index = 0;

        if (hash.length > 0) {
            index = (long)[[p substringFromIndex:NSMaxRange(hash)] intValue];
            p = [p substringToIndex:hash.location];
        }
        if ([p length] == 0) continue;
        if (uglyphs_add_face(glyphs, [p fileSystemRepresentation], index)) ok++;
        else SSTrace("unicode view: cannot use the font file %s", SSCS(p));
    }
    if (ok == 0 && glyphs != NULL) {
        uglyphs_free(glyphs);
        glyphs = NULL;
    }
    return ok;
}

- (void)setString:(NSString *)s
{
    unsigned int n = [s length];

    [self dropLayout];
    free(text);
    text = (u16 *)malloc((n + 1) * sizeof(u16));
    textLen = 0;
    if (text != NULL) {
        if (n > 0) [s getCharacters:text];
        textLen = n;
    }
    if (glyphs != NULL && text != NULL) haveLayout = ulayout_build(&layout, text, textLen, glyphs, 8) != 0;
    fg = rgb_of([Appearance textColor]);
    bg = rgb_of([Appearance backgroundColor]);
    [self fitToSuperview];
    [self setNeedsDisplay:YES];
}

/* As large as the text, and at least as large as the window shows. */
- (void)fitToSuperview
{
    NSSize avail = [[self superview] bounds].size;
    float w = avail.width, h = avail.height;

    if ([[self superview] isKindOfClass:[NSClipView class]]) avail = [(NSScrollView *)[(NSClipView *)[self superview] superview] contentSize], w = avail.width, h = avail.height;
    if (haveLayout) {
        float tw = (float)(layout.max_cols * (unsigned long)layout.cellw) + 2.0 * VIEW_MARGIN;
        float th = (float)(layout.nlines * (size_t)layout.cellh) + 2.0 * VIEW_MARGIN;

        if (tw > w) w = tw;
        if (th > h) h = th;
    }
    [self setFrameSize:NSMakeSize(w, h)];
}

- (void)drawRect:(NSRect)r
{
    int x, y, w, h;
    size_t bytes;
    const unsigned char *planes[5];
    NSRect b = [self bounds];

    if (r.origin.x < 0.0) r.size.width += r.origin.x, r.origin.x = 0.0;
    if (r.origin.y < 0.0) r.size.height += r.origin.y, r.origin.y = 0.0;
    if (NSMaxX(r) > NSMaxX(b)) r.size.width = NSMaxX(b) - r.origin.x;
    if (NSMaxY(r) > NSMaxY(b)) r.size.height = NSMaxY(b) - r.origin.y;
    x = (int)r.origin.x;
    y = (int)r.origin.y;
    w = (int)(r.size.width + 0.999);
    h = (int)(r.size.height + 0.999);
    if (w < 1 || h < 1) return;
    if (fb == NULL) fb = fbuf_new(w, h);
    else if (fb->w != w || fb->h != h) fbuf_resize(fb, w, h);
    if (fb == NULL) return;
    if (haveLayout) {
        /* the text starts VIEW_MARGIN pixels in: ask for the part of it that lies under the rectangle */
        ulayout_draw(&layout, glyphs, fb, x - VIEW_MARGIN, y - VIEW_MARGIN, w, h, fg, bg);
    } else {
        fbuf_fill(fb, 0, 0, w, h, bg);
    }
    bytes = (size_t)w * (size_t)h * 4;
    if (upload == NULL || uploadSize < bytes) {
        free(upload);
        upload = (unsigned char *)malloc(bytes);
        uploadSize = upload != NULL ? bytes : 0;
    }
    if (upload == NULL) return;
    fbuf_to_display(fb, upload);
    planes[0] = upload;
    planes[1] = planes[2] = planes[3] = planes[4] = NULL;
    NSDrawBitmap(NSMakeRect((float)x, (float)y, (float)w, (float)h), w, h, 8, 4, 32, w * 4, NO, YES, NSDeviceRGBColorSpace, planes);
}

@end

/* One Unicode view: the document, its window, and the view in it. */
@interface UnicodeItem : NSObject
{
@public
    EditorDoc   *doc;                         /* not retained */
    NSWindow    *window;
    UnicodeView *view;
}
@end

@implementation UnicodeItem
- (void)dealloc
{
    [window release];
    [super dealloc];
}
@end

@interface UnicodeController (Private)
- (UnicodeItem *)itemFor:(EditorDoc *)d;
- (void)refreshItem:(UnicodeItem *)it;
- (void)windowClosing:(NSNotification *)n;
- (void)windowResized:(NSNotification *)n;
- (BOOL)haveFonts;
@end

@implementation UnicodeController

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

- (UnicodeItem *)itemFor:(EditorDoc *)d
{
    unsigned int i;

    for (i = 0; i < [items count]; i++)
        if (((UnicodeItem *)[items objectAtIndex:i])->doc == d) return [items objectAtIndex:i];
    return nil;
}

- (BOOL)hasViewFor:(EditorDoc *)d { return [self itemFor:d] != nil; }

- (BOOL)haveFonts
{
    return [Appearance unicodeFonts] != nil && [[Appearance unicodeFonts] length] > 0;
}

- (void)refreshItem:(UnicodeItem *)it
{
    NSString *s = [it->doc expandedString:[[it->doc textView] string]];
    double t0 = [NSDate timeIntervalSinceReferenceDate];

    [it->view setString:s];
    SSTrace("unicode view: %u characters laid out in %.0f ms", (unsigned)[s length], ([NSDate timeIntervalSinceReferenceDate] - t0) * 1000.0);
}

- (void)toggleFor:(EditorDoc *)d
{
    UnicodeItem *it = [self itemFor:d];
    NSRect dr, fr;
    NSScrollView *sv;
    int ok;

    if (it != nil) {
        [[it retain] autorelease];
        [it->window close];
        return;
    }
    if (![self haveFonts]) {
        NSRunAlertPanel(@"Pilcrow", @"The Unicode view draws text itself from font files. Choose one or more (TrueType or OpenType; the first is the main font, the others supply the characters it lacks, such as Japanese ones).", @"OK", nil, nil);
        [self chooseFonts];
        if (![self haveFonts]) return;
    }
    it = [[[UnicodeItem alloc] init] autorelease];
    it->doc = d;
    dr = [[d window] frame];
    fr = NSMakeRect(NSMaxX(dr) + 6.0, dr.origin.y, 560.0, dr.size.height);
    if ([NSScreen mainScreen] != nil && NSMaxX(fr) > NSMaxX([[NSScreen mainScreen] frame])) fr.origin.x = dr.origin.x + 30.0, fr.origin.y = dr.origin.y - 30.0;
    it->window = [[NSWindow alloc] initWithContentRect:fr
                                             styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
                                               backing:NSBackingStoreBuffered defer:NO];
    [it->window setReleasedWhenClosed:NO];
    [it->window setTitle:[NSString stringWithFormat:@"Unicode: %@", [[d window] title]]];
    sv = [[[NSScrollView alloc] initWithFrame:[[it->window contentView] bounds]] autorelease];
    [sv setHasVerticalScroller:YES];
    [sv setHasHorizontalScroller:YES];
    [sv setBorderType:NSNoBorder];
    [sv setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    it->view = [[[UnicodeView alloc] initWithFrame:NSMakeRect(0, 0, [sv contentSize].width, [sv contentSize].height)] autorelease];
    ok = [it->view setFonts:[Appearance unicodeFonts] size:[Appearance unicodeFontSize]];
    SSTrace("unicode view: %d font file(s) usable of %s", ok, SSCS([Appearance unicodeFonts]));
    [sv setDocumentView:it->view];
    [[it->window contentView] addSubview:sv];
    [items addObject:it];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowClosing:)
                                                 name:NSWindowWillCloseNotification object:it->window];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowResized:)
                                                 name:NSWindowDidResizeNotification object:it->window];
    if (ok == 0) {
        NSRunAlertPanel(@"Pilcrow", @"None of the chosen font files can be used.", @"OK", nil, nil);
    }
    [self refreshItem:it];
    if ([[d window] isVisible]) [it->window orderFront:nil];
}

- (void)windowResized:(NSNotification *)n
{
    unsigned int i;

    for (i = 0; i < [items count]; i++) {
        UnicodeItem *it = [items objectAtIndex:i];

        if (it->window == [n object]) [it->view fitToSuperview];
    }
}

- (void)windowClosing:(NSNotification *)n
{
    unsigned int i;

    for (i = 0; i < [items count]; i++) {
        UnicodeItem *it = [items objectAtIndex:i];

        if (it->window == [n object]) {
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshItem:) object:it];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:it->window];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidResizeNotification object:it->window];
            [items removeObjectAtIndex:i];
            return;
        }
    }
}

- (void)documentChanged:(EditorDoc *)d
{
    UnicodeItem *it = [self itemFor:d];

    if (it == nil) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshItem:) object:it];
    [self performSelector:@selector(refreshItem:) withObject:it afterDelay:VIEW_DELAY];
}

- (void)documentClosed:(EditorDoc *)d
{
    UnicodeItem *it = [self itemFor:d];

    if (it != nil) {
        [[it retain] autorelease];
        [it->window close];
    }
}

- (void)chooseFonts
{
    NSOpenPanel *op = [NSOpenPanel openPanel];
    NSArray *files;
    NSString *dir = [Appearance unicodeFonts] != nil ? [[[[Appearance unicodeFonts] componentsSeparatedByString:@":"] objectAtIndex:0] stringByDeletingLastPathComponent] : @"/LocalLibrary/Fonts";
    unsigned int i;

    [op setTitle:@"Unicode View Fonts"];
    [op setAllowsMultipleSelection:YES];
    [op setCanChooseDirectories:NO];
    if ([op runModalForDirectory:dir file:nil types:nil] != NSOKButton) return;
    files = [op filenames];
    if ([files count] == 0) return;
    [Appearance setUnicodeFonts:[files componentsJoinedByString:@":"]];
    [Appearance saveSettings];
    for (i = 0; i < [items count]; i++) {
        UnicodeItem *it = [items objectAtIndex:i];

        [it->view setFonts:[Appearance unicodeFonts] size:[Appearance unicodeFontSize]];
        [self refreshItem:it];
    }
}

@end
