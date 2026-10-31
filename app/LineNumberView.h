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
    BOOL         showNumbers;          /* the line numbers ... */
    BOOL         showFold;             /* ... and the + / - column of the fold margin */
    id           foldSource;           /* the EditorDoc, not retained: says which lines can be folded, and folds them */
}
- (id)initWithScrollView:(NSScrollView *)scroll textView:(NSTextView *)tv;
- (unsigned int)lineNumberForChar:(unsigned int)ch;     /* the line a character is on */
- (void)textChangedAt:(unsigned int)loc removedNewlines:(unsigned int)removed insertedNewlines:(unsigned int)inserted;
- (void)setShowNumbers:(BOOL)numbers showFold:(BOOL)fold;
- (void)setFoldSource:(id)source;
- (void)textReplaced;                                    /* the whole text changed (load, revert) */
@end

/* What the ruler asks of the fold source (the EditorDoc). */
@interface NSObject (LineNumberFoldSource)
- (int)foldStateForLineStart:(unsigned int)lineStart;      /* 0 nothing, 1 a block begins there, 2 it is folded */
- (void)toggleFoldAtLineStart:(unsigned int)lineStart;
- (unsigned int)lineStartForPoint:(NSPoint)p;              /* the text view's line at a point of its own coordinates */
@end
