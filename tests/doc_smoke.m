/* Host-only: an EditorDoc end to end -- open, colour, edit, save, line endings.  make doc-smoke */
#import "EditorDoc.h"
#import "LineNumberView.h"
#import "HKSyntaxDefinition.h"
#include <stdio.h>

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

    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    printf(failures ? "doc: FAILED\n" : "doc: ok\n");
    [pool release];
    return failures != 0;
}
