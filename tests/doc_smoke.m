/* Host-only: an EditorDoc end to end -- open, colour, edit, save, line endings.  make doc-smoke */
#import "EditorDoc.h"
#import "LineNumberView.h"
#import "ShellController.h"
#import "HKSyntaxDefinition.h"
#include <stdio.h>

@interface ShellController (SmokeTest)
- (void)filter:(NSString *)command in:(EditorDoc *)doc;
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
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    printf(failures ? "doc: FAILED\n" : "doc: ok\n");
    [pool release];
    return failures != 0;
}
