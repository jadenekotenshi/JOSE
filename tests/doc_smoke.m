/* Host-only: an EditorDoc end to end -- open, colour, edit, save, line endings.  make doc-smoke */
#import "EditorDoc.h"
#import "HKSyntaxDefinition.h"
#include <stdio.h>

static int failures = 0;
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

    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    printf(failures ? "doc: FAILED\n" : "doc: ok\n");
    [pool release];
    return failures != 0;
}
