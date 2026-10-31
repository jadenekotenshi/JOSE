#import "Compat.h"
#import "HKSyntaxHighlighter.h"
#include "undo.h"

@class EditorDoc;

/* The text view of an editor window.  It asks the highlighter to colour what is about to be drawn. */
@interface EditTextView : NSTextView
{
    HKSyntaxHighlighter *highlighter;      /* not retained: the document owns it */
}
- (void)setHighlighter:(HKSyntaxHighlighter *)h;
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
- (void)showWindow;
@end
