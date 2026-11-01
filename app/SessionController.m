#import "SessionController.h"
#import "AppController.h"
#import "EditorDoc.h"
#import "UIHelpers.h"
#include "session.h"
#include <stdlib.h>
#include <string.h>

#define LAST_NAME @".last"

@interface SessionController (Private)
- (BOOL)writeSessionNamed:(NSString *)fileName;
- (BOOL)openSessionFile:(NSString *)fileName replace:(BOOL)replace;
- (BOOL)validName:(NSString *)name;
@end

static NSString *read_text(NSString *path)
{
    NSData *d = [NSData dataWithContentsOfFile:path];
    char *b;
    NSString *s;

    if (d == nil) return nil;
    b = (char *)malloc([d length] + 1);
    if (b == NULL) return nil;
    [d getBytes:b];
    b[[d length]] = '\0';
    s = ui_string_from_utf8(b);
    free(b);
    return s;
}

static BOOL write_text(NSString *text, NSString *path)
{
    NSData *enc = ui_utf8_cstring(text);

    return [[NSData dataWithBytes:[enc bytes] length:[enc length] - 1] writeToFile:path atomically:YES];
}

@implementation SessionController

- (id)initWithOwner:(id)anOwner
{
    self = [super init];
    if (self) {
        owner = anOwner;
        folder = [[NSHomeDirectory() stringByAppendingPathComponent:@".JOSE.sessions"] retain];
    }
    return self;
}

- (void)dealloc
{
    [folder release];
    [current release];
    [super dealloc];
}

- (NSString *)currentName { return current; }
- (void)setFolderPath:(NSString *)path { [folder release]; folder = [path copy]; }
- (void)setQuiet:(BOOL)flag { quiet = flag; }

- (BOOL)validName:(NSString *)name
{
    return [name length] > 0 && [name rangeOfString:@"/"].length == 0 && [name characterAtIndex:0] != '.';
}

