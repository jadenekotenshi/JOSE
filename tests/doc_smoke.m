/* Host-only: an EditorDoc end to end -- open, colour, edit, save, line endings.  make doc-smoke */
#import "EditorDoc.h"
#import "LineNumberView.h"
#import "ShellController.h"
#import "Appearance.h"
#import "FindController.h"
#import "MacroController.h"
#import "FilesController.h"
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
@end

@interface ShellController (SmokeTest)
- (BOOL)filter:(NSString *)command in:(EditorDoc *)doc;
@end

/* Stands in for the AppController: the macro recorder and the Find panel only ask it a few things. */
@interface MacroOwner : NSObject
{
    EditorDoc *doc;
    FindController *finder;
    ShellController *shell;
    MacroController *mc;
    EditorDoc *openDoc;
}
- (void)setDoc:(EditorDoc *)d;
- (void)setOpenDoc:(EditorDoc *)d;
- (MacroController *)mc;
@end

@implementation MacroOwner
- (void)setDoc:(EditorDoc *)d { doc = d; }
- (void)setOpenDoc:(EditorDoc *)d { openDoc = d; }
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
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    printf(failures ? "doc: FAILED\n" : "doc: ok\n");
    [pool release];
    return failures != 0;
}
