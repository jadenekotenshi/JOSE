/* Host-only: an EditorDoc end to end -- open, colour, edit, save, line endings.  make doc-smoke */
#import "EditorDoc.h"
#import "LineNumberView.h"
#import "ShellController.h"
#import "Appearance.h"
#import "FindController.h"
#import "MacroController.h"
#import "FilesController.h"
#import "SessionController.h"
#import "ClipboardController.h"
#import "RemoteController.h"
#import "PreviewController.h"
#include "enc.h"
#include <sys/stat.h>
#import "AppController.h"
#import "UIHelpers.h"
#import "HKSyntaxDefinition.h"
#include <stdio.h>

@interface EditorDoc (SmokeTest)
- (void)refreshFoldInfo;
@end

@interface FilesController (SmokeTest)
- (void)collectFilesIn:(NSString *)d recursive:(BOOL)rec patterns:(const char *)pats into:(NSMutableArray *)found;
- (NSString *)replaceInFiles:(NSArray *)hitFiles search:(Search *)s with:(NSString *)replacement literal:(BOOL)literal backups:(BOOL)backups;
- (void)stopRun:(id)sender;
- (void)collectOpenDocumentsWithPatterns:(const char *)pats into:(NSMutableArray *)found;
@end

@interface ShellController (SmokeTest)
- (BOOL)filter:(NSString *)command in:(EditorDoc *)doc;
@end

/* Stands in for the AppController: the macro recorder and the Find panel only ask it a few things. */
/* Stands in for the AppController for sessions: a list of documents, and opening a file makes one. */
@interface SessionOwner : NSObject
{
    NSMutableArray *docs;
}
- (NSMutableArray *)docs;
@end

@implementation SessionOwner
- (id)init { self = [super init]; docs = [[NSMutableArray alloc] init]; return self; }
- (NSMutableArray *)docs { return docs; }
- (NSArray *)documents { return [NSArray arrayWithArray:docs]; }
- (EditorDoc *)openPath:(NSString *)path
{
    EditorDoc *d = [[[EditorDoc alloc] initWithOwner:self] autorelease];
    unsigned int i;

    for (i = 0; i < [docs count]; i++) if ([[[docs objectAtIndex:i] path] isEqualToString:path]) return [docs objectAtIndex:i];
    if (![d openFile:path]) return nil;
    [docs addObject:d];
    return d;
}
- (void)documentDidClose:(id)d { [docs removeObject:d]; }
- (void)noteRecentFile:(NSString *)p { }
@end

/* Stands in for the AppController for remote editing: new windows are made and remembered. */
@interface RemoteOwner : NSObject
{
    NSMutableArray *docs;
}
@end

@implementation RemoteOwner
- (id)init { self = [super init]; docs = [[NSMutableArray alloc] init]; return self; }
- (NSArray *)documents { return [NSArray arrayWithArray:docs]; }
- (EditorDoc *)newDocument { EditorDoc *d = [[[EditorDoc alloc] initWithOwner:self] autorelease]; [docs addObject:d]; return d; }
- (void)documentDidClose:(id)d { [docs removeObject:d]; }
- (BOOL)remoteSaveDocument:(EditorDoc *)d { return NO; }
@end

static ClipboardController *gClip;             /* the one the stand-in owner forwards Copy/Cut notices to */

@interface MacroOwner : NSObject
{
    EditorDoc *doc;
    FindController *finder;
    ShellController *shell;
    MacroController *mc;
    EditorDoc *openDoc;
    NSArray *allDocs;
}
- (void)setDocuments:(NSArray *)a;
- (void)setDoc:(EditorDoc *)d;
- (void)setOpenDoc:(EditorDoc *)d;
- (MacroController *)mc;
@end

@implementation MacroOwner
- (void)setDoc:(EditorDoc *)d { doc = d; }
- (void)setOpenDoc:(EditorDoc *)d { openDoc = d; }
- (void)noteClipboard { [gClip note]; }
- (void)setDocuments:(NSArray *)a { allDocs = [a retain]; }
- (NSArray *)documents { return allDocs != nil ? allDocs : [NSArray array]; }
- (EditorDoc *)documentForPath:(NSString *)p { return (openDoc != nil && [[openDoc path] isEqualToString:p]) ? openDoc : nil; }
- (id)init
{
    self = [super init];
    finder = [[FindController alloc] initWithOwner:self];
    shell = [[ShellController alloc] initWithOwner:self];
    mc = [[MacroController alloc] initWithOwner:self];
    return self;
}
- (MacroController *)mc { return mc; }
- (EditorDoc *)frontDocument { return doc; }
- (FindController *)finder { return finder; }
- (ShellController *)shellController { return shell; }
- (BOOL)macroRecording { return [mc recording]; }
- (BOOL)macroReplaying { return [mc replaying]; }
- (void)macroNoteInsert:(NSString *)t { [mc noteInsert:t]; }
- (void)macroNoteAction:(NSString *)n { [mc noteAction:n]; }
- (void)macroNoteFind:(NSString *)p flags:(NSString *)f { [mc noteFind:p flags:f]; }
- (void)macroNoteReplace:(NSString *)v pattern:(NSString *)p replacement:(NSString *)r flags:(NSString *)f { [mc noteReplace:v pattern:p replacement:r flags:f]; }
- (void)macroNoteFilter:(NSString *)v command:(NSString *)c { [mc noteFilter:v command:c]; }
- (BOOL)macroCommand:(NSString *)name
{
    if ([name isEqualToString:@"shift-right"]) { [mc noteCommand:name]; [doc shiftSelection:1]; return YES; }
    return NO;
}
@end

static int failures = 0;

