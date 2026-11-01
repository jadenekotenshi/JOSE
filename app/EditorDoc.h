#import "Compat.h"
#import "HKSyntaxHighlighter.h"
#include "undo.h"
#include "foldlines.h"

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
    int                  macroSuppress;    /* above 0 while an action is being done: what it does inside is not a thing to learn */
}
- (unsigned int)lineStartForPoint:(NSPoint)p;   /* the line at a point of this view's coordinates */
- (void)setHighlighter:(HKSyntaxHighlighter *)h;
- (void)setEditor:(id)anEditor;
- (BOOL)mouseActive;
- (void)macroAction:(SEL)sel sender:(id)sender;   /* learn an action, then let the text view do it */
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
    FoldLines            foldInfo;         /* the lines that can be folded or are folded, for the fold margin */
    EditTextView        *originalView;     /* the first pane's view: never taken away, so the text storage it owns stays put */
    NSSplitView         *split;            /* nil unless the window is split into two panes */
    NSScrollView        *altScroll;        /* the pane that is not the active one (nil if not split); textView/scroll/ruler are the active pane */
    EditTextView        *altView;
    LineNumberView      *altRuler;
    NSString            *statusNote;       /* extra words for the status line until the selection moves */
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
- (int)findUnmatchedBracket;                /* selects the next bracket or block word without a partner (after the selection, wrapping round); returns how many such there are, 0 if all are paired */
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
- (NSString *)wordAtCaret;                  /* the identifier the insertion point is in or next to, or nil */
- (NSString *)wordBeforeParenAt:(unsigned int *)at;   /* the name before a `(` just before the insertion point (*at: that paren); else nil, and *at the caret */
- (NSRect)screenRectForCharAt:(unsigned int)idx;      /* where a character is, in screen coordinates */
- (void)revealLine:(int)line pattern:(NSString *)pattern name:(NSString *)name;   /* select a definition: the line with this text, else this line number */
- (void)didTypeOpenParen;                  /* a `(` was typed: perhaps show a call tip */
- (NSString *)lineAtCaret;                  /* the text of the line with the insertion point (no newline) */
- (NSString *)selectedString;              /* the selected text, or nil */
- (int)foldStateForLineStart:(unsigned int)lineStart;   /* 0 nothing, 1 a block begins there, 2 it is folded */
- (void)toggleFoldAtLineStart:(unsigned int)lineStart;
- (void)macroNoteInsert:(NSString *)text;     /* the macro recorder, if one is learning, is told */
- (void)macroNoteAction:(NSString *)selectorName;
- (void)macroStateChanged;                 /* learning began or ended: the status line says so */
- (void)applyAppearance;                   /* the font or colours changed */
- (BOOL)editNearEnd:(NSRange)r with:(NSString *)str;   /* replace a range that lies in the last few lines by hand: YES if it was done (see EditTextView) */
- (BOOL)cutNearEnd;                        /* Cut of a selection in the last few lines, by hand */
- (BOOL)deleteNearEnd:(BOOL)forward;        /* Backspace/Delete in the last few lines, done by hand: YES if it was (see EditTextView) */
- (int)scrollY;                            /* how far the text is scrolled, in points */
- (void)restoreSelection:(NSRange)sel scrollY:(int)y;   /* a saved caret and scroll position (the selection is cut to the text) */
- (void)splitPane;                          /* a second view of the same text under (or over) the first */
- (void)closePane;                         /* closes the pane with the insertion point; the other one fills the window */
- (BOOL)hasSplit;
- (void)paneActivated:(EditTextView *)view;   /* a pane took the focus: it becomes the one the commands work on */
- (void)showWindow;
@end
