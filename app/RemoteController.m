#import "RemoteController.h"
#import "AppController.h"
#import "EditorDoc.h"
#import "Appearance.h"
#import "UIHelpers.h"
#include "remote.h"
#include "shellrun.h"
#include "grep.h"
#include <stdlib.h>
#include <string.h>

#define RECENT_MAX 10
#define REMOTE_TIMEOUT_MS 60000U
#define REMOTE_MAX_BYTES (24UL * 1024UL * 1024UL)
#define UNKNOWN_LENGTH ((unsigned long)-1)      /* the file did not exist when it was opened */

@interface RemoteController (Private)
- (BOOL)run:(NSString *)remoteCmd userhost:(NSString *)uh input:(NSData *)input result:(ShellResult *)r;
- (NSString *)errorText:(ShellResult *)r;
- (BOOL)fetchSpec:(NSString *)spec into:(EditorDoc *)d;
- (void)noteRecent:(NSString *)spec;
- (void)dialogOK:(id)sender;
- (void)dialogCancel:(id)sender;
- (void)recentChosen:(id)sender;
@end

static BOOL split_spec(NSString *spec, NSString **userhost, NSString **rpath)
{
    char uh[256], p[2048];
    NSData *d = ui_utf8_cstring(spec);

    if (!remote_parse((const char *)[d bytes], uh, sizeof uh, p, sizeof p)) return NO;
    *userhost = ui_string_from_utf8(uh);
    *rpath = ui_string_from_utf8(p);
    return YES;
}

/* A path as the remote shell is to read it (quoted; ~/ stays the home folder). */
static NSString *qpath(NSString *rpath)
{
    char a[4200];
    NSData *pd = ui_utf8_cstring(rpath);

    remote_path_arg((const char *)[pd bytes], a, sizeof a);
    return ui_string_from_utf8(a);
}

@implementation RemoteController

- (id)initWithOwner:(id)anOwner
{
    self = [super init];
    if (self) {
        NSString *v = [[NSUserDefaults standardUserDefaults] stringForKey:@"RecentRemotes"];
        NSArray *parts = v != nil ? [v componentsSeparatedByString:@"\n"] : [NSArray array];
        unsigned int i;

        owner = anOwner;
        recent = [[NSMutableArray alloc] init];
        for (i = 0; i < [parts count] && [recent count] < RECENT_MAX; i++)
            if ([[parts objectAtIndex:i] length] > 0) [recent addObject:[parts objectAtIndex:i]];
    }
    return self;
}

- (void)dealloc
{
    [recent release];
    [super dealloc];
}

- (void)noteRecent:(NSString *)spec
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    [recent removeObject:spec];
    [recent insertObject:spec atIndex:0];
    while ([recent count] > RECENT_MAX) [recent removeLastObject];
    [ud setObject:[recent componentsJoinedByString:@"\n"] forKey:@"RecentRemotes"];
    [ud synchronize];
}

/* ---- running the program ---- */

- (NSString *)errorText:(ShellResult *)r
{
    NSString *e;

    if (r->timed_out) return @"The connection timed out.";
    e = r->nerr > 0 ? ui_string_from_utf8(r->err) : @"";
    e = ui_trim(e);
    if ([e length] > 500) e = [[e substringToIndex:500] stringByAppendingString:@"..."];
    return [e length] > 0 ? e : [NSString stringWithFormat:@"It exited with status %d.", r->status];
}

- (BOOL)run:(NSString *)remoteCmd userhost:(NSString *)uh input:(NSData *)input result:(ShellResult *)r
{
    int which = [Appearance remoteProgram];
    NSString *prog = [Appearance remotePathFor:which];
    NSData *pd = ui_utf8_cstring(prog), *ed = ui_utf8_cstring([Appearance remoteExtra]);
    NSData *ud = ui_utf8_cstring(uh), *cd = ui_utf8_cstring(remoteCmd);
    size_t need;
    char *line;
    int ran;

    memset(r, 0, sizeof *r);
    if ([prog rangeOfString:@"/"].length > 0 && ![[NSFileManager defaultManager] isExecutableFileAtPath:prog]) {
        r->out = (char *)calloc(1, 1);
        r->err = (char *)calloc(1, 1);
        r->status = -1;
        NSRunAlertPanel(@"Remote Editing", @"%@ was not found or cannot be run. Set the program in Preferences > Remote Editing.", @"OK", nil, nil, prog);
        r->nout = 0;
        r->nerr = 0;
        return NO;
    }
    need = remote_command((const char *)[pd bytes], which == 1, (const char *)[ed bytes], (const char *)[ud bytes], (const char *)[cd bytes], NULL, 0);
    line = (char *)malloc(need + 1);
    if (line == NULL) return NO;
    remote_command((const char *)[pd bytes], which == 1, (const char *)[ed bytes], (const char *)[ud bytes], (const char *)[cd bytes], line, need + 1);
    SSTrace("remote: %s", line);
    ran = shell_run(line, NULL, input != nil ? (const char *)[input bytes] : NULL, input != nil ? [input length] : 0, REMOTE_TIMEOUT_MS, REMOTE_MAX_BYTES, r);
    free(line);
    return ran != 0;
}

