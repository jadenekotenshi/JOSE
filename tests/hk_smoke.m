/* Host-only: does the vendored HighlighterKit colour C text, and how fast?  make hk-smoke */
#import "HKSyntaxHighlighter.h"
#import "HKSyntaxDefinition.h"
#include <stdio.h>
#include <sys/time.h>

static int failures = 0;
static double now(void) { struct timeval tv; gettimeofday(&tv, NULL); return tv.tv_sec + tv.tv_usec / 1e6; }
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSColor *colourAt(NSTextStorage *ts, unsigned int i)
{
    return [ts attribute:NSForegroundColorAttributeName atIndex:i effectiveRange:NULL];
}

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *text = @"int main(void)\n{\n    /* a comment */\n    char *s = \"text\";\n    return 0;\n}\n";
    NSTextStorage *ts = [[[NSTextStorage alloc] initWithString:text] autorelease];
    HKSyntaxHighlighter *hl;
    NSColor *plain, *kw, *cm, *str;
    NSMutableString *big;
    int i;
    double t0;

    [HKSyntaxDefinition setSyntaxDirectory:@"syntax"];
    hl = [[HKSyntaxHighlighter alloc] initWithHighlighterType:@"C" textStorage:ts defaultTextColor:[NSColor blackColor]];
    CHECK(hl != nil);
    [hl highlightRange:NSMakeRange(0, [ts length])];
    plain = colourAt(ts, [text rangeOfString:@"main"].location);
    kw = colourAt(ts, 0);                                   /* int */
    cm = colourAt(ts, [text rangeOfString:@"a comment"].location);
    str = colourAt(ts, [text rangeOfString:@"text\""].location);
    CHECK(kw != nil && cm != nil && str != nil);
    CHECK(![kw isEqual:cm]);
    CHECK(![cm isEqual:str]);
    CHECK(![kw isEqual:plain] || plain == nil);
    {   /* Python: keyword, comment, string and triple-quoted string get colours */
        NSString *py = @"def f(x):\n    # note\n    s = 'abc'\n    \"\"\"doc\n    more\"\"\"\n    return None\n";
        NSTextStorage *pts = [[[NSTextStorage alloc] initWithString:py] autorelease];
        HKSyntaxHighlighter *ph = [[HKSyntaxHighlighter alloc] initWithHighlighterType:@"Python" textStorage:pts
                                                                      defaultTextColor:[NSColor blackColor]];
        CHECK(ph != nil);
        [ph highlightRange:NSMakeRange(0, [pts length])];
        CHECK(colourAt(pts, 0) != nil);
        CHECK(colourAt(pts, [py rangeOfString:@"note"].location) != nil);
        CHECK(colourAt(pts, [py rangeOfString:@"abc"].location) != nil);
        CHECK(colourAt(pts, [py rangeOfString:@"more"].location) != nil);
        CHECK(![colourAt(pts, 0) isEqual:colourAt(pts, [py rangeOfString:@"note"].location)]);
        CHECK(![colourAt(pts, [py rangeOfString:@"more"].location) isEqual:colourAt(pts, [py rangeOfString:@"x"].location)]);
        printf("python def=%s note=%s more=%s\n", [[colourAt(pts, 0) description] cString],
               [[colourAt(pts, [py rangeOfString:@"note"].location) description] cString],
               [[colourAt(pts, [py rangeOfString:@"more"].location) description] cString]);
    }
    printf("int=%s comment=%s string=%s main=%s\n", [[kw description] cString], [[cm description] cString],
           [[str description] cString], [[plain description] cString]);

    big = [NSMutableString string];
    for (i = 0; i < 2000; i++) [big appendFormat:@"static int f%d(int a, char *b)\n{\n    /* number %d */\n    return a + %d; /* x */\n}\n\n", i, i, i];
    ts = [[[NSTextStorage alloc] initWithString:big] autorelease];
    hl = [[HKSyntaxHighlighter alloc] initWithHighlighterType:@"C" textStorage:ts defaultTextColor:[NSColor blackColor]];
    t0 = now();
    [hl highlightRange:NSMakeRange(0, [ts length])];
    printf("highlighted %lu bytes in %.0f ms\n", (unsigned long)[ts length], (now() - t0) * 1000.0);
    t0 = now();
    [hl highlightRange:NSMakeRange(1000, 2000)];
    printf("a screenful after that: %.1f ms\n", (now() - t0) * 1000.0);
    printf(failures ? "hk: FAILED\n" : "hk: ok\n");
    [pool release];
    return failures != 0;
}
