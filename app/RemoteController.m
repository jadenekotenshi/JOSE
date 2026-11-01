#import "RemoteController.h"
#import "AppController.h"
#import "EditorDoc.h"
#import "Appearance.h"
#import "UIHelpers.h"
#include "remote.h"
#include "shellrun.h"
#include "grep.h"
#include "enc.h"
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
- (void)buildBrowser;
- (void)browseGo:(id)sender;
- (void)browseUp:(id)sender;
- (void)browseOpen:(id)sender;
- (void)browseClose:(id)sender;
- (void)browseList:(NSString *)dir;
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
    if (enc_looks_binary((const unsigned char *)r.out, r.nout)) {
        shell_result_free(&r);
        NSRunAlertPanel(@"Open Remote", @"%@ looks like a binary file (it holds NUL bytes), so it is not opened.", @"OK", nil, nil, spec);
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

/* ---- the browser ---- */

- (NSArray *)listDirectory:(NSString *)dir userhost:(NSString *)uh hidden:(BOOL)hidden resolved:(NSString **)abs
{
    ShellResult r;
    NSString *cmd, *text;
    NSMutableArray *lines, *dirs = [NSMutableArray array], *files = [NSMutableArray array];
    unsigned int i;

    cmd = [NSString stringWithFormat:@"cd %@ && pwd && for f in %@; do if [ -d \"$f\" ]; then echo \"$f/\"; elif [ -e \"$f\" ] || [ -L \"$f\" ]; then echo \"$f\"; fi; done",
           qpath(dir), hidden ? @"* .[!.]* ..?*" : @"*"];
    if (![self run:cmd userhost:uh input:nil result:&r]) { shell_result_free(&r); *abs = @"Could not run the program."; return nil; }
    if (r.status != 0 || r.timed_out) {
        *abs = [self errorText:&r];
        shell_result_free(&r);
        return nil;
    }
    text = ui_string_from_utf8(r.out);
    shell_result_free(&r);
    lines = [NSMutableArray arrayWithArray:[text componentsSeparatedByString:@"\n"]];
    if ([lines count] == 0 || [[lines objectAtIndex:0] length] == 0) { *abs = @"The far side did not say where it is."; return nil; }
    *abs = [[[lines objectAtIndex:0] copy] autorelease];
    for (i = 1; i < [lines count]; i++) {
        NSString *n = [lines objectAtIndex:i];

        if ([n length] == 0 || [n isEqualToString:@"*/"] || [n isEqualToString:@"*"]) continue;                /* a glob that matched nothing */
        if ([n characterAtIndex:[n length] - 1] == '/') [dirs addObject:n]; else [files addObject:n];
    }
    [dirs addObjectsFromArray:files];
    return dirs;
}

- (int)numberOfRowsInTableView:(NSTableView *)tv { return (int)[browseNames count]; }

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(int)row
{
    return (row >= 0 && row < (int)[browseNames count]) ? [browseNames objectAtIndex:row] : @"";
}

- (void)browseList:(NSString *)dir
{
    NSString *uh = ui_trim([browseHost stringValue]), *abs = nil;
    NSArray *names;

    if ([uh length] == 0) { [browseMessage setStringValue:@"Type the machine as [user@]host."]; return; }
    [browseMessage setStringValue:@"Listing..."];
    [browseMessage display];
    names = [self listDirectory:dir userhost:uh hidden:[browseHidden state] == NSOnState resolved:&abs];
    if (names == nil) {
        [browseMessage setStringValue:abs];
        return;
    }
    [browseCurrent release];
    browseCurrent = [abs copy];
    [browseDir setStringValue:abs];
    [browseNames removeAllObjects];
    [browseNames addObjectsFromArray:names];
    [browseTable reloadData];
    [browseMessage setStringValue:[NSString stringWithFormat:@"%u entries in %@", (unsigned)[names count], abs]];
    {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

        [ud setObject:uh forKey:@"RemoteBrowseHost"];
        [ud setObject:abs forKey:@"RemoteBrowseDir"];
    }
}

- (void)browseGo:(id)sender
{
    NSString *d = ui_trim([browseDir stringValue]);

    [self browseList:[d length] > 0 ? d : @"~"];
}

- (void)browseUp:(id)sender
{
    NSString *cur = browseCurrent != nil ? browseCurrent : ui_trim([browseDir stringValue]);

    if ([cur length] == 0 || [cur isEqualToString:@"/"]) return;
    [self browseList:[cur stringByDeletingLastPathComponent]];
}

- (void)browseOpen:(id)sender
{
    int row = [browseTable clickedRow];
    NSString *name, *full;

    if (row < 0) row = [browseTable selectedRow];
    if (row < 0 || row >= (int)[browseNames count] || browseCurrent == nil) return;
    name = [browseNames objectAtIndex:row];
    if ([name characterAtIndex:[name length] - 1] == '/') {                         /* a folder: go into it */
        [self browseList:[browseCurrent stringByAppendingPathComponent:[name substringToIndex:[name length] - 1]]];
        return;
    }
    full = [NSString stringWithFormat:@"%@:%@", ui_trim([browseHost stringValue]), [browseCurrent stringByAppendingPathComponent:name]];
    if ([self openSpec:full] == nil) [browseMessage setStringValue:@"That file could not be opened."];
}

- (void)browseClose:(id)sender
{
    [browsePanel orderOut:nil];
}

- (void)buildBrowser
{
    NSView *c;
    NSTableColumn *col;
    NSScrollView *sv;

    browsePanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 480, 400)
                                             styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask)
                                               backing:NSBackingStoreBuffered defer:NO];
    [browsePanel setTitle:@"Browse Remote"];
    [browsePanel setReleasedWhenClosed:NO];
    [browsePanel setMinSize:NSMakeSize(360, 280)];
    c = [browsePanel contentView];
    [c addSubview:ui_label(@"Machine:", NSMakeRect(14, 366, 60, 18))];
    browseHost = ui_field(NSMakeRect(80, 364, 386, 22));
    [browseHost setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [c addSubview:browseHost];
    [c addSubview:ui_label(@"Folder:", NSMakeRect(14, 336, 60, 18))];
    browseDir = ui_field(NSMakeRect(80, 334, 306, 22));
    [browseDir setTarget:self];
    [browseDir setAction:@selector(browseGo:)];
    [browseDir setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [c addSubview:browseDir];
    {
        NSButton *b = ui_button(@"List", NSMakeRect(392, 330, 74, 28), self, @selector(browseGo:));
        [b setAutoresizingMask:(NSViewMinXMargin | NSViewMinYMargin)];
        [c addSubview:b];
    }
    browseHidden = ui_switch(@"Show hidden files", NSMakeRect(14, 306, 200, 20));
    [browseHidden setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];
    [c addSubview:browseHidden];
    browseTable = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 440, 200)] autorelease];
    col = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
    [[col headerCell] setStringValue:@"Double-click a folder to enter it, a file to open it"];
    [col setWidth:1200];
    [col setEditable:NO];
    [browseTable addTableColumn:col];
    [browseTable setDataSource:(id)self];
    [browseTable setAllowsMultipleSelection:NO];
    [browseTable setTarget:self];
    [browseTable setDoubleAction:@selector(browseOpen:)];
    sv = [[[NSScrollView alloc] initWithFrame:NSMakeRect(14, 70, 452, 228)] autorelease];
    [sv setHasVerticalScroller:YES];
    [sv setHasHorizontalScroller:YES];
    [sv setBorderType:NSBezelBorder];
    [sv setDocumentView:browseTable];
    [sv setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [c addSubview:sv];
    browseMessage = ui_label(@"", NSMakeRect(14, 44, 452, 18));
    [browseMessage setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
    [c addSubview:browseMessage];
    {
        NSButton *b;

        b = ui_button(@"Up", NSMakeRect(14, 8, 60, 28), self, @selector(browseUp:));
        [b setAutoresizingMask:(NSViewMaxXMargin | NSViewMaxYMargin)]; [c addSubview:b];
        b = ui_button(@"Open", NSMakeRect(80, 8, 70, 28), self, @selector(browseOpen:));
        [b setAutoresizingMask:(NSViewMaxXMargin | NSViewMaxYMargin)]; [c addSubview:b];
        b = ui_button(@"Close", NSMakeRect(396, 8, 70, 28), self, @selector(browseClose:));
        [b setAutoresizingMask:(NSViewMinXMargin | NSViewMaxYMargin)]; [c addSubview:b];
    }
    browseNames = [[NSMutableArray alloc] init];
    [browsePanel center];
}

- (void)browse
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *h = [ud stringForKey:@"RemoteBrowseHost"], *d = [ud stringForKey:@"RemoteBrowseDir"];

    if (browsePanel == nil) [self buildBrowser];
    if (h == nil && [recent count] > 0) {                                  /* the machine of the file opened last */
        NSString *uh, *rp;

        if (split_spec([recent objectAtIndex:0], &uh, &rp)) { h = uh; d = [rp stringByDeletingLastPathComponent]; }
    }
    if ([[browseHost stringValue] length] == 0 && h != nil) [browseHost setStringValue:h];
    if ([[browseDir stringValue] length] == 0) [browseDir setStringValue:d != nil ? d : @"~"];
    [browsePanel makeKeyAndOrderFront:nil];
    [browsePanel makeFirstResponder:[[browseHost stringValue] length] > 0 ? (NSResponder *)browseDir : (NSResponder *)browseHost];
}

@end