/* ---- opening ---- */

- (BOOL)fetchSpec:(NSString *)spec into:(EditorDoc *)d
{
    NSString *uh, *rpath;
    ShellResult r;
    NSData *data;

    if (!split_spec(spec, &uh, &rpath)) {
        NSRunAlertPanel(@"Open Remote", @"\"%@\" is not of the form [user@]host:path.", @"OK", nil, nil, spec);
        return NO;
    }
    if (![self run:[NSString stringWithFormat:@"cat %@", qpath(rpath)] userhost:uh input:nil result:&r]) { shell_result_free(&r); return NO; }
    if (r.status != 0 || r.timed_out) {
        NSString *why = [self errorText:&r];
        BOOL missing = r.status != 0 && !r.timed_out && ([why rangeOfString:@"No such file"].length > 0 || [why rangeOfString:@"not found"].length > 0);

        shell_result_free(&r);
        if (missing && d != nil && [d remoteSpec] == nil &&
            NSRunAlertPanel(@"Open Remote", @"%@ does not exist. Start a new file there?", @"Create", @"Cancel", nil, spec) == NSAlertDefaultReturn) {
            [d loadRemoteData:[NSData data] spec:spec remotePath:rpath];
            [d setRemoteCrc:0 length:UNKNOWN_LENGTH];
            return YES;
        }
        if (!missing) NSRunAlertPanel(@"Open Remote", @"%@ could not be read:\n%@", @"OK", nil, nil, spec, why);
        return NO;
    }
    if (r.truncated) {
        shell_result_free(&r);
        NSRunAlertPanel(@"Open Remote", @"%@ is too big to edit this way (over %u MB).", @"OK", nil, nil, spec, (unsigned)(REMOTE_MAX_BYTES / (1024UL * 1024UL)));
        return NO;
    }
    if (!grep_bytes_are_text((const unsigned char *)r.out, (unsigned)r.nout)) {
        shell_result_free(&r);
        NSRunAlertPanel(@"Open Remote", @"%@ is not UTF-8 text, so it is not opened (a binary or Latin-1 file would be damaged by saving it).", @"OK", nil, nil, spec);
        return NO;
    }
    data = [NSData dataWithBytes:r.out length:r.nout];
    [d loadRemoteData:data spec:spec remotePath:rpath];
    [d setRemoteCrc:remote_cksum((const unsigned char *)r.out, r.nout) length:(unsigned long)r.nout];
    shell_result_free(&r);
    return YES;
}

- (EditorDoc *)openSpec:(NSString *)spec
{
    EditorDoc *d;
    unsigned int i;

    spec = ui_trim(spec);
    {
        NSArray *now = [(AppController *)owner documents];

        for (i = 0; i < [now count]; i++) {                      /* already open: bring it forward */
            EditorDoc *o = [now objectAtIndex:i];

            if ([o remoteSpec] != nil && [[o remoteSpec] isEqualToString:spec]) { [o showWindow]; return o; }
        }
    }
    d = [(AppController *)owner newDocument];
    if (![self fetchSpec:spec into:d]) {
        if ([d remoteSpec] == nil) [d closeWindow];            /* the empty window made for it goes again */
        return nil;
    }
    [self noteRecent:spec];
    [d showWindow];
    return d;
}

- (BOOL)reloadDocument:(EditorDoc *)d
{
    NSString *spec = [[[d remoteSpec] copy] autorelease];

    if (spec == nil) return NO;
    return [self fetchSpec:spec into:d];
}

/* ---- saving ---- */

