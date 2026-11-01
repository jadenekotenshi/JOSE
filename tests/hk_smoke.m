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
    {   /* Markdown: a heading, a quote and fenced code are coloured, the body text is not */
        NSString *mdsrc = @"# Title\n\nbody text\n\n```\ncode here\n```\n\n> quoted\n";
        NSTextStorage *mts = [[[NSTextStorage alloc] initWithString:mdsrc] autorelease];
        HKSyntaxHighlighter *mh = [[HKSyntaxHighlighter alloc] initWithHighlighterType:@"Markdown" textStorage:mts defaultTextColor:[NSColor blackColor]];

        CHECK(mh != nil);
        [mh highlightRange:NSMakeRange(0, [mts length])];
        CHECK(![colourAt(mts, [mdsrc rangeOfString:@"Title"].location) isEqual:colourAt(mts, [mdsrc rangeOfString:@"body"].location)]);
        CHECK(![colourAt(mts, [mdsrc rangeOfString:@"code here"].location) isEqual:colourAt(mts, [mdsrc rangeOfString:@"body"].location)]);
        CHECK(![colourAt(mts, [mdsrc rangeOfString:@"quoted"].location) isEqual:colourAt(mts, [mdsrc rangeOfString:@"body"].location)]);
        [mh detach];
        [mh release];
    }
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
    {   /* the newer modes each colour a keyword, a string and a comment differently, and the nested bits */
        static const struct { const char *mode; NSString *text; NSString *kw, *str, *cmt; } T[] = {
            { "JSON", @"{\"name\": \"x\", \"ok\": true}\n", @"true", @"x\"", nil },
            { "JavaScript", @"function f() { return \"s\"; } // note\n", @"function", @"s\"", @"note" },
            { "Ruby", @"def f\n  puts \"s\" # note\nend\n", @"def", @"s\"", @"note" },
            { "Zsh", @"autoload -U compinit\necho \"s\" # note\n", @"autoload", @"s\"", @"note" },
            { "BSDMakefile", @".include <bsd.prog.mk>\nFOO= \"s\" # note\n", @"include", @"s\"", @"note" },
            { "Imakefile", @"XCOMM note\nSRCS = a.c\n#define X \"s\"\n", @"SRCS", @"s\"", @"note" },
            { "PilcrowMacro", @"# note\ninsert \"s\"\n", @"insert", @"s\"", @"note" }
        };
        int ti;
        for (ti = 0; ti < 7; ti++) {
            NSTextStorage *mts = [[[NSTextStorage alloc] initWithString:T[ti].text] autorelease];
            HKSyntaxHighlighter *mh = [[HKSyntaxHighlighter alloc] initWithHighlighterType:[NSString stringWithCString:T[ti].mode] textStorage:mts
                                                                          defaultTextColor:[NSColor blackColor]];
            NSColor *kwc, *plainc;
            if (mh == nil) { printf("FAIL: no syntax for %s\n", T[ti].mode); failures++; continue; }
            [mh highlightRange:NSMakeRange(0, [mts length])];
            kwc = colourAt(mts, [T[ti].text rangeOfString:T[ti].kw].location);
            plainc = colourAt(mts, [T[ti].text length] - 1);
            if (kwc == nil) { printf("FAIL: %s: no colour on %s\n", T[ti].mode, [T[ti].kw cString]); failures++; }
            if (T[ti].str != nil) {
                NSColor *sc = colourAt(mts, [T[ti].text rangeOfString:T[ti].str].location);
                if (sc == nil || [sc isEqual:kwc]) { printf("FAIL: %s: the string is not coloured apart from the keyword\n", T[ti].mode); failures++; }
            }
            if (T[ti].cmt != nil) {
                NSColor *cc = colourAt(mts, [T[ti].text rangeOfString:T[ti].cmt].location);
                if (cc == nil || [cc isEqual:kwc]) { printf("FAIL: %s: the comment is not coloured apart from the keyword\n", T[ti].mode); failures++; }
            }
            (void)plainc;
        }
    }
    {   /* Ruby: #{...} in a string; JavaScript: ${...} in a template literal; Imake: <header> in a cpp line */
        NSString *rb = @"\"a #{b} c\"\n";
        NSTextStorage *rts = [[[NSTextStorage alloc] initWithString:rb] autorelease];
        HKSyntaxHighlighter *rh = [[HKSyntaxHighlighter alloc] initWithHighlighterType:@"Ruby" textStorage:rts defaultTextColor:[NSColor blackColor]];
        NSString *js = @"`a ${b} c`\n";
        NSTextStorage *jts = [[[NSTextStorage alloc] initWithString:js] autorelease];
        HKSyntaxHighlighter *jh = [[HKSyntaxHighlighter alloc] initWithHighlighterType:@"JavaScript" textStorage:jts defaultTextColor:[NSColor blackColor]];
        NSString *im = @"#include <X11/Xos.h>\nSRCS = a.c\n";
        NSTextStorage *its = [[[NSTextStorage alloc] initWithString:im] autorelease];
        HKSyntaxHighlighter *ih = [[HKSyntaxHighlighter alloc] initWithHighlighterType:@"Imakefile" textStorage:its defaultTextColor:[NSColor blackColor]];
        [rh highlightRange:NSMakeRange(0, [rts length])];
        [jh highlightRange:NSMakeRange(0, [jts length])];
        [ih highlightRange:NSMakeRange(0, [its length])];
        CHECK(![colourAt(rts, [rb rangeOfString:@"a #"].location) isEqual:colourAt(rts, [rb rangeOfString:@"b"].location)]);
        CHECK([colourAt(rts, [rb rangeOfString:@"a #"].location) isEqual:colourAt(rts, [rb rangeOfString:@" c"].location + 1)]);      /* back in the string */
        CHECK(![colourAt(jts, [js rangeOfString:@"a $"].location) isEqual:colourAt(jts, [js rangeOfString:@"b"].location)]);
        CHECK([colourAt(jts, [js rangeOfString:@"a $"].location) isEqual:colourAt(jts, [js rangeOfString:@" c"].location + 1)]);
        CHECK(![colourAt(its, 1) isEqual:colourAt(its, [im rangeOfString:@"X11"].location)]);
        CHECK(![colourAt(its, 1) isEqual:colourAt(its, [im rangeOfString:@"a.c"].location)]);
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
