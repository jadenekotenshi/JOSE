#import "Compat.h"
#import "HKSyntaxHighlighter.h"
#include "undo.h"

@class EditorDoc;
@class LineNumberView;

/* The text view of an editor window.  It asks the highlighter to colour what is about to be drawn. */
@interface EditTextView : NSTextView
{
    HKSyntaxHighlighter *highlighter;      /* not retained: the document owns it */
    id                   editor;           /* the EditorDoc, not retained: asked about Return, Tab and typing a brace */
    BOOL                 rectOn;           /* a rectangular selection (Option-drag) is showing */
    BOOL                 rectBusy;         /* the rectangle itself is moving the insertion point: do not take that for a click */
    unsigned int         rectAnchorLine;   /* the start of the line, and the column, where the drag began ... */
    unsigned int         rectAnchorCol;
    unsigned int         rectCurLine;      /* ... and where it is now */
    unsigned int         rectCurCol;
    BOOL                 mouseActive;      /* a click or drag is in progress */
}
- (void)setHighlighter:(HKSyntaxHighlighter *)h;
- (void)setEditor:(id)anEditor;
- (BOOL)mouseActive;
- (BOOL)rectActive;
- (void)rectClear;
- (void)rectSelectionMoved;                /* the selection changed: forget the rectangle unless it caused it */
/* The rectangle: the whole lines it covers (without the final newline) and the columns [*c0, *c1).  NO if there is none. */
- (BOOL)rectLines:(NSRange *)lines columns:(unsigned int *)c0 :(unsigned int *)c1;
/* Shows a rectangle over the lines of `region` (a range of whole lines) and puts the insertion point at its top. */
- (void)rectShowLines:(NSRange)region columns:(unsigned int)c0 :(unsigned int)c1;
@end

/* One open file: a window, its text, the file it came from, and its language mode. */
@interface EditorDoc : NSObject
{
    NSWindow            *window;
    NSScrollView        *scroll;
    EditTextView        *textView;
    NSTextField         *status;
    NSString            *path;             /* nil for a new, unsaved document */
    NSString            *mode;             /* a syntax file's base name, or nil for plain text */
    HKSyntaxHighlighter *highlighter;
    id                   owner;            /* the AppController: told when the window closes */
    BOOL                 dirty;
    BOOL                 wrap;
    Undo                *undo;
    unsigned long        savedVersion;     /* undo_version() when the file was last read or written */
    unsigned             expectedCaret;    /* where the insertion point should be after the last edit (to see when it moves away) */
    NSTimeInterval       clockBase;
    LineNumberView      *ruler;            /* nil until line numbers are first shown */
    BOOL                 lineNumbers;
    BOOL                 autoIndent;       /* Return copies the indentation (and adds a level after a brace/colon) */
    BOOL                 useSpaces;        /* indent with spaces rather than tabs; Tab inserts spaces */
    int                  indentWidth;      /* spaces per level */
    int                  eol;              /* 0 = LF, 1 = CRLF, 2 = CR: what the file used, kept on save */
    NSMutableDictionary *folds;            /* fold number -> the text it hides; only ever added to, so undo can always find it */
    unsigned int         foldNext;
    BOOL                 snapping;         /* the selection is being moved off a fold marker */
    NSRange              prevSel;
}
- (id)initWithOwner:(id)anOwner;
- (BOOL)openFile:(NSString *)aPath;        /* NO (and an alert) if it cannot be read */
- (BOOL)save;                              /* YES if saved (asks for a name if there is none) */
- (BOOL)saveAs;
- (BOOL)revert;
- (BOOL)closeWindow;                       /* asks about unsaved changes; YES if the window was closed */
- (void)setMode:(NSString *)aMode;         /* nil: plain text */
- (NSString *)mode;
- (void)setWrap:(BOOL)flag;
- (BOOL)wrap;
- (BOOL)isDirty;
- (NSString *)path;
- (NSWindow *)window;
- (EditTextView *)textView;
- (void)goToLine:(int)line;
- (void)replaceRange:(NSRange)range with:(NSString *)str select:(NSRange)sel;   /* one undoable step */
- (BOOL)canUndo;
- (BOOL)canRedo;
- (void)undo;
- (void)redo;
- (void)setLineNumbers:(BOOL)flag;
- (BOOL)lineNumbers;
- (void)gotoMatchingBracket:(BOOL)select;   /* the caret to the bracket that goes with the one at/before it, or select up to it */
- (void)setAutoIndent:(BOOL)flag;
- (BOOL)autoIndent;
- (void)setUseSpaces:(BOOL)flag;
- (BOOL)useSpaces;
- (void)setIndentWidth:(int)width;
- (int)indentWidth;
- (void)shiftSelection:(int)direction;     /* the selected lines one level right (+1) or left (-1) */
- (void)commentSelection:(BOOL)comment;    /* comment out (YES) or uncomment (NO) the selected lines */
- (BOOL)newlineWithIndent;                 /* YES if it inserted the new line itself */
- (void)willInsertText:(NSString *)str;    /* a typed '}' takes its line back a level first */
- (BOOL)tabInsertedSpaces;                 /* YES if it inserted spaces for a Tab itself */
- (void)fillWithWidth:(int)width;          /* re-flow the selected lines, or the paragraph with the insertion point */
- (BOOL)rectActive;                        /* a rectangular selection is showing */
- (BOOL)rectCopyAndCut:(BOOL)cut;          /* the rectangle to the pasteboard (and out of the text, with cut) */
- (void)rectType:(NSString *)str;          /* typed text goes into every line of the rectangle */
- (void)rectDeleteBackward:(BOOL)backward; /* the rectangle's text, or the column before/after a zero-width one */
- (BOOL)rectPaste;                         /* the pasteboard as a block at the rectangle or the insertion point; NO if it is not */
- (BOOL)pasteIsRectangle;                  /* the pasteboard holds what Copy last took from a rectangle */
- (NSString *)workingDirectory;            /* the file's folder, or the home folder */
- (BOOL)hasFolds;                          /* some code is folded */
- (void)toggleFold;                        /* fold the block at the insertion point, or unfold the marker on its line */
- (void)foldAll;                           /* fold every outermost block that spans several lines */
- (void)expandAllFolds;                    /* put all hidden code back (one undo step) */
- (NSString *)expandedString:(NSString *)s;   /* s with every fold marker replaced by the code it hides */
- (BOOL)copyExpandedSelectionAndCut:(BOOL)cut;   /* a selection that holds markers goes to the pasteboard with the code; NO if it holds none */
- (void)mouseSelectionDone;                /* a click ended: a marker that was clicked on opens */
- (void)showWindow;
@end