- (BOOL)remoteChanged:(EditorDoc *)d
{
    NSString *uh, *rpath;
    ShellResult r;
    unsigned long crc, len;
    BOOL changed = NO;

    if ([d remoteLength] == UNKNOWN_LENGTH || !split_spec([d remoteSpec], &uh, &rpath)) return NO;
    if ([self run:[NSString stringWithFormat:@"cksum < %@", qpath(rpath)] userhost:uh input:nil result:&r] && r.status == 0 &&
        remote_parse_cksum(r.out, &crc, &len))
        changed = crc != [d remoteCrc] || len != [d remoteLength];
    shell_result_free(&r);
    return changed;
}

- (BOOL)saveDocument:(EditorDoc *)d
{
    NSString *uh, *rpath, *tmp;
    NSData *data = [d dataToSave];
    ShellResult r;
    BOOL ok;

    if (data == nil || !split_spec([d remoteSpec], &uh, &rpath)) return NO;
    if ([self remoteChanged:d] &&
        NSRunAlertPanel(@"Save Remote File", @"%@ has changed on the other machine since it was read. Overwrite it with this text?", @"Overwrite", @"Cancel", nil, [d remoteSpec]) != NSAlertDefaultReturn)
        return NO;
    tmp = [rpath stringByAppendingString:@".jose-tmp"];
    if (![self run:[NSString stringWithFormat:@"cat > %@ && cat %@ > %@ && rm -f %@", qpath(tmp), qpath(tmp), qpath(rpath), qpath(tmp)] userhost:uh input:data result:&r]) { shell_result_free(&r); return NO; }
    ok = r.status == 0 && !r.timed_out;
    if (!ok) {
        NSRunAlertPanel(@"Save Remote File", @"%@ could not be written:\n%@", @"OK", nil, nil, [d remoteSpec], [self errorText:&r]);
        shell_result_free(&r);
        return NO;
    }
    shell_result_free(&r);
    [d setRemoteCrc:remote_cksum((const unsigned char *)[data bytes], [data length]) length:(unsigned long)[data length]];
    return YES;
}

/* ---- the dialog ---- */

- (void)dialogOK:(id)sender { [NSApp stopModalWithCode:NSOKButton]; }
- (void)dialogCancel:(id)sender { [NSApp stopModalWithCode:NSCancelButton]; }

- (void)recentChosen:(id)sender
{
    int i = [sender indexOfSelectedItem] - 1;

    if (i >= 0 && i < (int)[recent count]) [specField setStringValue:[recent objectAtIndex:i]];
}

- (void)openDialog
{
    NSPopUpButton *pop;
    unsigned int i;
    NSString *spec = nil;

    dialogPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 420, 128)
                                             styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                               backing:NSBackingStoreBuffered defer:NO];
    [dialogPanel setTitle:@"Open Remote"];
    [[dialogPanel contentView] addSubview:ui_label(@"File:", NSMakeRect(16, 92, 50, 18))];
    specField = ui_field(NSMakeRect(70, 90, 334, 22));
    [specField setTarget:self];
    [specField setAction:@selector(dialogOK:)];
    if ([recent count] > 0) [specField setStringValue:[recent objectAtIndex:0]];
    [[dialogPanel contentView] addSubview:specField];
    [[dialogPanel contentView] addSubview:ui_label(@"Recent:", NSMakeRect(16, 60, 50, 18))];
    pop = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(70, 56, 334, 24) pullsDown:NO] autorelease];
    [pop addItemWithTitle:@"-"];
    for (i = 0; i < [recent count]; i++) [pop addItemWithTitle:[recent objectAtIndex:i]];
    [pop setTarget:self];
    [pop setAction:@selector(recentChosen:)];
    [[dialogPanel contentView] addSubview:pop];
    [[dialogPanel contentView] addSubview:ui_label(@"As [user@]host:path, for example me@sparc:/home/me/x.c or sparc:~/x.c", NSMakeRect(16, 38, 388, 14))];
    [[dialogPanel contentView] addSubview:ui_button(@"Open", NSMakeRect(334, 6, 70, 28), self, @selector(dialogOK:))];
    [[dialogPanel contentView] addSubview:ui_button(@"Cancel", NSMakeRect(254, 6, 70, 28), self, @selector(dialogCancel:))];
    [dialogPanel center];
    [dialogPanel makeFirstResponder:specField];
    if ([NSApp runModalForWindow:dialogPanel] == NSOKButton) spec = [[[specField stringValue] copy] autorelease];
    [dialogPanel close];
    [dialogPanel release];
    dialogPanel = nil;
    if (spec != nil && [ui_trim(spec) length] > 0) [self openSpec:spec];
}

@end
