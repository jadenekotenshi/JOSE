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
    {   /* nested contexts: <header> and a comment inside a preprocessor line, ${var} inside a shell string */
        NSString *cp = @"#include <stdio.h> /* c */\nint x;\n#define A 1\n";
        NSTextStorage *cts = [[[NSTextStorage alloc] initWithString:cp] autorelease];
        HKSyntaxHighlighter *ch = [[HKSyntaxHighlighter alloc] initWithHighlighterType:@"C" textStorage:cts
                                                                      defaultTextColor:[NSColor blackColor]];
        NSColor *dir, *hdr, *cmt, *after;
        [ch highlightRange:NSMakeRange(0, [cts length])];
        dir = colourAt(cts, 1);
        hdr = colourAt(cts, [cp rangeOfString:@"stdio"].location);
        cmt = colourAt(cts, [cp rangeOfString:@"c */"].location);
        after = colourAt(cts, [cp rangeOfString:@"int"].location);
        CHECK(dir != nil && hdr != nil && cmt != nil);
        CHECK(![dir isEqual:hdr]);
        CHECK(![hdr isEqual:cmt]);
        CHECK(![dir isEqual:after]);
        CHECK(![hdr isEqual:after]);
        CHECK([dir isEqual:colourAt(cts, [cp rangeOfString:@"define"].location + 1)]);
        CHECK([dir isEqual:colourAt(cts, [cp rangeOfString:@"A 1"].location)]);        /* the directive resumes after the child */
        printf("nested C: directive=%s header=%s comment=%s\n", [[dir description] cString], [[hdr description] cString],
               [[cmt description] cString]);
        {
            NSString *sh = @"echo \"a ${HOME} b $(pwd) c\"\nls\n";
            NSTextStorage *sts = [[[NSTextStorage alloc] initWithString:sh] autorelease];
            HKSyntaxHighlighter *sh2 = [[HKSyntaxHighlighter alloc] initWithHighlighterType:@"Shell" textStorage:sts
                                                                           defaultTextColor:[NSColor blackColor]];
            NSColor *plainStr, *var, *cmd, *ls;
            [sh2 highlightRange:NSMakeRange(0, [sts length])];
            plainStr = colourAt(sts, [sh rangeOfString:@"a "].location);
            var = colourAt(sts, [sh rangeOfString:@"HOME"].location);
            cmd = colourAt(sts, [sh rangeOfString:@"pwd"].location);
            ls = colourAt(sts, [sh rangeOfString:@"ls"].location);
            CHECK(![plainStr isEqual:var]);
            CHECK(![plainStr isEqual:cmd]);
            CHECK([plainStr isEqual:colourAt(sts, [sh rangeOfString:@" b "].location + 1)]);   /* back in the string after } */
            CHECK([plainStr isEqual:colourAt(sts, [sh rangeOfString:@" c"].location + 1)]);    /* ... and after ) */
            CHECK(![plainStr isEqual:ls]);
        }
        /* an unterminated child is closed by the end of the line around it */
        {
            NSString *u = @"#include <std\nint y;\n";
            NSTextStorage *uts = [[[NSTextStorage alloc] initWithString:u] autorelease];
            HKSyntaxHighlighter *uh = [[HKSyntaxHighlighter alloc] initWithHighlighterType:@"C" textStorage:uts
                                                                          defaultTextColor:[NSColor blackColor]];
            [uh highlightRange:NSMakeRange(0, [uts length])];
            CHECK(![colourAt(uts, [u rangeOfString:@"std"].location) isEqual:colourAt(uts, [u rangeOfString:@"int"].location)]);
            CHECK(![colourAt(uts, [u rangeOfString:@"y;"].location) isEqual:colourAt(uts, 1)]);
        }
        /* editing inside the nested context re-highlights it consistently */
        [cts replaceCharactersInRange:NSMakeRange([cp rangeOfString:@"stdio"].location, 5) withString:@"stdlib"];
        [ch highlightRange:NSMakeRange(0, [cts length])];
        CHECK([colourAt(cts, [[cts string] rangeOfString:@"stdlib"].location) isEqual:hdr]);
        CHECK(![colourAt(cts, [[cts string] rangeOfString:@"int"].location) isEqual:hdr]);
    }
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
    {   /* shell, csh and perl each colour a keyword, a comment and a string */
        static const char *const modes[] = { "Shell", "Csh", "Perl" };
        static NSString *const texts[] = { @"if true; then\n  # note\n  echo \"hi $X\"\nfi\n",
                                           @"if ($x) then\n  # note\n  echo \"hi $x\"\nendif\n",
                                           @"my $x = 1;\n# note\nprint \"hi $x\";\n=pod\nmore\n=cut\n" };
        int mi;
        for (mi = 0; mi < 3; mi++) {
            NSTextStorage *mts = [[[NSTextStorage alloc] initWithString:texts[mi]] autorelease];
            HKSyntaxHighlighter *mh = [[HKSyntaxHighlighter alloc]
                initWithHighlighterType:[NSString stringWithCString:modes[mi]] textStorage:mts defaultTextColor:[NSColor blackColor]];
            NSColor *a, *b, *c;
            CHECK(mh != nil);
            [mh highlightRange:NSMakeRange(0, [mts length])];
            a = colourAt(mts, 0);
            b = colourAt(mts, [texts[mi] rangeOfString:@"note"].location);
            c = colourAt(mts, [texts[mi] rangeOfString:@"hi"].location);
            CHECK(a != nil && b != nil && c != nil);
            CHECK(![a isEqual:b] && ![b isEqual:c]);
            printf("%s ok\n", modes[mi]);
        }
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
