#import "LineNumberView.h"
#import "UIHelpers.h"
#import "Appearance.h"
#include "fold.h"

#define CHUNK 1024

@interface LineNumberView (Private)
- (float)thicknessForDigits:(int)d;
- (unsigned int)newlinesFrom:(unsigned int)from to:(unsigned int)to;
- (void)updateThickness;
- (void)drawNumber:(unsigned int)n atY:(float)y height:(float)h;
@end

@implementation LineNumberView

- (id)initWithScrollView:(NSScrollView *)scroll textView:(NSTextView *)tv
{
    self = [super initWithScrollView:scroll orientation:NSVerticalRuler];
    if (self) {
        textView = tv;
        font = [[NSFont userFixedPitchFontOfSize:9.0] retain];
        cacheLine = 1;
        digits = 3;
        [self setReservedThicknessForMarkers:0.0];
        [self setRuleThickness:[self thicknessForDigits:digits]];
    }
    return self;
}

- (void)dealloc
{
    [font release];
    [super dealloc];
}

- (float)thicknessForDigits:(int)d
{
    return (float)d * [font widthOfString:@"0"] + 10.0;
}

/* The number of line breaks in [from, to) of the text, counting those that a fold marker hides. */
- (unsigned int)newlinesFrom:(unsigned int)from to:(unsigned int)to
{
    NSString *s = [textView string];
    unichar buf[CHUNK + 64];
    unsigned int n = 0, pos = from, total = [s length], got, avail, i;

    while (pos < to) {
        got = to - pos;
        if (got > CHUNK) got = CHUNK;
        avail = total - pos < got + 64 ? total - pos : got + 64;
        [s getCharacters:buf range:NSMakeRange(pos, avail)];
        for (i = 0; i < got; i++) if (buf[i] == '\n') n++;
        n += fold_hidden_lines((const u16 *)buf, avail, got);
        pos += got;
    }
    return n;
}

- (unsigned int)lineNumberForChar:(unsigned int)ch
{
    unsigned int len = [[textView string] length];

    if (ch > len) ch = len;
    if (cacheChar > len) { cacheChar = 0; cacheLine = 1; }
    if (ch >= cacheChar) cacheLine += [self newlinesFrom:cacheChar to:ch];
    else if (ch < cacheChar - ch) cacheLine = 1 + [self newlinesFrom:0 to:ch];       /* nearer the top than the cache */
    else cacheLine -= [self newlinesFrom:ch to:cacheChar];
    cacheChar = ch;
    return cacheLine;
}

- (void)updateThickness
{
    int d = 1;
    unsigned int n = totalLines;

    while (n >= 10) { n /= 10; d++; }
    if (d < 3) d = 3;
    if (d != digits) {
        digits = d;
        [self setRuleThickness:[self thicknessForDigits:digits]];
    }
}

- (void)textChangedAt:(unsigned int)loc removedNewlines:(unsigned int)removed insertedNewlines:(unsigned int)inserted
{
    if (loc < cacheChar) { cacheChar = 0; cacheLine = 1; }
    if (totalLines == 0) totalLines = 1 + [self newlinesFrom:0 to:[[textView string] length]];
    else totalLines = totalLines + inserted - removed;
    [self updateThickness];
    [self setNeedsDisplay:YES];
}

- (void)textReplaced
{
    cacheChar = 0;
    cacheLine = 1;
    totalLines = 1 + [self newlinesFrom:0 to:[[textView string] length]];
    [self updateThickness];
    [self setNeedsDisplay:YES];
}

- (void)drawNumber:(unsigned int)n atY:(float)y height:(float)h
{
    char buf[16];
    float w, x;

    sprintf(buf, "%u", n);
    w = [font widthOfString:[NSString stringWithCString:buf]];
    x = [self ruleThickness] - 5.0 - w;
    PSmoveto(x, y + ([font ascender] + (h - ([font ascender] - [font descender])) / 2.0));
    PSshow(buf);
}

- (void)drawHashMarksAndLabelsInRect:(NSRect)rect
{
    NSLayoutManager *lm = [textView layoutManager];
    NSTextContainer *tc = [textView textContainer];
    NSString *str = [textView string];
    NSPoint origin = [textView textContainerOrigin];
    NSRect vis = [textView visibleRect];
    NSRect inContainer = NSMakeRect(vis.origin.x - origin.x, vis.origin.y - origin.y, vis.size.width, vis.size.height);
    NSRange glyphs;
    unsigned int g;

    [[Appearance gutterBackground] set];
    NSRectFill(rect);
    if (![lm respondsToSelector:@selector(lineFragmentRectForGlyphAtIndex:effectiveRange:)] ||
        ![lm respondsToSelector:@selector(characterIndexForGlyphAtIndex:)]) {
        SSTrace("line numbers: this text system cannot tell where the lines are");
        return;
    }
    [font set];
    [[Appearance gutterText] set];
    glyphs = [lm glyphRangeForBoundingRect:inContainer inTextContainer:tc];
    g = glyphs.location;
    while (g < NSMaxRange(glyphs)) {
        NSRange eff;
        NSRect fr = [lm lineFragmentRectForGlyphAtIndex:g effectiveRange:&eff];
        unsigned int ch = [lm characterIndexForGlyphAtIndex:eff.location];
        NSRect r = [self convertRect:NSMakeRect(fr.origin.x + origin.x, fr.origin.y + origin.y, fr.size.width, fr.size.height)
                            fromView:textView];

        if (ch == 0 || [str characterAtIndex:ch - 1] == '\n') [self drawNumber:[self lineNumberForChar:ch] atY:r.origin.y height:r.size.height];
        if (eff.length == 0) break;
        g = NSMaxRange(eff);
    }
    if ([str length] == 0 || [str characterAtIndex:[str length] - 1] == '\n') {
        /* the empty last line after a final newline has no glyphs of its own */
        if ([lm respondsToSelector:@selector(extraLineFragmentRect)]) {
            NSRect fr = [lm extraLineFragmentRect];
            if (fr.size.height > 0.0) {
                NSRect r = [self convertRect:NSMakeRect(fr.origin.x + origin.x, fr.origin.y + origin.y, fr.size.width, fr.size.height)
                                    fromView:textView];
                [self drawNumber:[self lineNumberForChar:[str length]] atY:r.origin.y height:r.size.height];
            }
        }
    }
}

@end
