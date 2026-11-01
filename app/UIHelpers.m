#import "UIHelpers.h"
#include "enc.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>

const char *volatile ss_crumb = "(before the first step)";

void SSTraceV(NSString *path, const char *fmt, va_list ap)
{
    static NSTimeInterval first = 0.0;
    FILE *f = fopen([path cString], "r+");      /* "r+" never creates the file: tracing is opt-in */
    NSTimeInterval now;

    if (f == NULL) return;
    now = [NSDate timeIntervalSinceReferenceDate];
    if (first == 0.0) first = now;
    fseek(f, 0L, SEEK_END);
    fprintf(f, "[+%7.2fs] ", now - first);       /* seconds since the first line: a stall or a kill shows up as a gap */
    vfprintf(f, fmt, ap);
    fputc('\n', f);
    fclose(f);                                  /* closed every time so a crash keeps earlier lines */
}

void SSTrace(const char *fmt, ...)
{
    va_list ap;

    va_start(ap, fmt);
    SSTraceV([NSHomeDirectory() stringByAppendingPathComponent:@".JOSE.trace"], fmt, ap);
    va_end(ap);
}

NSTextField *ui_label(NSString *text, NSRect frame)
{
    NSTextField *l = [[NSTextField alloc] initWithFrame:frame];
    [l setStringValue:text];
    [l setEditable:NO];
    [l setSelectable:NO];
    [l setBezeled:NO];
    [l setBordered:NO];
    [l setDrawsBackground:NO];
    return [l autorelease];
}

NSTextField *ui_wrapping_label(NSString *text, NSRect frame, BOOL selectable)
{
    NSTextField *l = ui_label(text, frame);
    [[l cell] setWraps:YES];
    [l setSelectable:selectable];
    return l;
}

NSTextField *ui_field(NSRect frame)
{
    NSTextField *f = [[NSTextField alloc] initWithFrame:frame];
    [f setEditable:YES];
    [f setBezeled:YES];
    return [f autorelease];
}

/* A check box whose image is explicitly to the left of its title, on a row of its own. */
NSButton *ui_switch(NSString *title, NSRect frame)
{
    NSButton *b = [[NSButton alloc] initWithFrame:frame];
    [b setButtonType:NSSwitchButton];
    [b setTitle:title];
    [[b cell] setImagePosition:NSImageLeft];
    [b setAlignment:NSLeftTextAlignment];
    return [b autorelease];
}

NSButton *ui_button(NSString *title, NSRect frame, id target, SEL action)
{
    NSButton *b = [[NSButton alloc] initWithFrame:frame];
    [b setTitle:title];
    [b setTarget:target];
    [b setAction:action];
    return [b autorelease];
}

NSString *ui_trim(NSString *s)
{
    unsigned a = 0, b = [s length];
    while (a < b && ([s characterAtIndex:a] == ' ' || [s characterAtIndex:a] == '\t')) a++;
    while (b > a && ([s characterAtIndex:b - 1] == ' ' || [s characterAtIndex:b - 1] == '\t')) b--;
    return [s substringWithRange:NSMakeRange(a, b - a)];
}

/* UTF-8 to a string, with characters outside the BMP as surrogate pairs.  Bytes that are not valid UTF-8 are read as Latin-1 (these are
 * messages and names, not files: the editor reads files with core/enc, which keeps such bytes exactly). */
NSString *ui_string_from_utf8(const char *s)
{
    size_t n = 0, i;
    u16 *t = enc_utf8_to_utf16(s, strlen(s), &n);
    NSString *r;

    if (t == NULL) return @"";
    for (i = 0; i < n; i++) if (t[i] >= 0xDC80 && t[i] <= 0xDCFF) t[i] = (u16)(t[i] - 0xDC00);        /* an escaped bad byte: Latin-1 */
    r = [NSString stringWithCharacters:(const unichar *)t length:n];
    free(t);
    return r;
}

NSData *ui_utf8_cstring(NSString *s)
{
    size_t n = [s length], m = 0;
    u16 *t = (u16 *)malloc((n + 1) * sizeof(u16));
    char *u;
    NSMutableData *d;

    if (t == NULL) return [NSData dataWithBytes:"" length:1];
    if (n > 0) [s getCharacters:t];
    u = enc_utf16_to_utf8(t, n, &m);
    free(t);
    if (u == NULL) return [NSData dataWithBytes:"" length:1];
    d = [NSMutableData dataWithBytes:u length:m + 1];                  /* the NUL is part of it */
    free(u);
    return d;
}