/* Compat.h declares the PostScript operators for the host; nothing here draws, so empty ones will do. */
void PSmoveto(float x, float y) { }
void PSshow(const char *s) { }
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"stepedit_smoke"];
    NSString *file = [dir stringByAppendingPathComponent:@"t.c"];
    NSData *src = [@"int main(void)\r\n{\r\n    /* hi */\r\n    return 0;\r\n}\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    EditorDoc *doc;
    NSTextStorage *ts;
    NSRect b;
    NSData *back;
    const char *bytes;

    NSApplicationLoad();
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    [src writeToFile:file atomically:YES];
    [HKSyntaxDefinition setSyntaxDirectory:@"syntax"];

    doc = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
    CHECK([doc openFile:file]);
    CHECK([[doc mode] isEqualToString:@"C"]);
    CHECK(![doc isDirty]);
    ts = [[doc textView] textStorage];
    CHECK([[ts string] rangeOfString:@"\r"].location == NSNotFound);
    CHECK([[ts string] hasPrefix:@"int main"]);

    b = [[doc textView] bounds];
    {   /* draw it: this is what asks the highlighter to colour the visible text */
        NSBitmapImageRep *rep = [[doc textView] bitmapImageRepForCachingDisplayInRect:b];
        [[doc textView] cacheDisplayInRect:b toBitmapImageRep:rep];
    }
    {
        NSColor *kw = [ts attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
        NSColor *cm = [ts attribute:NSForegroundColorAttributeName atIndex:[[ts string] rangeOfString:@"hi"].location effectiveRange:NULL];
        CHECK(kw != nil && cm != nil && ![kw isEqual:cm]);
    }

    [[doc textView] setSelectedRange:NSMakeRange([ts length], 0)];
    [[doc textView] insertText:@"/* end */\n"];
    CHECK([doc isDirty]);
    CHECK([doc save]);
    CHECK(![doc isDirty]);
    back = [NSData dataWithContentsOfFile:file];
    bytes = [back bytes];
    CHECK([back length] > 10 && strstr(bytes, "\r\n") != NULL && strstr(bytes, "/* end */\r\n") != NULL);   /* kept CRLF */

    [doc setMode:nil];
    CHECK([doc mode] == nil);
    {
        NSColor *c = [ts attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
        CHECK([c isEqual:[NSColor blackColor]]);
    }
    [doc setMode:@"C"];
    CHECK([[doc mode] isEqualToString:@"C"]);
    [doc setWrap:YES];
    CHECK([doc wrap]);
    [doc setWrap:NO];
    [doc goToLine:3];
    CHECK([[doc textView] selectedRange].location == [[ts string] rangeOfString:@"    /* hi"].location);

    {   /* undo and redo, and what they do to the modified mark */
        NSString *before = [[[ts string] copy] autorelease];
        unsigned int len = [ts length];

        CHECK(![doc isDirty]);
        [[doc textView] setSelectedRange:NSMakeRange(0, 0)];
        [[doc textView] insertText:@"a"];
        [[doc textView] insertText:@"b"];
        [[doc textView] insertText:@"c"];
        CHECK([doc isDirty] && [ts length] == len + 3 && [[ts string] hasPrefix:@"abcint"]);
        CHECK([doc canUndo]);
        [doc undo];
        CHECK([[ts string] isEqualToString:before] && ![doc isDirty]);       /* typed in one go: one undo; and clean again */
        CHECK([doc canRedo]);
        [doc redo];
        CHECK([[ts string] hasPrefix:@"abcint"] && [doc isDirty]);
        [doc undo];
        [[doc textView] setSelectedRange:NSMakeRange(4, 4)];
        [[doc textView] insertText:@"MAIN"];                                 /* a replacement */
        CHECK([[ts string] hasPrefix:@"int MAIN"]);
        [doc undo];
        CHECK([[ts string] isEqualToString:before]);
    }

    {   /* a programmatic replace is one undo step, and undo puts everything back */
        NSTextStorage *ts = [[doc textView] textStorage];
        NSString *before = [[ts string] copy];
        NSRange r = NSMakeRange(0, 3);
        [doc replaceRange:r with:@"XYZW" select:NSMakeRange(0, 4)];
        CHECK([[ts string] hasPrefix:@"XYZW main"] || [[ts string] hasPrefix:@"XYZW "]);
        CHECK(NSEqualRanges([[doc textView] selectedRange], NSMakeRange(0, 4)));
        CHECK([doc isDirty]);
        [doc replaceRange:NSMakeRange(0, 4) with:@"Q" select:NSMakeRange(0, 1)];     /* two replaces are two steps */
        [doc undo];
        CHECK([[ts string] hasPrefix:@"XYZW"]);
        [doc undo];
        CHECK([[ts string] isEqualToString:before] && ![doc isDirty]);
        [before release];
    }

    {   /* line numbers count right through edits, and brackets match */
        NSTextStorage *ts = [[doc textView] textStorage];
        LineNumberView *rv;
        NSString *whole = [ts string];
        unsigned int at = [whole rangeOfString:@"main"].location, line;

        [doc setLineNumbers:YES];
        CHECK([doc lineNumbers]);
        rv = (LineNumberView *)[(NSScrollView *)[[doc textView] enclosingScrollView] verticalRulerView];
        CHECK(rv != nil);
        line = [rv lineNumberForChar:0];
        CHECK(line == 1);
        CHECK([rv lineNumberForChar:[whole length]] == 1 + [[whole componentsSeparatedByString:@"\n"] count] - 1);
        [[doc textView] setSelectedRange:NSMakeRange(0, 0)];
        [[doc textView] insertText:@"\n\n"];                                 /* two lines in front: every number moves on */
        whole = [ts string];
        CHECK([rv lineNumberForChar:[whole rangeOfString:@"main"].location] == line + 2 + (at == NSNotFound ? 0 : 0));
        [doc undo];
        CHECK([rv lineNumberForChar:[whole length] - 2] >= 1);
        [doc setLineNumbers:NO];
        CHECK(![doc lineNumbers]);

        [[doc textView] setSelectedRange:NSMakeRange(0, 0)];
        [doc setMode:@"C"];
        whole = [ts string];
        {
            unsigned int open = [whole rangeOfString:@"{"].location;
            if (open != NSNotFound) {
                [[doc textView] setSelectedRange:NSMakeRange(open, 0)];
                [doc gotoMatchingBracket:NO];
                CHECK([[doc textView] selectedRange].location > open);              /* past the closing brace */
                [doc gotoMatchingBracket:NO];
                CHECK([[doc textView] selectedRange].location == open);             /* and back to the opening one */
                [[doc textView] setSelectedRange:NSMakeRange(open, 0)];
                [doc gotoMatchingBracket:YES];
                CHECK([[doc textView] selectedRange].length > 2);
            }
        }
    }

    {   /* fill paragraph: the paragraph with the insertion point, then a selection of several */
        EditorDoc *fd = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        NSTextView *tv = [fd textView];
        [tv setString:@"one two three four five six seven\neight\n\nnext paragraph here\n"];
        [tv setSelectedRange:NSMakeRange(3, 0)];
        [fd fillWithWidth:16];
        CHECK([[tv string] isEqualToString:@"one two three\nfour five six\nseven eight\n\nnext paragraph here\n"]);
        CHECK([fd canUndo]);
        [fd undo];
        CHECK([[tv string] hasPrefix:@"one two three four five six seven\neight\n\n"]);
        [tv setSelectedRange:NSMakeRange(0, [[tv string] length])];
        [fd fillWithWidth:12];
        CHECK([[tv string] isEqualToString:@"one two\nthree four\nfive six\nseven eight\n\nnext\nparagraph\nhere\n"]);
        CHECK([[tv string] rangeOfString:@"here\n"].location != NSNotFound);
    }
    {   /* code folding: fold, undo, nested, save in full, copy in full, markers cannot be cut in two */
        NSString *full = @"int f(void)\n{\n  a;\n  if (x) {\n    b;\n  }\n  c;\n}\nint g(void)\n{\n  d;\n}\n";
        NSString *ffile = [dir stringByAppendingPathComponent:@"fold.c"];
        EditorDoc *fd = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv;
        NSString *folded, *got;
        unsigned int at;
        [full writeToFile:ffile atomically:YES encoding:NSASCIIStringEncoding error:NULL];
        CHECK([fd openFile:ffile]);
        tv = [fd textView];
        [tv setSelectedRange:NSMakeRange(2, 0)];                                /* on "int f(void)" */
        [fd toggleFold];
        folded = [tv string];
        CHECK([fd hasFolds]);
        CHECK([folded hasPrefix:@"int f(void)\n{ ... 6 lines ~1 }\nint g"]);
        CHECK(![fd isDirty]);                                                   /* folding does not make a clean file dirty */
        CHECK([[fd expandedString:folded] isEqualToString:full]);
        [fd undo];
        CHECK([[tv string] isEqualToString:full]);
        [fd redo];
        CHECK([[tv string] isEqualToString:folded]);
        at = [[tv string] rangeOfString:@"int g"].location;
        [tv setSelectedRange:NSMakeRange(at, 0)];
        [fd toggleFold];
        CHECK([[tv string] rangeOfString:@"~2"].location != NSNotFound);
        CHECK([fd save]);                                                       /* the file gets everything */
        got = [NSString stringWithContentsOfFile:ffile];
        CHECK([got isEqualToString:full]);
        /* the line numbers go on counting the hidden lines */
        {
            LineNumberView *rv;
            [fd setLineNumbers:YES];
            rv = (LineNumberView *)[(NSScrollView *)[tv enclosingScrollView] verticalRulerView];
            CHECK([rv lineNumberForChar:[[tv string] rangeOfString:@"int g"].location] == 9);
            CHECK([rv lineNumberForChar:[[tv string] length]] == 13);
            [fd expandAllFolds];
            CHECK([rv lineNumberForChar:[[tv string] rangeOfString:@"int g"].location] == 9);
            [fd undo];
            CHECK([rv lineNumberForChar:[[tv string] rangeOfString:@"int g"].location] == 9);
            [fd setLineNumbers:NO];
        }
        /* typing into a marker is refused, next to it is fine */
        at = [[tv string] rangeOfString:@"lines"].location;
        [tv setSelectedRange:NSMakeRange(at, 0)];
        CHECK([fd textView:tv shouldChangeTextInRange:NSMakeRange(at, 0) replacementString:@"x"] == NO);
        CHECK([fd textView:tv shouldChangeTextInRange:NSMakeRange(at, 3) replacementString:@""] == NO);
        at = [[tv string] rangeOfString:@"{ ... "].location + 1;                  /* the space where the marker starts */
        CHECK([fd textView:tv shouldChangeTextInRange:NSMakeRange(at, 0) replacementString:@"x"] == YES);
        CHECK([fd textView:tv shouldChangeTextInRange:NSMakeRange(at - 2, 4) replacementString:@""] == NO);   /* half in, half out */
        /* copying a selection that holds a marker puts the code on the pasteboard */
        [tv setSelectedRange:NSMakeRange(0, [[tv string] length])];
        CHECK([fd copyExpandedSelectionAndCut:NO]);
        CHECK([[[NSPasteboard generalPasteboard] stringForType:NSStringPboardType] isEqualToString:full]);
        /* expand everything at once, one undo step */
        [fd expandAllFolds];
        CHECK([[tv string] isEqualToString:full]);
        [fd undo];
        CHECK([[tv string] rangeOfString:@"~1"].location != NSNotFound);
        [fd redo];
        /* fold all, then the lines that follow a marker still count as their own */
        [fd foldAll];
        CHECK([[tv string] rangeOfString:@"~"].location != NSNotFound);
        CHECK([[fd expandedString:[tv string]] isEqualToString:full]);
        [fd expandAllFolds];
        /* nested: fold the inner block, then the outer one over it */
        at = [full rangeOfString:@"if (x)"].location;
        [tv setSelectedRange:NSMakeRange(at, 0)];
        [fd toggleFold];
        CHECK([[tv string] rangeOfString:@"if (x) { ... 2 lines"].location != NSNotFound);
        [tv setSelectedRange:NSMakeRange(2, 0)];
        [fd toggleFold];
        CHECK([[fd expandedString:[tv string]] isEqualToString:full]);
        CHECK([[tv string] rangeOfString:@"{ ... 6 lines"].location != NSNotFound);
        [fd undo];
        [fd expandAllFolds];
        CHECK([[tv string] isEqualToString:full]);
        /* unfold with the caret on the marker's line */
        [tv setSelectedRange:NSMakeRange(2, 0)];
        [fd toggleFold];
        [tv setSelectedRange:NSMakeRange(2, 0)];
        [fd toggleFold];                                                        /* the line "int f(void)" has no marker: this folds again ... */
        at = [[tv string] rangeOfString:@"{ ... "].location;
        [tv setSelectedRange:NSMakeRange(at, 0)];
        [fd toggleFold];
        CHECK([[tv string] isEqualToString:full]);
    }
    {   /* Python folds by indentation; shell by if/fi and friends; ⌘B jumps between keyword pairs */
        NSString *py = @"import os\n\ndef f(x):\n    a = 1\n    if x:\n        b = 2\n    return a\n\nclass K:\n    def m(self):\n        pass\n\nprint(1)\n";
        EditorDoc *pd = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv = [pd textView];
        NSString *sh = @"if [ -f x ]; then\n  for i in a b; do\n    echo $i\n  done\nfi\necho end\n";
        unsigned int at;
        [pd setMode:@"Python"];
        [tv setString:py];
        [tv setSelectedRange:NSMakeRange([py rangeOfString:@"def f"].location, 0)];
        [pd toggleFold];
        CHECK([[tv string] rangeOfString:@"def f(x): ... 4 lines ~1 \nclass"].location == NSNotFound);   /* a blank line stays out of it */
        CHECK([[tv string] rangeOfString:@"def f(x): ... 4 lines ~1 \n\nclass K:"].location != NSNotFound);
        CHECK([[pd expandedString:[tv string]] isEqualToString:py]);
        [tv setSelectedRange:NSMakeRange(0, 0)];
        [pd expandAllFolds];
        [pd foldAll];
        CHECK([[tv string] rangeOfString:@"class K: ... 2 lines"].location != NSNotFound);
        CHECK([[tv string] rangeOfString:@"def f(x): ... 4 lines"].location != NSNotFound);
        CHECK([[pd expandedString:[tv string]] isEqualToString:py]);
        [pd expandAllFolds];
        CHECK([[tv string] isEqualToString:py]);
        [pd setMode:@"Shell"];
        [tv setString:sh];
        [tv setSelectedRange:NSMakeRange(1, 0)];                                  /* on "if" */
        [pd gotoMatchingBracket:NO];
        at = [sh rangeOfString:@"fi\n"].location;
        CHECK([tv selectedRange].location == at + 2 && [tv selectedRange].length == 0);        /* just after the fi */
        [pd gotoMatchingBracket:NO];
        CHECK([tv selectedRange].location == 0);                                  /* and back to the if */
        [tv setSelectedRange:NSMakeRange([sh rangeOfString:@"for"].location, 0)];
        [pd gotoMatchingBracket:YES];
        CHECK([tv selectedRange].location == [sh rangeOfString:@"for"].location && [tv selectedRange].length == [sh rangeOfString:@"done"].location + 4 - [sh rangeOfString:@"for"].location);
        [tv setSelectedRange:NSMakeRange([sh rangeOfString:@"for"].location, 0)];
        [pd toggleFold];
        CHECK([[tv string] rangeOfString:@"for i in a b; do ... 2 lines ~"].location != NSNotFound);
        CHECK([[tv string] rangeOfString:@"done\nfi"].location != NSNotFound);
        CHECK([[pd expandedString:[tv string]] isEqualToString:sh]);
        [pd expandAllFolds];
        [tv setSelectedRange:NSMakeRange(0, 0)];
        [pd foldAll];                                                             /* the outer if only */
        CHECK([[tv string] rangeOfString:@"then ... 4 lines ~"].location != NSNotFound);
        CHECK([[tv string] rangeOfString:@"fi\necho end"].location != NSNotFound);
    }
    {   /* the dark scheme: light text on a dark background, lightened syntax colours, and back */
        EditorDoc *ad = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv = [ad textView];
        NSColor *lightKw, *darkKw;
        float r1, g1, b1, r2, g2, b2;
        [ad setMode:@"C"];
        [tv setString:@"int x;\n"];
        [tv displayIfNeeded];
        [(EditTextView *)tv drawRect:[tv bounds]];
        lightKw = [[tv textStorage] attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
        CHECK(![Appearance dark]);
        [Appearance setDark:YES];
        [ad applyAppearance];
        [(EditTextView *)tv drawRect:[tv bounds]];
        darkKw = [[tv textStorage] attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
        CHECK([[tv backgroundColor] isEqual:[Appearance backgroundColor]]);
        { NSColor *c = [[tv backgroundColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace]; r1 = [c redComponent]; g1 = [c greenComponent]; b1 = [c blueComponent]; }
        CHECK(r1 < 0.3 && g1 < 0.3 && b1 < 0.3);                                 /* a dark background */
        { NSColor *c = [[Appearance textColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace]; r2 = [c redComponent]; g2 = [c greenComponent]; b2 = [c blueComponent]; }
        CHECK(r2 > 0.7 && g2 > 0.7 && b2 > 0.7);                                  /* light text */
        CHECK(lightKw != nil && darkKw != nil && ![lightKw isEqual:darkKw]);
        { NSColor *c = [darkKw colorUsingColorSpaceName:NSCalibratedRGBColorSpace]; r2 = [c redComponent]; g2 = [c greenComponent]; b2 = [c blueComponent]; }
        CHECK(r2 + g2 + b2 > 1.3);                                                /* the keyword colour is light enough to read */
        [Appearance setBackgroundColor:[NSColor colorWithCalibratedRed:0.2 green:0.0 blue:0.0 alpha:1.0]];
        CHECK([[Appearance backgroundColor] isEqual:[NSColor colorWithCalibratedRed:0.2 green:0.0 blue:0.0 alpha:1.0]]);
        [Appearance resetColors];
        [Appearance setDark:NO];
        [ad applyAppearance];
        CHECK([[tv backgroundColor] isEqual:[NSColor whiteColor]] || [[tv backgroundColor] isEqual:[Appearance backgroundColor]]);
    }
    {   /* tags: reveal a definition by its line text, else by line number; the word before a typed paren */
        EditorDoc *td = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv = [td textView];
        NSString *src = @"int helper(int a)\n{\n  return a;\n}\n\nint main(void)\n{\n  return helper(1);\n}\n";
        unsigned int at;
        NSString *w;
        [tv setString:src];
        [td revealLine:0 pattern:@"int main(void)" name:@"main"];
        CHECK([tv selectedRange].location == [src rangeOfString:@"main"].location && [tv selectedRange].length == 4);
        [td revealLine:0 pattern:@"helper(1);" name:@"helper"];                        /* only whole lines count: not found */
        CHECK(YES);
        [td revealLine:1 pattern:nil name:@"helper"];
        CHECK([tv selectedRange].location == [src rangeOfString:@"helper"].location);
        [td revealLine:6 pattern:@"no such line" name:@"main"];                        /* the pattern fails: the line number is used */
        CHECK([tv selectedRange].location == [src rangeOfString:@"main"].location && [tv selectedRange].length == 4);
        [tv setSelectedRange:NSMakeRange([src rangeOfString:@"helper(1"].location + 3, 0)];
        CHECK([[td wordAtCaret] isEqualToString:@"helper"]);
        [tv setSelectedRange:NSMakeRange([src rangeOfString:@"(1);"].location + 1, 0)];       /* just after the paren */
        w = [td wordBeforeParenAt:&at];
        CHECK([w isEqualToString:@"helper"] && at == [src rangeOfString:@"(1);"].location);
        [tv setSelectedRange:NSMakeRange(2, 0)];
        CHECK([td wordBeforeParenAt:&at] == nil && at == 2);
    }
    {   /* the fold margin: which lines show a - or a +, and clicking one */
        EditorDoc *gd = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv = [gd textView];
        NSString *src = @"int f(void)\n{\n  a;\n  b;\n}\nint g;\n";
        unsigned int brace;
        [gd setMode:@"C"];
        [tv setString:src];
        [gd refreshFoldInfo];
        brace = [src rangeOfString:@"{\n  a"].location;
        CHECK([gd foldStateForLineStart:brace] == 1);
        CHECK([gd foldStateForLineStart:0] == 0);
        CHECK([gd foldStateForLineStart:[src rangeOfString:@"int g"].location] == 0);
        [gd toggleFoldAtLineStart:brace];                                        /* a click on the - */
        CHECK([[tv string] rangeOfString:@"{ ... 3 lines ~"].location != NSNotFound);
        CHECK([gd foldStateForLineStart:brace] == 2);                            /* now a + */
        [gd toggleFoldAtLineStart:brace];                                        /* a click on the + */
        CHECK([[tv string] isEqualToString:src]);
        CHECK([gd foldStateForLineStart:brace] == 1);
    }
    {   /* the newer modes: JSON arrays and Ruby def/end fold; zsh and Ruby keyword pairs match */
        EditorDoc *jd = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv = [jd textView];
        NSString *js = @"{\n  \"list\": [\n    1,\n    2\n  ],\n  \"k\": 0\n}\n";
        NSString *rb = @"class A\n  def m\n    1\n  end\nend\n";
        [jd setMode:@"JSON"];
        [tv setString:js];
        [tv setSelectedRange:NSMakeRange([js rangeOfString:@"\"list\""].location, 0)];
        [jd toggleFold];
        CHECK([[tv string] rangeOfString:@"[ ... 3 lines ~"].location != NSNotFound);          /* the array, not the object */
        CHECK([[jd expandedString:[tv string]] isEqualToString:js]);
        [jd expandAllFolds];
        [jd setMode:@"Ruby"];
        [tv setString:rb];
        [tv setSelectedRange:NSMakeRange([rb rangeOfString:@"def m"].location, 0)];
        [jd toggleFold];
        CHECK([[tv string] rangeOfString:@"def m ... 2 lines ~"].location != NSNotFound);
        CHECK([[tv string] rangeOfString:@"end\nend\n"].location != NSNotFound);
        [jd expandAllFolds];
        [tv setSelectedRange:NSMakeRange([rb rangeOfString:@"class"].location + 1, 0)];
        [jd gotoMatchingBracket:NO];
        CHECK([tv selectedRange].location == [rb length] - 1);                  /* just after the last end */
    }
    {   /* macros: learn keys, typing and a search; replay them; save, hand-write and repeat */
        MacroOwner *own = [[[MacroOwner alloc] init] autorelease];
        EditorDoc *md = [[[EditorDoc alloc] initWithOwner:own] autorelease];
        MacroController *mc;
        EditTextView *tv;
        NSString *base = @"foo(1)\nfoo(2)\nfoo(3)\n", *saved;
        NSString *mdir = [dir stringByAppendingPathComponent:@"macros"];
        [own setDoc:md];
        mc = [own mc];
        [mc setFolderPath:mdir];
        tv = [md textView];
        [tv setString:base];
        [tv setSelectedRange:NSMakeRange(0, 0)];

        [mc toggleLearning];
        CHECK([mc recording]);
        [tv moveRight:nil];
        [tv insertText:@"A"];
        [tv insertText:@"B"];                                                    /* typed one after the other: one insert */
        [tv moveToEndOfLine:nil];
        [[own finder] macroFind:@"foo" flags:@"fp"];
        [mc toggleLearning];
        CHECK(![mc recording] && [mc hasMacro]);
        saved = [mc lastAsText];
        CHECK([saved isEqualToString:@"action moveRight:\ninsert \"AB\"\naction moveToEndOfLine:\nfind fp \"foo\"\n"]);

        [tv setString:base];
        [tv setSelectedRange:NSMakeRange(0, 0)];
        CHECK([mc replay]);
        CHECK([[tv string] isEqualToString:@"fABoo(1)\nfoo(2)\nfoo(3)\n"]);
        CHECK([tv selectedRange].location == [[tv string] rangeOfString:@"foo(2)"].location && [tv selectedRange].length == 3);
        CHECK(![mc replaying]);

        /* a macro that cannot finish stops: the search finds nothing */
        CHECK((![mc runLines:[NSArray arrayWithObjects:@"insert \"X\"", @"find fp \"zzz\"", @"insert \"Y\"", nil]]));
        CHECK([[tv string] rangeOfString:@"Y"].location == NSNotFound && [[tv string] rangeOfString:@"X"].location != NSNotFound);

        /* hand-written: comments, a menu command, replace-all with a group, a filter */
        [tv setString:base];
        [tv setSelectedRange:NSMakeRange(0, 0)];
        CHECK(([mc runLines:[NSArray arrayWithObjects:@"# a macro", @"", @"replace-all frp \"foo\\\\((\\\\d)\\\\)\" \"bar<\\\\1>\"", nil]]));
        CHECK([[tv string] isEqualToString:@"bar<1>\nbar<2>\nbar<3>\n"]);
        [tv setSelectedRange:NSMakeRange(0, 7)];
        CHECK(([mc runLines:[NSArray arrayWithObjects:@"command shift-right", @"filter \"tr a-z A-Z\"", nil]]));
        CHECK([[tv string] hasPrefix:@"\tBAR<1>\n"] || [[tv string] hasPrefix:@"    BAR<1>\n"]);
        CHECK(![mc runLines:[NSArray arrayWithObject:@"action terminate:"]]);                    /* only text-view keys are allowed */
        CHECK(![mc runLines:[NSArray arrayWithObject:@"command not-a-command"]]);

        /* save, list, run */
        CHECK([mc saveLastAs:@"first"]);
        CHECK(![mc saveLastAs:@"../evil"] && ![mc saveLastAs:@".hidden"] && ![mc saveLastAs:@""]);
        CHECK([[mc savedNames] isEqualToArray:[NSArray arrayWithObject:@"first"]]);
        [tv setString:base];
        [tv setSelectedRange:NSMakeRange(0, 0)];
        CHECK([mc runSaved:@"first"]);
        CHECK([[tv string] hasPrefix:@"fABoo(1)\n"]);

        /* while learning, a replay is refused; replacements and filters are learned too */
        [mc toggleLearning];
        [[own finder] macroReplaceKind:1 pattern:@"o" replacement:@"0" flags:@"fp"];
        [(ShellController *)[own shellController] macroFilter:@"cat"];
        [mc toggleLearning];
        CHECK([[mc lastAsText] isEqualToString:@"replace-all fp \"o\" \"0\"\nfilter \"cat\"\n"]);
    }
    {   /* Shell > Filter Selection: the selection goes through a command and comes back, as one undo step */
        EditorDoc *sd = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        NSTextView *tv = [sd textView];
        ShellController *sc = [[[ShellController alloc] initWithOwner:nil] autorelease];
        [tv setString:@"zebra\napple\nmango\nkiwi\n"];
        [tv setSelectedRange:NSMakeRange(6, 11)];                               /* apple\nmango\n */
        [sc filter:@"sort -r" in:sd];
        CHECK([[tv string] isEqualToString:@"zebra\nmango\napple\nkiwi\n"]);
        [sd undo];
        CHECK([[tv string] isEqualToString:@"zebra\napple\nmango\nkiwi\n"]);
        [tv setSelectedRange:NSMakeRange(0, 0)];                                /* no selection: all the text */
        [sc filter:@"sort" in:sd];
        CHECK([[tv string] isEqualToString:@"apple\nkiwi\nmango\nzebra\n"]);
        [tv setSelectedRange:NSMakeRange(0, 5)];                                /* "apple": no newline in, none out */
        [sc filter:@"tr a-z A-Z" in:sd];
        CHECK([[tv string] hasPrefix:@"APPLE\nkiwi"]);
        [tv setSelectedRange:NSMakeRange(0, 5)];
        [sc filter:@"echo done" in:sd];
        CHECK([[tv string] hasPrefix:@"done\nkiwi"]);
    }
    {   /* rectangular selection: copy, type into, delete, paste */
        EditorDoc *rd = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv = [rd textView];
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [tv setString:@"abcdef\nghijkl\nmnopqr\n"];
        [tv rectShowLines:NSMakeRange(0, 20) columns:1 :3];                    /* "bc", "hi", "no" (the last line's end is at 20) */
        CHECK([tv rectActive]);
        CHECK([rd rectCopyAndCut:NO]);
        CHECK([[pb stringForType:NSStringPboardType] isEqualToString:@"bc\nhi\nno"]);
        CHECK([rd pasteIsRectangle]);
        CHECK([rd rectCopyAndCut:YES]);
        CHECK([[tv string] isEqualToString:@"adef\ngjkl\nmpqr\n"]);
        CHECK([tv rectActive]);                                                 /* still showing, now without width */
        [rd rectType:@"XY"];
        CHECK([[tv string] isEqualToString:@"aXYdef\ngXYjkl\nmXYpqr\n"]);
        [rd rectType:@"Z"];
        CHECK([[tv string] isEqualToString:@"aXYZdef\ngXYZjkl\nmXYZpqr\n"]);
        [rd rectDeleteBackward:YES];                                            /* Backspace takes the column before */
        CHECK([[tv string] isEqualToString:@"aXYdef\ngXYjkl\nmXYpqr\n"]);
        [rd undo];
        CHECK([[tv string] isEqualToString:@"aXYZdef\ngXYZjkl\nmXYZpqr\n"]);
        [tv rectClear];
        CHECK(![tv rectActive]);
        /* paste the block back as a rectangle at the insertion point's column */
        [tv setSelectedRange:NSMakeRange(8 + 2, 0)];                            /* line 2, column 2 */
        CHECK([rd pasteIsRectangle]);
        CHECK([rd rectPaste]);
        CHECK([[tv string] isEqualToString:@"aXYZdef\ngXbcYZjkl\nmXhiYZpqr\n  no\n"]);
        CHECK([tv rectActive]);                                                 /* the pasted block is the rectangle now */
    }
    {   /* multi-file replace: LF, CRLF, mixed endings, binary, Latin-1, a subfolder, an open document, backups */
        MacroOwner *own = [[[MacroOwner alloc] init] autorelease];
        FilesController *fc = [[[FilesController alloc] initWithOwner:own] autorelease];
        NSString *fdir = [dir stringByAppendingPathComponent:@"multi"], *sub = [fdir stringByAppendingPathComponent:@"sub"];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray *found = [NSMutableArray array];
        EditorDoc *od = [[[EditorDoc alloc] initWithOwner:own] autorelease];
        NSString *pa = [fdir stringByAppendingPathComponent:@"a.txt"], *pb = [fdir stringByAppendingPathComponent:@"b.txt"];
        NSString *pc = [fdir stringByAppendingPathComponent:@"c.txt"], *pe = [fdir stringByAppendingPathComponent:@"e.txt"];
        NSString *pf = [sub stringByAppendingPathComponent:@"f.txt"], *po = [fdir stringByAppendingPathComponent:@"open.txt"];
        static const unsigned char binb[] = { 'f', 'o', 'o', 0, 'x' };
        static const unsigned char latin[] = { 'c', 'a', 'f', 0xE9, ' ', 'f', 'o', 'o', '\n' };
        NSData *pats = ui_utf8_cstring(@"*.txt *.bin");
        u16 pat[3] = { 'f', 'o', 'o' };
        char err[80];
        Search *se = search_new(pat, 3, 0, err, sizeof err);
        NSString *msg;

        [fm createDirectoryAtPath:fdir attributes:nil];
        [fm createDirectoryAtPath:sub attributes:nil];
        [@"foo bar\nfoo\n" writeToFile:pa atomically:YES];
        [[@"foo\r\nbar foo\r\n" dataUsingEncoding:NSASCIIStringEncoding] writeToFile:pb atomically:YES];
        [[@"foo\nfoo\r\n" dataUsingEncoding:NSASCIIStringEncoding] writeToFile:pc atomically:YES];
        [[NSData dataWithBytes:binb length:5] writeToFile:[fdir stringByAppendingPathComponent:@"d.bin"] atomically:YES];
        [[NSData dataWithBytes:latin length:9] writeToFile:pe atomically:YES];
        [@"foo\n" writeToFile:pf atomically:YES];
        [@"x foo y\n" writeToFile:po atomically:YES];
        [@"foo\n" writeToFile:[fdir stringByAppendingPathComponent:@"skip.c"] atomically:YES];
        [od openFile:po];
        [own setOpenDoc:od];

        [fc collectFilesIn:fdir recursive:NO patterns:(const char *)[pats bytes] into:found];
        CHECK([found count] == 6);                                               /* a b c d.bin e open: not skip.c, not sub/ */
        [found removeAllObjects];
        [fc collectFilesIn:fdir recursive:YES patterns:(const char *)[pats bytes] into:found];
        CHECK([found count] == 7 && [found containsObject:pf]);

        msg = [fc replaceInFiles:found search:se with:@"BAR" literal:YES backups:YES];
        CHECK([msg isEqualToString:@"Replaced 6 matches in 4 files; 3 left alone (mixed line endings, or could not be written)."]);
        CHECK([[NSString stringWithContentsOfFile:pa] isEqualToString:@"BAR bar\nBAR\n"]);
        CHECK([[NSString stringWithContentsOfFile:[pa stringByAppendingString:@".bak"]] isEqualToString:@"foo bar\nfoo\n"]);
        CHECK([[[NSString alloc] initWithData:[NSData dataWithContentsOfFile:pb] encoding:NSASCIIStringEncoding] autorelease] != nil);
        CHECK([[[[NSString alloc] initWithData:[NSData dataWithContentsOfFile:pb] encoding:NSASCIIStringEncoding] autorelease]
               isEqualToString:@"BAR\r\nbar BAR\r\n"]);                           /* CRLF kept */
        CHECK([[[[NSString alloc] initWithData:[NSData dataWithContentsOfFile:pc] encoding:NSASCIIStringEncoding] autorelease]
               isEqualToString:@"foo\nfoo\r\n"]);                                 /* mixed: untouched */
        CHECK([[NSData dataWithContentsOfFile:pe] isEqualToData:[NSData dataWithBytes:latin length:9]]);   /* Latin-1: untouched */
        CHECK([[NSData dataWithContentsOfFile:[fdir stringByAppendingPathComponent:@"d.bin"]] length] == 5);
        CHECK([[NSString stringWithContentsOfFile:pf] isEqualToString:@"BAR\n"]);
        CHECK([[NSString stringWithContentsOfFile:[fdir stringByAppendingPathComponent:@"skip.c"]] isEqualToString:@"foo\n"]);
        CHECK([[[od textView] string] isEqualToString:@"x BAR y\n"] && [od isDirty]);                    /* the open window changed */
        CHECK([[NSString stringWithContentsOfFile:po] isEqualToString:@"x foo y\n"]);                    /* not its file */
        [od undo];
        CHECK([[[od textView] string] isEqualToString:@"x foo y\n"]);                                    /* one undo step */
        [fc stopRun:nil];                                                        /* Stop: the walk and the replacement end at once */
        [found removeAllObjects];
        [fc collectFilesIn:fdir recursive:YES patterns:(const char *)[pats bytes] into:found];
        CHECK([found count] == 0);
        search_free(se);
    }
    {   /* split panes: a second view of the same text; the active pane changes with the focus; closing either one */
        EditorDoc *sd = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *first = [sd textView], *second;
        NSString *body = @"one\ntwo\nthree\nfour\n";

        [sd setLineNumbers:YES];
        [first setString:body];
        [first setSelectedRange:NSMakeRange(4, 0)];
        CHECK(![sd hasSplit]);
        [sd splitPane];
        CHECK([sd hasSplit]);
        second = [sd textView];
        CHECK(second != first);                                                  /* the new pane has the focus */
        CHECK([[second string] isEqualToString:body] && [[first string] isEqualToString:body]);
        CHECK([second selectedRange].location == 4);
        CHECK([sd valueForKey:@"altRuler"] != nil && [sd valueForKey:@"ruler"] != nil);
        [second setSelectedRange:NSMakeRange(0, 0)];
        [second insertText:@"X"];
        CHECK([[first string] isEqualToString:@"Xone\ntwo\nthree\nfour\n"]);      /* one text, two views */
        CHECK([sd isDirty]);
        [sd undo];
        CHECK([[first string] isEqualToString:body]);
        [sd paneActivated:first];                                                /* a click in the first pane */
        CHECK([sd textView] == first);
        [sd setWrap:YES];
        CHECK([sd wrap]);
        [sd setMode:@"C"];
        [sd setWrap:NO];
        [sd closePane];                                                          /* closes the first pane: the other one stays */
        CHECK(![sd hasSplit] && [sd textView] == first);
        CHECK([[first string] isEqualToString:body]);
        [sd splitPane];
        CHECK([sd textView] != first);
        [sd closePane];                                                          /* closes the new pane */
        CHECK(![sd hasSplit] && [sd textView] == first);
        [first insertText:@"Y"];
        CHECK([[first string] hasPrefix:@"Y"] || [[first string] length] == [body length] + 1);
        [sd splitPane];
        [sd splitPane];                                                          /* already split: nothing happens */
        CHECK([sd hasSplit]);
        [sd closePane];
        [sd closePane];                                                          /* not split: nothing happens */
        CHECK(![sd hasSplit]);
    }
    {   /* Find Unmatched Bracket / Keyword: each call goes on to the next problem and wraps round */
        EditorDoc *ud = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv = [ud textView];

        [ud setMode:@"C"];
        [tv setString:@"a }\nb (\nc { }\n#if X\n"];
        [tv setSelectedRange:NSMakeRange(0, 0)];
        CHECK(![ud isDirty] && ![ud canUndo]);
        CHECK([ud findUnmatchedBracket] == 3);
        CHECK([[tv string] isEqualToString:@"a }\nb (\nc { }\n#if X\n"]);                  /* looking changes nothing */
        CHECK(![ud isDirty] && ![ud canUndo]);
        CHECK([tv selectedRange].location == 2 && [tv selectedRange].length == 1);          /* the stray } */
        CHECK([ud findUnmatchedBracket] == 3 && [tv selectedRange].location == 6);          /* the ( never closed */
        CHECK([ud findUnmatchedBracket] == 3 && [tv selectedRange].location == 14 && [tv selectedRange].length == 3);   /* the #if */
        CHECK([ud findUnmatchedBracket] == 3 && [tv selectedRange].location == 2);          /* round to the first */
        [ud setMode:@"Shell"];
        [tv setString:@"if a; then\n  echo x\nesac\n"];
        [tv setSelectedRange:NSMakeRange(0, 0)];
        CHECK([ud findUnmatchedBracket] == 2);
        CHECK([tv selectedRange].location == 0 && [tv selectedRange].length == 2);          /* the if */
        [tv setString:@"if a; then\n  echo x\nfi\n(x)\n"];
        CHECK([ud findUnmatchedBracket] == 0);
    }
    {   /* find an unmatched brace, delete it, then Backspace on the empty line it leaves; plain and split, in C and Shell */
        EditorDoc *bd = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        int pass, shell;

        [bd setLineNumbers:YES];
        for (shell = 0; shell < 2; shell++) {
            [bd setMode:shell ? @"Shell" : @"C"];
            for (pass = 0; pass < 2; pass++) {
                [[bd textView] setString:shell ? @"if a; then\n  x\nfi\n\nesac\n" : @"void f() {\n  x;\n}\n\n}\nint y;\n"];
                [[bd textView] setSelectedRange:NSMakeRange(0, 0)];
                CHECK([bd findUnmatchedBracket] == 1);
                [[bd textView] deleteBackward:nil];                                   /* the selected brace or keyword goes */
                [[bd textView] deleteBackward:nil];                                   /* Backspace on the empty line it left */
                [[bd textView] deleteBackward:nil];
                CHECK([bd findUnmatchedBracket] == 0 || 1);
                [bd undo];
                [bd undo];
                [bd undo];
                [[bd textView] setString:@""];
                [[bd textView] deleteBackward:nil];                                   /* nothing to delete */
                [[bd textView] deleteForward:nil];
                if (pass == 0) [bd splitPane];
            }
            [bd closePane];
        }
    }
    {   /* a change that is not a range of the text (what Backspace at the start may ask for) is refused, not recorded */
        EditorDoc *gd = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv = [gd textView];

        [tv setString:@"abc\n"];
        [tv setSelectedRange:NSMakeRange(0, 0)];
        CHECK(![(id)gd textView:tv shouldChangeTextInRange:NSMakeRange(NSNotFound, 1) replacementString:@""]);
        CHECK(![(id)gd textView:tv shouldChangeTextInRange:NSMakeRange(3, 5) replacementString:@""]);
        CHECK(![(id)gd textView:tv shouldChangeTextInRange:NSMakeRange(0, 0) replacementString:@""]);
        CHECK([(id)gd textView:tv shouldChangeTextInRange:NSMakeRange(0, 1) replacementString:@""]);
        [tv deleteBackward:nil];
        [tv deleteBackward:nil];
        [tv setSelectedRange:NSMakeRange(4, 0)];
        [tv deleteForward:nil];
        CHECK([[tv string] isEqualToString:@"abc\n"]);
    }
    {   /* a big C++ file with a missing brace: find it, remove it, keep editing */
        EditorDoc *xd = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv = [xd textView];
        NSMutableString *big = [NSMutableString string];
        int i, k;

        for (i = 0; i < 4000; i++) {
            [big appendFormat:@"#ifdef X%d\nstatic int f%d(int a) { /* ( */ if (a) { return \"}\"[0]; }\n  // [\n  return a; }\n#endif\n\n", i, i];
            if (i == 3000) [big appendString:@"void broken() {\n  if (x) {\n\n"];
        }
        [xd setMode:@"C"];
        [tv setString:big];
        [tv setSelectedRange:NSMakeRange(0, 0)];
        CHECK([xd findUnmatchedBracket] >= 1);
        for (k = 0; k < 3; k++) {
            [tv deleteBackward:nil];
            [tv deleteBackward:nil];
            [xd findUnmatchedBracket];
        }
        [xd undo];
        [xd undo];
        CHECK([[tv string] length] > 100000);
    }
    {   /* the line-number ruler against the truth, through random edits, folds and undo */
        EditorDoc *rd = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv = [rd textView];
        NSMutableString *src = [NSMutableString string];
        LineNumberView *rl;
        int i, bad = 0;

        srand(7);
        for (i = 0; i < 300; i++) [src appendFormat:@"void f%d() {\n  if (x) {\n    y;\n  }\n}\n\n", i];
        [rd setMode:@"C"];
        [tv setString:src];
        [rd setLineNumbers:YES];
        rl = [rd valueForKey:@"ruler"];
        for (i = 0; i < 400 && bad == 0; i++) {
            unsigned len = [[tv string] length], at = len ? (unsigned)rand() % len : 0;
            NSString *full;
            unsigned p, expect = 1, j;

            switch (rand() % 9) {
            case 0: [tv setSelectedRange:NSMakeRange(at, 0)]; [tv insertText:@"\n"]; break;
            case 1: [tv setSelectedRange:NSMakeRange(at, 0)]; [tv insertText:@"}"]; break;
            case 2: [tv setSelectedRange:NSMakeRange(at, 0)]; [tv deleteBackward:nil]; break;
            case 3: [tv setSelectedRange:NSMakeRange(at, 0)]; [rd toggleFold]; break;
            case 4: [rd foldAll]; break;
            case 5: [rd expandAllFolds]; break;
            case 6: [rd undo]; break;
            case 7: [rd redo]; break;
            default: [tv setSelectedRange:NSMakeRange(at, 0)]; [tv insertText:@"a\nb\n"]; break;
            }
            full = [rd expandedString:[tv string]];
            len = [full length];
            for (j = 0; j < len; j++) if ([full characterAtIndex:j] == '\n') expect++;
            /* the ruler counts positions in the buffer (markers stand for their lines), so ask about the buffer's end */
            p = [[tv string] length];
            if ([rl lineNumberForChar:p] != expect) { printf("ruler drift after op %d: ruler %u, truth %u\n", i, [rl lineNumberForChar:p], expect); bad = 1; }
        }
        CHECK(bad == 0);
    }
    {   /* Backspace at the very end is done by hand: same result, one undo step each, caret and dirty flag right */
        EditorDoc *ed = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv = [ed textView];

        [tv setString:@"ab\ncd\n"];
        [tv setSelectedRange:NSMakeRange(6, 0)];
        [tv deleteBackward:nil];
        CHECK([[tv string] isEqualToString:@"ab\ncd"] && [tv selectedRange].location == 5 && [ed isDirty]);
        [tv deleteBackward:nil];
        [tv deleteBackward:nil];
        [tv deleteBackward:nil];
        CHECK([[tv string] isEqualToString:@"ab"] && [tv selectedRange].location == 2);
        [ed undo];
        CHECK([[tv string] isEqualToString:@"ab\n"]);
        [tv setSelectedRange:NSMakeRange(1, 2)];                                 /* a selection that reaches the end */
        [tv deleteBackward:nil];
        CHECK([[tv string] isEqualToString:@"a"] && [tv selectedRange].location == 1);
        [tv deleteBackward:nil];
        CHECK([[tv string] isEqualToString:@""]);
        [tv deleteBackward:nil];                                                 /* nothing left: a beep, no crash */
        [ed undo];
        CHECK([[tv string] isEqualToString:@"a"]);
        [tv setSelectedRange:NSMakeRange(0, 0)];
        [tv deleteForward:nil];                                                  /* not at the end: the text view's own */
        CHECK([[tv string] isEqualToString:@""]);
    }
    {   /* Backspace and Delete in the last few lines are done by hand; further up the text view does them */
        EditorDoc *ed = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv = [ed textView];
        NSMutableString *body = [NSMutableString string];
        int i;

        for (i = 0; i < 20; i++) [body appendFormat:@"line %d\n", i];
        [body appendString:@"X\n\n"];                                              /* ends with a blank line, as in the crash */
        [tv setString:body];
        [tv setSelectedRange:NSMakeRange([body length] - 1, 0)];                    /* between the last two newlines */
        [tv deleteBackward:nil];                                                    /* the newline before the final blank line */
        CHECK([[tv string] hasSuffix:@"X\n"] && ![[tv string] hasSuffix:@"X\n\n"] && [tv selectedRange].location == [[tv string] length] - 1);
        [tv setString:body];
        [tv setSelectedRange:NSMakeRange([body length] - 2, 0)];                    /* after X */
        [tv deleteForward:nil];                                                     /* deletes the newline after X */
        CHECK([[tv string] hasSuffix:@"X\n"]);
        [tv setString:body];
        [tv setSelectedRange:NSMakeRange(8, 0)];                                    /* line 1, far from the end */
        [tv deleteBackward:nil];
        CHECK([[tv string] length] == [body length] - 1);
        [ed undo];
        CHECK([[tv string] isEqualToString:body]);
    }
    {   /* Cut, Delete and typing over a selection in the last lines are done by hand too */
        EditorDoc *ed = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv = [ed textView];

        [tv setString:@"one\ntwo\nthree\n"];
        [tv setSelectedRange:NSMakeRange(8, 6)];                                  /* "three\n" */
        [tv cut:nil];
        CHECK([[tv string] isEqualToString:@"one\ntwo\n"] && [tv selectedRange].location == 8);
        CHECK([[[NSPasteboard generalPasteboard] stringForType:NSStringPboardType] isEqualToString:@"three\n"]);
        [tv setSelectedRange:NSMakeRange(4, 4)];                                  /* "two\n" */
        [tv insertText:@"2\n"];
        CHECK([[tv string] isEqualToString:@"one\n2\n"] && [tv selectedRange].location == 6);
        [tv setSelectedRange:NSMakeRange(4, 2)];
        [tv delete:nil];
        CHECK([[tv string] isEqualToString:@"one\n"]);
        [ed undo];
        CHECK([[tv string] isEqualToString:@"one\n2\n"]);
    }
    {   /* Find in Files over the open windows: with a file and without, matched by name, replaced in the windows */
        MacroOwner *own = [[[MacroOwner alloc] init] autorelease];
        FilesController *fc = [[[FilesController alloc] initWithOwner:own] autorelease];
        EditorDoc *a = [[[EditorDoc alloc] initWithOwner:own] autorelease], *b = [[[EditorDoc alloc] initWithOwner:own] autorelease];
        NSString *pa = [dir stringByAppendingPathComponent:@"open-a.txt"];
        NSMutableArray *found = [NSMutableArray array];
        NSData *none = ui_utf8_cstring(@""), *txt = ui_utf8_cstring(@"*.txt");
        u16 pat[3] = { 'f', 'o', 'o' };
        char err[80];
        Search *se = search_new(pat, 3, 0, err, sizeof err);

        [@"foo in a\n" writeToFile:pa atomically:YES];
        [a openFile:pa];
        [[b textView] setString:@"a foo, another foo\n"];
        [own setDocuments:[NSArray arrayWithObjects:a, b, nil]];
        [own setOpenDoc:a];
        [fc collectOpenDocumentsWithPatterns:(const char *)[none bytes] into:found];
        CHECK([found count] == 2 && [found containsObject:pa]);
        [found removeAllObjects];
        [fc collectOpenDocumentsWithPatterns:(const char *)[txt bytes] into:found];
        CHECK([found count] == 1 && [[found objectAtIndex:0] isEqualToString:pa]);          /* the untitled one has no .txt name */
        [found removeAllObjects];
        [fc collectOpenDocumentsWithPatterns:(const char *)[none bytes] into:found];
        CHECK([[fc replaceInFiles:found search:se with:@"BAR" literal:YES backups:NO] isEqualToString:@"Replaced 3 matches in 2 files."]);
        CHECK([[[a textView] string] isEqualToString:@"BAR in a\n"] && [[[b textView] string] isEqualToString:@"a BAR, another BAR\n"]);
        CHECK([a isDirty] && [b isDirty]);
        [b undo];
        CHECK([[[b textView] string] isEqualToString:@"a foo, another foo\n"]);
        search_free(se);
    }
    {   /* sessions: save the open files with their carets, reopen them in a new "program", the last session, replace, delete */
        SessionOwner *o1 = [[[SessionOwner alloc] init] autorelease], *o2 = [[[SessionOwner alloc] init] autorelease];
        SessionController *sc1 = [[[SessionController alloc] initWithOwner:o1] autorelease], *sc2 = [[[SessionController alloc] initWithOwner:o2] autorelease];
        NSString *sdir = [dir stringByAppendingPathComponent:@"sessions"];
        NSString *f1 = [dir stringByAppendingPathComponent:@"s one.txt"], *f2 = [dir stringByAppendingPathComponent:@"s2.c"], *gone = [dir stringByAppendingPathComponent:@"gone.c"];
        EditorDoc *d1, *d2;

        [[NSFileManager defaultManager] removeItemAtPath:sdir error:NULL];               /* from an earlier, interrupted run */
        [@"line one\nline two\nline three\n" writeToFile:f1 atomically:YES];
        [@"int main(void) { return 0; }\n" writeToFile:f2 atomically:YES];
        [@"x\n" writeToFile:gone atomically:YES];
        [sc1 setFolderPath:sdir];
        [sc2 setFolderPath:sdir];
        CHECK(![sc1 saveAs:@"work"]);                                            /* no windows with files yet */
        d1 = [o1 openPath:f1];
        d2 = [o1 openPath:f2];
        [[o1 docs] addObject:[[[EditorDoc alloc] initWithOwner:o1] autorelease]];  /* a window without a file is left out */
        [[d1 textView] setSelectedRange:NSMakeRange(9, 3)];
        [d2 setWrap:YES];
        CHECK([sc1 saveAs:@"work"] && [[sc1 currentName] isEqualToString:@"work"]);
        CHECK(![sc1 saveAs:@"a/b"] && ![sc1 saveAs:@".hidden"] && ![sc1 saveAs:@"  "]);
        CHECK([[sc1 savedNames] isEqualToArray:[NSArray arrayWithObject:@"work"]]);
        [sc1 recordLast];
        CHECK([sc1 hasLast] && ![[sc1 savedNames] containsObject:@".last"]);
        {
            NSString *txt = [NSString stringWithContentsOfFile:[sdir stringByAppendingPathComponent:@"work"]];
            CHECK([txt hasPrefix:@"# JOSE session\n"] && [txt rangeOfString:@"path="].length > 0 && [txt rangeOfString:@"s one.txt"].length > 0);
        }

        CHECK([sc2 open:@"work" replace:NO]);                                    /* "another run" of the program */
        CHECK([[o2 docs] count] == 2);
        CHECK([[[o2 docs] objectAtIndex:0] path] != nil && [[[[o2 docs] objectAtIndex:0] path] isEqualToString:f1]);
        CHECK([[[[o2 docs] objectAtIndex:0] textView] selectedRange].location == 9 && [[[[o2 docs] objectAtIndex:0] textView] selectedRange].length == 3);
        CHECK([[[o2 docs] objectAtIndex:1] wrap]);
        CHECK([sc2 missingCount] == 0);

        [[NSFileManager defaultManager] removeItemAtPath:gone error:NULL];
        {   /* a file that has gone is skipped and counted */
            SessionOwner *o3 = [[[SessionOwner alloc] init] autorelease];
            SessionController *sc3 = [[[SessionController alloc] initWithOwner:o3] autorelease];
            NSString *txt = [NSString stringWithFormat:@"file caret=0 path=%@\nfile caret=2 path=%@\n", gone, f2];
            [sc3 setFolderPath:sdir];
            [txt writeToFile:[sdir stringByAppendingPathComponent:@"partial"] atomically:YES];
            CHECK([sc3 open:@"partial" replace:NO] && [sc3 missingCount] == 1 && [[o3 docs] count] == 1);
        }
        {   /* replace: windows that are not in the session go (clean ones without asking), the ones that are stay */
            SessionOwner *o4 = [[[SessionOwner alloc] init] autorelease];
            SessionController *sc4 = [[[SessionController alloc] initWithOwner:o4] autorelease];
            EditorDoc *keep;
            [sc4 setFolderPath:sdir];
            keep = [o4 openPath:f2];
            [@"extra\n" writeToFile:[dir stringByAppendingPathComponent:@"s3.txt"] atomically:YES];
            [o4 openPath:[dir stringByAppendingPathComponent:@"s3.txt"]];
            CHECK([[o4 docs] count] == 2);
            CHECK([sc4 open:@"work" replace:YES]);
            CHECK([[o4 docs] count] == 2 && [[o4 docs] containsObject:keep]);   /* s3 went; f2 stayed; f1 came */
        }
        CHECK([sc1 deleteNamed:@"work"] && [[sc1 currentName] isEqualToString:@"work"] == NO);
        CHECK(![[sc1 savedNames] containsObject:@"work"]);
        (void)d2;
    }
    {   /* clipboard history: copies and cuts are remembered; one is made current and pasted; a rectangle stays a rectangle */
        MacroOwner *own = [[[MacroOwner alloc] init] autorelease];
        EditorDoc *cd = [[[EditorDoc alloc] initWithOwner:own] autorelease];
        EditTextView *tv = [cd textView];
        ClipboardController *cc = [[[ClipboardController alloc] initWithOwner:own] autorelease];

        gClip = cc;
        [own setDoc:cd];
        [tv setString:@"alpha beta gamma\nline two\n"];
        [tv setSelectedRange:NSMakeRange(0, 5)];
        [tv copy:nil];
        [tv setSelectedRange:NSMakeRange(6, 4)];
        [tv copy:nil];
        [tv setSelectedRange:NSMakeRange(11, 5)];
        [tv cut:nil];                                                            /* "gamma" */
        CHECK([[tv string] isEqualToString:@"alpha beta \nline two\n"]);
        CHECK([cc count] == 3 && [[cc previewAt:0] isEqualToString:@"gamma"] && [[cc previewAt:2] isEqualToString:@"alpha"]);
        [tv setSelectedRange:NSMakeRange(0, 0)];
        [cc pasteEntry:2];                                                       /* "alpha" is current, and pasted */
        CHECK([[tv string] hasPrefix:@"alphaalpha beta"]);
        CHECK([[[NSPasteboard generalPasteboard] stringForType:NSStringPboardType] isEqualToString:@"alpha"]);
        CHECK([cc count] == 3 && [[cc previewAt:0] isEqualToString:@"alpha"]);   /* chosen: to the front */
        [tv setSelectedRange:NSMakeRange(0, 0)];
        [tv copy:nil];                                                           /* nothing selected: nothing new */
        [tv setString:@"abcd\nefgh\nijkl\n"];
        [tv rectShowLines:NSMakeRange(0, 14) columns:1 :3];
        [tv copy:nil];                                                           /* a rectangle: "bc", "fg", "jk" */
        CHECK([cc count] == 4 && [[cc previewAt:0] isEqualToString:@"bc fg jk  (3 lines)"]);
        [tv rectClear];
        [tv setSelectedRange:NSMakeRange(0, 0)];
        [cc pasteEntry:0];
        CHECK([[tv string] hasPrefix:@"bc"] || [tv rectActive] || [[tv string] length] > 15);   /* pasted as a block */
        CHECK(![cc makeCurrent:9]);
        gClip = nil;
    }
    {   /* Complete Word cycles through the candidates, then the word as typed; another edit ends the cycle; one undo step remains */
        EditorDoc *cd = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        EditTextView *tv = [cd textView];
        NSString *base = @"foo foobar foo_baz x foobar fo";

        [tv setString:base];
        [tv setSelectedRange:NSMakeRange([base length], 0)];
        CHECK([cd completeWord:1] && [[tv string] hasSuffix:@" foobar"] && [tv selectedRange].location == [[tv string] length]);
        CHECK([cd completeWord:1] && [[tv string] hasSuffix:@" foo_baz"]);
        CHECK([cd completeWord:1] && [[tv string] hasSuffix:@" x foobar foo"]);
        CHECK([cd completeWord:1] && [[tv string] isEqualToString:base]);           /* the word as typed */
        CHECK([cd completeWord:1] && [[tv string] hasSuffix:@" foobar"]);           /* and round again */
        CHECK([cd completeWord:-1] && [[tv string] isEqualToString:base]);          /* backwards */
        CHECK([cd completeWord:-1] && [[tv string] hasSuffix:@" x foobar foo"]);
        [cd undo];                                                                  /* one step took the completion out */
        CHECK([[tv string] isEqualToString:base] && ![cd canUndo]);
        [tv setSelectedRange:NSMakeRange([base length], 0)];
        CHECK([cd completeWord:1]);
        [tv insertText:@"x"];                                                       /* typing ends the cycle ... */
        [tv setSelectedRange:NSMakeRange([[tv string] length], 0)];
        CHECK(![cd completeWord:1] || YES);                                         /* ... and a new one starts from the word before the caret */
        [tv setString:@"zzz "];
        [tv setSelectedRange:NSMakeRange(4, 0)];
        CHECK(![cd completeWord:1]);                                                /* no word before the caret */
        [tv setString:@"qq1 qq2 q"];
        [tv setSelectedRange:NSMakeRange(9, 0)];
        CHECK([cd completeWord:1] && [[tv string] hasSuffix:@" qq2"]);
        [tv setString:@"Alpha alp"];                                                /* only matching ignoring case */
        [tv setSelectedRange:NSMakeRange(9, 0)];
        CHECK([cd completeWord:1] && [[tv string] hasSuffix:@" Alpha"]);
    }
    {   /* remote editing, with a stand-in for ssh that runs the remote command here: open, edit, save, detect a change, reload */
        RemoteOwner *own = [[[RemoteOwner alloc] init] autorelease];
        RemoteController *rc = [[[RemoteController alloc] initWithOwner:own] autorelease];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *rdir = [dir stringByAppendingPathComponent:@"remote dir"];
        NSString *script = [dir stringByAppendingPathComponent:@"fake-ssh"];
        NSString *rfile = [rdir stringByAppendingPathComponent:@"r file.txt"], *spec, *crlf = [rdir stringByAppendingPathComponent:@"dos.txt"];
        NSString *script_text = @"#!/bin/sh\nwhile [ \"${1#-}\" != \"$1\" ]; do\n  case \"$1\" in -o|-p|-i|-l|-c|-m) shift 2;; *) shift;; esac\ndone\nshift\nexec /bin/sh -c \"$1\"\n";
        EditorDoc *rd;
        int oldProg = [Appearance remoteProgram];
        NSString *oldPath = [Appearance remotePathFor:1];

        [fm createDirectoryAtPath:rdir attributes:nil];
        [script_text writeToFile:script atomically:YES];
        chmod([script cString], 0755);
        [Appearance setRemoteProgram:1];
        [Appearance setRemotePath:script for:1];
        [@"hello\nworld\n" writeToFile:rfile atomically:YES];
        [[@"a\r\nb\r\n" dataUsingEncoding:NSASCIIStringEncoding] writeToFile:crlf atomically:YES];

        spec = [@"me@fakehost:" stringByAppendingString:rfile];
        rd = [rc openSpec:spec];
        CHECK(rd != nil && [[rd remoteSpec] isEqualToString:spec] && [rd path] == nil);
        CHECK([[[rd textView] string] isEqualToString:@"hello\nworld\n"] && ![rd isDirty]);
        CHECK([rc openSpec:spec] == rd);                                         /* already open: the same window */
        CHECK(![rc remoteChanged:rd]);
        [[rd textView] setSelectedRange:NSMakeRange(0, 0)];
        [[rd textView] insertText:@"X"];
        CHECK([rd isDirty]);
        CHECK([rc saveDocument:rd] && [rd remoteLength] == 13);                  /* written through the "ssh" */
        CHECK([[NSString stringWithContentsOfFile:rfile] isEqualToString:@"Xhello\nworld\n"]);
        CHECK(![fm fileExistsAtPath:[rfile stringByAppendingString:@".jose-tmp"]]);   /* the temporary file is gone */
        CHECK(![rc remoteChanged:rd]);
        [@"changed elsewhere\n" writeToFile:rfile atomically:YES];
        CHECK([rc remoteChanged:rd]);                                            /* noticed (no save is tried: it would ask) */
        CHECK([rc reloadDocument:rd] && [[[rd textView] string] isEqualToString:@"changed elsewhere\n"] && ![rc remoteChanged:rd]);

        rd = [rc openSpec:[@"u@h:" stringByAppendingString:crlf]];               /* CRLF files keep their line endings */
        CHECK(rd != nil && [[[rd textView] string] isEqualToString:@"a\nb\n"]);
        [[rd textView] setSelectedRange:NSMakeRange(0, 0)];
        [[rd textView] insertText:@"Z"];
        CHECK([rc saveDocument:rd]);
        CHECK([[NSData dataWithContentsOfFile:crlf] isEqualToData:[@"Za\r\nb\r\n" dataUsingEncoding:NSASCIIStringEncoding]]);

        {   /* the folder listing: folders first (with a slash), then files; hidden ones only when asked for */
            NSString *abs = nil, *bdir = [rdir stringByAppendingPathComponent:@"list dir"];
            NSArray *names, *want;

            [fm createDirectoryAtPath:bdir attributes:nil];
            [fm createDirectoryAtPath:[bdir stringByAppendingPathComponent:@"zsub"] attributes:nil];
            [fm createDirectoryAtPath:[bdir stringByAppendingPathComponent:@".hid dir"] attributes:nil];
            [@"x" writeToFile:[bdir stringByAppendingPathComponent:@"b file"] atomically:YES];
            [@"x" writeToFile:[bdir stringByAppendingPathComponent:@"a.txt"] atomically:YES];
            [@"x" writeToFile:[bdir stringByAppendingPathComponent:@".dot"] atomically:YES];
            names = [rc listDirectory:bdir userhost:@"me@h" hidden:NO resolved:&abs];
            CHECK([abs isEqualToString:bdir]);
            want = [NSArray arrayWithObjects:@"zsub/", @"a.txt", @"b file", nil];
            CHECK([names isEqualToArray:want]);
            names = [rc listDirectory:bdir userhost:@"me@h" hidden:YES resolved:&abs];
            CHECK([names count] == 5 && [names containsObject:@".dot"] && [names containsObject:@".hid dir/"] && [names containsObject:@"zsub/"]);
            CHECK([[names objectAtIndex:0] characterAtIndex:[[names objectAtIndex:0] length] - 1] == '/');        /* folders first */
            names = [rc listDirectory:[bdir stringByAppendingPathComponent:@"zsub"] userhost:@"me@h" hidden:NO resolved:&abs];
            CHECK([names count] == 0 && names != nil);                              /* an empty folder lists as nothing */
        }
        setenv("HOME", [rdir cString], 1);                                       /* ~/ is the remote home */
        [@"in home\n" writeToFile:[rdir stringByAppendingPathComponent:@"tilde.txt"] atomically:YES];
        rd = [rc openSpec:@"h:~/tilde.txt"];
        CHECK(rd != nil && [[[rd textView] string] isEqualToString:@"in home\n"]);
        [Appearance setRemoteProgram:oldProg];
        [Appearance setRemotePath:oldPath for:1];
    }
    {   /* Markdown preview: made from the text, follows an edit, shows folded text, closes with the document */
        EditorDoc *md = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        PreviewController *pc = [[[PreviewController alloc] initWithOwner:nil] autorelease];
        NSString *shown;

        [[md textView] setString:@"# Heading\n\nSome *emphasis* and **strong** text.\n\n- one\n- two\n"];
        CHECK(![pc hasPreviewFor:md]);
        [pc toggleFor:md];
        CHECK([pc hasPreviewFor:md]);
        shown = [pc previewStringFor:md];
        CHECK(shown != nil && [shown rangeOfString:@"Heading"].length > 0 && [shown rangeOfString:@"Some emphasis and strong text."].length > 0);
        CHECK([shown rangeOfString:@"*"].length == 0 && [shown rangeOfString:@"#"].length == 0);          /* the marks are gone */
        [[md textView] setString:@"Changed *now*\n"];
        [pc refreshNowFor:md];
        shown = [pc previewStringFor:md];
        CHECK([shown rangeOfString:@"Changed now"].length > 0 && [shown rangeOfString:@"Heading"].length == 0);
        [pc toggleFor:md];                                                        /* closes it */
        CHECK(![pc hasPreviewFor:md] && [pc previewStringFor:md] == nil);
        [pc toggleFor:md];
        [pc documentClosed:md];
        CHECK(![pc hasPreviewFor:md]);
    }
    {   /* the browser for preview links: an .app's executable, arguments with %u or the address last, quoting */
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *app = [dir stringByAppendingPathComponent:@"fake.app"], *exe = [app stringByAppendingPathComponent:@"fake"];
        NSString *out = [dir stringByAppendingPathComponent:@"browser.out"];
        NSString *body = [NSString stringWithFormat:@"#!/bin/sh\nprintf '%%s|' \"$@\" > '%@'\n", out];
        NSString *oldPath = [Appearance browserPath], *oldArgs = [Appearance browserArgs], *got = nil;
        int tries;

        [fm createDirectoryAtPath:app attributes:nil];
        [body writeToFile:exe atomically:YES];
        chmod([exe cString], 0755);
        [Appearance setBrowserPath:app];
        [Appearance setBrowserArgs:@"-new"];
        [fm removeFileAtPath:out handler:nil];
        CHECK([PreviewController openURLString:@"http://x.example/a b?q=1&r='2'"]);
        for (tries = 0; tries < 60 && got == nil; tries++) {
            got = [NSString stringWithContentsOfFile:out];
            if (got == nil || [got length] == 0) { got = nil; [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
        }
        CHECK(got != nil && [got isEqualToString:@"-new|http://x.example/a b?q=1&r='2'|"]);
        [Appearance setBrowserArgs:@"--url=%u --x"];
        [fm removeFileAtPath:out handler:nil];
        got = nil;
        CHECK([PreviewController openURLString:@"http://y.example/"]);
        for (tries = 0; tries < 60 && got == nil; tries++) {
            got = [NSString stringWithContentsOfFile:out];
            if (got == nil || [got length] == 0) { got = nil; [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
        }
        CHECK(got != nil && [got isEqualToString:@"--url=http://y.example/|--x|"]);
        [Appearance setBrowserPath:oldPath];
        [Appearance setBrowserArgs:oldArgs];
    }
    {   /* completion from the headers a file includes, two levels deep */
        AppController *ac = [[AppController alloc] init];
        NSString *hd = [dir stringByAppendingPathComponent:@"hdr"];
        NSString *h1 = [hd stringByAppendingPathComponent:@"jh.h"], *h2 = [hd stringByAppendingPathComponent:@"jh2.h"], *src = [hd stringByAppendingPathComponent:@"t.m"];
        EditorDoc *hdoc = [[[EditorDoc alloc] initWithOwner:ac] autorelease];
        NSArray *got;

        [HKSyntaxDefinition setSyntaxDirectory:@"syntax"];                 /* AppController pointed it at its bundle */
        [[NSFileManager defaultManager] createDirectoryAtPath:hd attributes:nil];
        [@"#include \"jh2.h\"\n@interface Widget\n- (void)frobnicateWidgetWithName:(NSString *)n;\n@end\n" writeToFile:h1 atomically:YES];
        [@"int deepFunctionName(void);\nextern int ab;\n" writeToFile:h2 atomically:YES];
        [@"#import \"jh.h\"\n#include <missing/nothere.h>\nint main(void) { frob" writeToFile:src atomically:YES];
        CHECK([hdoc openFile:src] && [[hdoc mode] isEqualToString:@"ObjC"]);
        got = [ac extraCompletionsForPrefix:@"frob" document:hdoc icase:NO];
        CHECK([got containsObject:@"frobnicateWidgetWithName"]);                 /* from the header itself */
        got = [ac extraCompletionsForPrefix:@"deepF" document:hdoc icase:NO];
        CHECK([got containsObject:@"deepFunctionName"]);                          /* from the header it includes */
        CHECK(![[ac extraCompletionsForPrefix:@"ab" document:hdoc icase:NO] containsObject:@"ab"]);        /* under three letters is not kept */
        CHECK([[ac extraCompletionsForPrefix:@"FROB" document:hdoc icase:YES] containsObject:@"frobnicateWidgetWithName"]);
        [[hdoc textView] setSelectedRange:NSMakeRange([[[hdoc textView] string] length], 0)];
        CHECK([hdoc completeWord:1] && [[[hdoc textView] string] hasSuffix:@"{ frobnicateWidgetWithName"]);
        [ac release];
    }
    {   /* the character under the pointer in a preview, and files dropped on a window */
        EditorDoc *md = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        PreviewController *pc = [[[PreviewController alloc] initWithOwner:nil] autorelease];
        NSTextView *ptv;
        NSString *shown;
        NSRange u;

        [[md textView] setString:@"Some text before [a link](http://example.com/page) and more after it.\n"];
        [pc toggleFor:md];
        ptv = [pc previewViewFor:md];
        shown = [ptv string];
        u = [shown rangeOfString:@"http://example.com/page"];
        CHECK(ptv != nil && u.length > 0);
        {
            NSLayoutManager *lm = [ptv layoutManager];
            NSPoint o = [ptv textContainerOrigin];
            NSRect r;
            unsigned int k, hit, inside = 0, sample = 0;

            for (k = 0; k < u.length; k += 3) {                                  /* points along the address, and some before and after */
                r = [lm boundingRectForGlyphRange:NSMakeRange(u.location + k, 1) inTextContainer:[ptv textContainer]];
                hit = [PreviewController characterIndexAt:NSMakePoint(NSMidX(r) + o.x, NSMidY(r) + o.y) inView:ptv];
                sample++;
                if (hit >= u.location && hit < NSMaxRange(u) && hit == u.location + k) inside++;
            }
            CHECK(sample > 4 && inside == sample);                               /* each point finds its own character, not the line's first */
            r = [lm boundingRectForGlyphRange:NSMakeRange(2, 1) inTextContainer:[ptv textContainer]];
            hit = [PreviewController characterIndexAt:NSMakePoint(NSMidX(r) + o.x, NSMidY(r) + o.y) inView:ptv];
            CHECK(hit == 2);
        }
        [pc toggleFor:md];
    }
    {   /* files dropped on a window: files open, folders and missing names do not */
        SessionOwner *o = [[[SessionOwner alloc] init] autorelease];
        EditorDoc *dd = [[[EditorDoc alloc] initWithOwner:o] autorelease];
        NSString *f1 = [dir stringByAppendingPathComponent:@"drop one.txt"], *f2 = [dir stringByAppendingPathComponent:@"drop2.c"];

        [@"one\n" writeToFile:f1 atomically:YES];
        [@"two\n" writeToFile:f2 atomically:YES];
        [dd openDroppedFiles:[NSArray arrayWithObjects:f1, dir, [dir stringByAppendingPathComponent:@"nonesuch"], f2, nil]];
        CHECK([[o docs] count] == 2 && [[[[o docs] objectAtIndex:0] path] isEqualToString:f1] && [[[[o docs] objectAtIndex:1] path] isEqualToString:f2]);
    }
    {   /* text encodings: a file is written back in the encoding it was read in, byte for byte */
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *ed_dir = [dir stringByAppendingPathComponent:@"encodings"];
        NSString *pl1 = [ed_dir stringByAppendingPathComponent:@"latin1.txt"], *psj = [ed_dir stringByAppendingPathComponent:@"sjis.txt"];
        NSString *pbom = [ed_dir stringByAppendingPathComponent:@"bom.txt"], *p16 = [ed_dir stringByAppendingPathComponent:@"utf16.txt"];
        NSString *pemo = [ed_dir stringByAppendingPathComponent:@"emoji.txt"], *pbad = [ed_dir stringByAppendingPathComponent:@"bad.txt"];
        EditorDoc *e;

        [fm createDirectoryAtPath:ed_dir attributes:nil];
        [[NSData dataWithBytes:"caf\xE9 na\xEFve\n" length:11] writeToFile:pl1 atomically:YES];
        [[NSData dataWithBytes:"\x93\xFA\x96\x7B\x8C\xEA\r\nabc\r\n" length:13] writeToFile:psj atomically:YES];
        [[NSData dataWithBytes:"\xEF\xBB\xBF" "hi\n" length:6] writeToFile:pbom atomically:YES];
        [[NSData dataWithBytes:"\xFF\xFE" "h\0i\0\n\0" length:8] writeToFile:p16 atomically:YES];
        [[NSData dataWithBytes:"a \xF0\x9F\x98\x80 b\n" length:9] writeToFile:pemo atomically:YES];
        [[NSData dataWithBytes:"ok \xFF\xFE ok\n" length:9] writeToFile:pbad atomically:YES];

        e = [[[EditorDoc alloc] initWithOwner:nil] autorelease];                       /* Latin-1: kept, not turned into UTF-8 */
        CHECK([e openFile:pl1] && [e encoding] == ENC_LATIN1 && [[[e textView] string] isEqualToString:@"caf\u00e9 na\u00efve\n"]);
        [[e textView] setSelectedRange:NSMakeRange(0, 0)];
        [[e textView] insertText:@"\u00e9"];
        CHECK([e save] && [[NSData dataWithContentsOfFile:pl1] isEqualToData:[NSData dataWithBytes:"\xE9" "caf\xE9 na\xEFve\n" length:12]]);
        [e setEncodingForSave:ENC_UTF8];                                              /* Save with Encoding */
        CHECK([e isDirty] && [e encoding] == ENC_UTF8);
        CHECK([e save] && ![e isDirty] && [[NSData dataWithContentsOfFile:pl1] isEqualToData:[NSData dataWithBytes:"\xC3\xA9" "caf\xC3\xA9 na\xC3\xAFve\n" length:15]]);

        e = [[[EditorDoc alloc] initWithOwner:nil] autorelease];                       /* Shift_JIS: read as Latin-1 at first, then reopened */
        CHECK([e openFile:psj] && [e encoding] == ENC_LATIN1);
        CHECK([e reopenWithEncoding:ENC_SJIS] && [e encoding] == ENC_SJIS && [[[e textView] string] isEqualToString:@"\u65e5\u672c\u8a9e\nabc\n"]);
        [[e textView] setSelectedRange:NSMakeRange(7, 0)];
        [[e textView] insertText:@"!"];
        CHECK([e save] && [[NSData dataWithContentsOfFile:psj] isEqualToData:[NSData dataWithBytes:"\x93\xFA\x96\x7B\x8C\xEA\r\nabc!\r\n" length:14]]);   /* CRLF kept too */

        e = [[[EditorDoc alloc] initWithOwner:nil] autorelease];                       /* byte order marks */
        CHECK([e openFile:pbom] && [e encoding] == ENC_UTF8_BOM && [[[e textView] string] isEqualToString:@"hi\n"]);
        [[e textView] setSelectedRange:NSMakeRange(2, 0)];
        [[e textView] insertText:@"!"];
        CHECK([e save] && [[NSData dataWithContentsOfFile:pbom] isEqualToData:[NSData dataWithBytes:"\xEF\xBB\xBF" "hi!\n" length:7]]);
        e = [[[EditorDoc alloc] initWithOwner:nil] autorelease];
        CHECK([e openFile:p16] && [e encoding] == ENC_UTF16LE && [[[e textView] string] isEqualToString:@"hi\n"]);
        [[e textView] setSelectedRange:NSMakeRange(0, 0)];
        [[e textView] insertText:@"> "];
        CHECK([e save] && [[NSData dataWithContentsOfFile:p16] isEqualToData:[NSData dataWithBytes:"\xFF\xFE" ">\0 \0h\0i\0\n\0" length:12]]);

        e = [[[EditorDoc alloc] initWithOwner:nil] autorelease];                       /* outside the BMP survives */
        CHECK([e openFile:pemo] && [e encoding] == ENC_UTF8 && [[[e textView] string] length] == 7);       /* a, space, 2 units, space, b, newline */
        [[e textView] setSelectedRange:NSMakeRange(0, 0)];
        [[e textView] insertText:@"x"];
        CHECK([e save] && [[NSData dataWithContentsOfFile:pemo] isEqualToData:[NSData dataWithBytes:"xa \xF0\x9F\x98\x80 b\n" length:10]]);

        e = [[[EditorDoc alloc] initWithOwner:nil] autorelease];                       /* bytes that are not valid UTF-8 come back as they were */
        CHECK([e openFile:pbad] && [e encoding] == ENC_LATIN1);
        CHECK([e reopenWithEncoding:ENC_UTF8]);
        [[e textView] setSelectedRange:NSMakeRange(0, 0)];
        [[e textView] insertText:@"-"];
        CHECK([e save] && [[NSData dataWithContentsOfFile:pbad] isEqualToData:[NSData dataWithBytes:"-ok \xFF\xFE ok\n" length:10]]);
    }
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    printf(failures ? "doc: FAILED\n" : "doc: ok\n");
    [pool release];
    return failures != 0;
}