- (NSArray *)savedNames
{
    NSArray *all = [[NSFileManager defaultManager] directoryContentsAtPath:folder];
    NSMutableArray *names = [NSMutableArray array];
    unsigned int i;

    for (i = 0; i < [all count]; i++) {
        NSString *n = [all objectAtIndex:i];
        if ([n length] > 0 && [n characterAtIndex:0] != '.') [names addObject:n];
    }
    return [names sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
}

/* The open windows that have files, in the order they were opened. */
- (BOOL)writeSessionNamed:(NSString *)fileName
{
    NSArray *docs = [owner documents];
    Session *s = session_new();
    char *buf;
    unsigned int i, need;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir, ok;

    if (s == NULL) return NO;
    for (i = 0; i < [docs count]; i++) {
        EditorDoc *d = [docs objectAtIndex:i];
        SessionFile f;
        NSRange sel;
        NSRect fr;
        NSData *pd;

        if ([d path] == nil) continue;
        pd = ui_utf8_cstring([d path]);
        if ([pd length] > SESSION_PATH_SIZE) continue;
        memset(&f, 0, sizeof f);
        memcpy(f.path, [pd bytes], [pd length]);
        sel = [[d textView] selectedRange];
        f.caret = sel.location;
        f.sel = sel.length;
        f.scroll = [d scrollY];
        fr = [[d window] frame];
        f.has_frame = 1;
        f.fx = (int)fr.origin.x; f.fy = (int)fr.origin.y; f.fw = (int)fr.size.width; f.fh = (int)fr.size.height;
        f.wrap = [d wrap] ? 1 : 0;
        session_add(s, &f);
    }
    if (s->n == 0) { session_free(s); return NO; }
    need = session_format(s, NULL, 0);
    buf = (char *)malloc(need + 1);
    if (buf == NULL) { session_free(s); return NO; }
    session_format(s, buf, need + 1);
    if (![fm fileExistsAtPath:folder isDirectory:&isDir]) [fm createDirectoryAtPath:folder attributes:nil];
    ok = write_text([@"# JOSE session\n" stringByAppendingString:ui_string_from_utf8(buf)], [folder stringByAppendingPathComponent:fileName]);
    free(buf);
    session_free(s);
    return ok;
}

- (BOOL)saveAs:(NSString *)name
{
    name = ui_trim(name);
    if (![self validName:name]) return NO;
    if (![self writeSessionNamed:name]) return NO;
    [current release];
    current = [name copy];
    return YES;
}

- (BOOL)save
{
    return current != nil && [self saveAs:current];
}

- (void)recordLast
{
    BOOL ok;

    if (quiet) return;
    SSTrace("session: recording the last session");
    ok = [self writeSessionNamed:LAST_NAME];
    SSTrace("session: %s", ok ? "recorded" : "nothing to record");
}

- (BOOL)hasLast
{
    return [[NSFileManager defaultManager] fileExistsAtPath:[folder stringByAppendingPathComponent:LAST_NAME]];
}

- (BOOL)deleteNamed:(NSString *)name
{
    if (![self validName:name]) return NO;
    if (current != nil && [current isEqualToString:name]) { [current release]; current = nil; }
    return [[NSFileManager defaultManager] removeFileAtPath:[folder stringByAppendingPathComponent:name] handler:nil];
}

static unsigned int missing;

- (unsigned int)missingCount { return missing; }

- (BOOL)openSessionFile:(NSString *)fileName replace:(BOOL)replace
{
    NSString *text = read_text([folder stringByAppendingPathComponent:fileName]);
    Session *s;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *paths = [NSMutableArray array];
    BOOL any = NO;
    int i;

    missing = 0;
    if (text == nil) return NO;
    s = session_new();
    if (s == NULL) return NO;
    session_parse(s, UI_CPATH(text));
    for (i = 0; i < s->n; i++) [paths addObject:[ui_string_from_utf8(s->f[i].path) stringByStandardizingPath]];
    quiet = YES;
    if (replace) {                                      /* what is not in the session goes; the rest stays as it is */
        NSArray *docs = [NSArray arrayWithArray:[owner documents]];
        unsigned int k;

        for (k = 0; k < [docs count]; k++) {
            EditorDoc *d = [docs objectAtIndex:k];

            if ([d path] != nil && [paths containsObject:[[d path] stringByStandardizingPath]]) continue;
            [d showWindow];
            if (![d closeWindow]) { quiet = NO; session_free(s); return NO; }
        }
    }
    for (i = 0; i < s->n; i++) {
        NSString *path = [paths objectAtIndex:i];
        EditorDoc *d;

        if (![fm isReadableFileAtPath:path]) { missing++; continue; }
        d = [owner openPath:path];
        if (d == nil) { missing++; continue; }
        any = YES;
        [d restoreSelection:NSMakeRange(s->f[i].caret, s->f[i].sel) scrollY:s->f[i].scroll];
        if (s->f[i].wrap >= 0 && (BOOL)s->f[i].wrap != [d wrap]) [d setWrap:s->f[i].wrap != 0];
        if (s->f[i].has_frame) {
            NSRect fr = NSMakeRect((float)s->f[i].fx, (float)s->f[i].fy, (float)s->f[i].fw, (float)s->f[i].fh);
            NSScreen *scr = [NSScreen mainScreen];

            if (scr == nil || NSIntersectsRect(fr, [scr frame])) [[d window] setFrame:fr display:YES];     /* not if it would be off the screen */
        }
    }
    quiet = NO;
    session_free(s);
    return any;
}

- (BOOL)open:(NSString *)name replace:(BOOL)replace
{
    BOOL ok;

    if (![self validName:name]) return NO;
    ok = [self openSessionFile:name replace:replace];
    if (ok) { [current release]; current = [name copy]; }
    return ok;
}

- (BOOL)openLast
{
    return [self openSessionFile:LAST_NAME replace:NO];
}

@end
