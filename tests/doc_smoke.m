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
