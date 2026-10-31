#import "Compat.h"

/* The line numbers down the left of an editor window: a vertical ruler that numbers the first line fragment of every
 * paragraph (a wrapped line's continuation gets no number).  Counting is done from a remembered position so that scrolling
 * a big file does not count from the top every time. */
@interface LineNumberView : NSRulerView
{
    NSTextView  *textView;             /* not retained */
    NSFont      *font;
    unsigned int cacheChar;            /* a character index known to start a line ... */
    unsigned int cacheLine;            /* ... and its 1-based line number */
    unsigned int totalLines;           /* 0 until counted */
    int          digits;
}
- (id)initWithScrollView:(NSScrollView *)scroll textView:(NSTextView *)tv;
- (unsigned int)lineNumberForChar:(unsigned int)ch;     /* the line a character is on */
- (void)textChangedAt:(unsigned int)loc removedNewlines:(unsigned int)removed insertedNewlines:(unsigned int)inserted;
- (void)textReplaced;                                    /* the whole text changed (load, revert) */
@end
