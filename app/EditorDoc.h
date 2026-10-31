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
}
- (void)setHighlighter:(HKSyntaxHighlighter *)h;
- (void)setEditor:(id)anEditor;
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
- (void)showWindow;
@end
