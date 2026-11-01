#import "FilesController.h"
#import "AppController.h"
#import "EditorDoc.h"
#import "UIHelpers.h"
#include "search.h"
#include "grep.h"
#include "eol.h"
#include <stdlib.h>
#include <string.h>

#define MAX_FILES    20000
#define MAX_ROWS     3000
#define MAX_FILESIZE 4000000UL

@interface FilesController (Private)
- (void)buildPanel;
- (void)say:(NSString *)text;
- (int)flags;
- (Search *)compiledSearch;
- (void)clearRows;
- (void)collectFilesIn:(NSString *)dir recursive:(BOOL)rec patterns:(const char *)pats into:(NSMutableArray *)found;
- (NSString *)textOfFile:(NSString *)file eol:(int *)eol mixed:(int *)mixed doc:(EditorDoc **)doc;
- (void)findAll:(id)sender;
- (void)replaceAll:(id)sender;
- (void)useFileFolder:(id)sender;
- (void)openRow:(id)sender;
- (void)closePanel:(id)sender;
- (void)stopRun:(id)sender;
- (void)beginRun;
- (void)endRun;
- (BOOL)pumpIfDue;
- (NSString *)replaceInFiles:(NSArray *)hitFiles search:(Search *)s with:(NSString *)replacement literal:(BOOL)literal backups:(BOOL)backups;
- (unsigned int)scanFiles:(NSArray *)files search:(Search *)s filesWithHits:(NSMutableArray *)hitFiles;
@end

/* OpenStep's NSString has no -hasPrefix:. */
static BOOL starts_with(NSString *s, NSString *prefix)
{
    return [s length] >= [prefix length] && [[s substringToIndex:[prefix length]] isEqualToString:prefix];
}

static u16 *units_of(NSString *s, unsigned int *n)
{
    u16 *buf;

    *n = [s length];
    buf = (u16 *)malloc((*n + 1) * sizeof(u16));
    if (buf != NULL && *n > 0) [s getCharacters:buf];
    return buf;
}

@implementation FilesController

- (id)initWithOwner:(id)anOwner
{
    self = [super init];
    if (self) {
        owner = anOwner;
        rowText = [[NSMutableArray alloc] init];
        rowPath = [[NSMutableArray alloc] init];
        rowLine = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [rowText release];
    [rowPath release];
    [rowLine release];
    [super dealloc];
}

- (void)say:(NSString *)text
{
    if (message == nil) return;
    [message setStringValue:text];
    [message display];
}

- (void)buildPanel
{
    NSView *c;
    NSTableColumn *col;
    NSScrollView *sv;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *v;

    if (panel != nil) return;
    panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 560, 470)
                                       styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask)
                                         backing:NSBackingStoreBuffered defer:NO];
    [panel setTitle:@"Find in Files"];
    [panel setReleasedWhenClosed:NO];
    [panel setMinSize:NSMakeSize(560, 360)];
    [panel setDelegate:self];
    c = [panel contentView];

    [c addSubview:ui_label(@"Find:", NSMakeRect(14, 438, 70, 18))];
    findField = ui_field(NSMakeRect(100, 436, 446, 22));
    [findField setTarget:self];
    [findField setAction:@selector(findAll:)];
    [findField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [c addSubview:findField];
    [c addSubview:ui_label(@"Replace with:", NSMakeRect(14, 408, 84, 18))];
    replaceField = ui_field(NSMakeRect(100, 406, 446, 22));
    [replaceField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [c addSubview:replaceField];
    [c addSubview:ui_label(@"Folder:", NSMakeRect(14, 378, 70, 18))];
    folderField = ui_field(NSMakeRect(100, 376, 326, 22));
    [folderField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [c addSubview:folderField];
    {
        NSButton *b = ui_button(@"This File's Folder", NSMakeRect(432, 372, 114, 28), self, @selector(useFileFolder:));
        [b setAutoresizingMask:(NSViewMinXMargin | NSViewMinYMargin)];
        [c addSubview:b];
    }
    [c addSubview:ui_label(@"File names:", NSMakeRect(14, 348, 84, 18))];
    patternField = ui_field(NSMakeRect(100, 346, 446, 22));
    [patternField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [c addSubview:patternField];

    caseSwitch = ui_switch(@"Case sensitive", NSMakeRect(14, 318, 130, 20));
    regexSwitch = ui_switch(@"Regular expression", NSMakeRect(150, 318, 150, 20));
    wordSwitch = ui_switch(@"Whole word", NSMakeRect(306, 318, 110, 20));
    subSwitch = ui_switch(@"Subfolders", NSMakeRect(14, 294, 130, 20));
    backupSwitch = ui_switch(@"Keep .bak copies when replacing", NSMakeRect(150, 294, 260, 20));
    [subSwitch setState:NSOnState];
    [backupSwitch setState:NSOnState];
    {
        NSButton *all[5];
        int i;

        all[0] = caseSwitch; all[1] = regexSwitch; all[2] = wordSwitch; all[3] = subSwitch; all[4] = backupSwitch;
        for (i = 0; i < 5; i++) {
            [all[i] setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];
            [c addSubview:all[i]];
        }
    }

    table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 520, 160)] autorelease];
    col = [[[NSTableColumn alloc] initWithIdentifier:@"match"] autorelease];
    [[col headerCell] setStringValue:@"Matching lines (double-click to open)"];
    [col setWidth:2000];
    [col setEditable:NO];
    [table addTableColumn:col];
    [table setDataSource:(id)self];
    [table setAllowsMultipleSelection:NO];
    [table setTarget:self];
    [table setDoubleAction:@selector(openRow:)];
    sv = [[[NSScrollView alloc] initWithFrame:NSMakeRect(14, 76, 532, 212)] autorelease];
    [sv setHasVerticalScroller:YES];
    [sv setHasHorizontalScroller:YES];
    [sv setBorderType:NSBezelBorder];
    [sv setDocumentView:table];
    [sv setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [c addSubview:sv];

    {
        NSButton *b;

        b = ui_button(@"Find All", NSMakeRect(14, 40, 100, 28), self, @selector(findAll:));
        [b setAutoresizingMask:(NSViewMaxXMargin | NSViewMaxYMargin)];
        [c addSubview:b];
        findButton = b;
        b = ui_button(@"Replace All...", NSMakeRect(120, 40, 110, 28), self, @selector(replaceAll:));
        [b setAutoresizingMask:(NSViewMaxXMargin | NSViewMaxYMargin)];
        [c addSubview:b];
        replaceButton = b;
        b = ui_button(@"Stop", NSMakeRect(236, 40, 70, 28), self, @selector(stopRun:));
        [b setAutoresizingMask:(NSViewMaxXMargin | NSViewMaxYMargin)];
        [b setEnabled:NO];
        [c addSubview:b];
        stopButton = b;
        b = ui_button(@"Close", NSMakeRect(476, 40, 70, 28), self, @selector(closePanel:));
        [b setAutoresizingMask:(NSViewMinXMargin | NSViewMaxYMargin)];
        [c addSubview:b];
    }
    message = ui_label(@"", NSMakeRect(14, 12, 532, 18));
    [message setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
    [c addSubview:message];

    v = [ud stringForKey:@"FilesFolder"];
    if (v != nil) [folderField setStringValue:v];
    v = [ud stringForKey:@"FilesPattern"];
    [patternField setStringValue:v != nil ? v : @"*"];
    [panel center];
}

- (void)showPanel
{
    EditorDoc *d = [owner frontDocument];

    [self buildPanel];
    if (d != nil) {
        NSRange sel = [[d textView] selectedRange];

        if (sel.length > 0 && sel.length < 200) {
            NSString *t = [[[d textView] string] substringWithRange:sel];
            if ([t rangeOfString:@"\n"].length == 0) [findField setStringValue:t];
        }
        if ([[folderField stringValue] length] == 0) [folderField setStringValue:[d workingDirectory]];
    }
    if ([[folderField stringValue] length] == 0) [folderField setStringValue:NSHomeDirectory()];
    [panel makeKeyAndOrderFront:nil];
    [panel makeFirstResponder:findField];
    [findField selectText:nil];
}

- (void)closePanel:(id)sender
{
    if (modalSession != NULL) { stopRequested = YES; return; }       /* closing during a run stops it */
    [panel orderOut:nil];
}

- (BOOL)windowShouldClose:(id)sender
{
    if (modalSession != NULL) { stopRequested = YES; return NO; }
    return YES;
}

/* ---- running a search without freezing the panel ---- */

- (void)stopRun:(id)sender
{
    stopRequested = YES;
}

/* The panel becomes a modal session: its Stop button works, and nothing else in the program does until the run ends. */
- (void)beginRun
{
    stopRequested = NO;
    [findButton setEnabled:NO];
    [replaceButton setEnabled:NO];
    [stopButton setEnabled:YES];
    modalSession = [NSApp beginModalSessionForWindow:panel];
    lastPump = [NSDate timeIntervalSinceReferenceDate];
}

- (void)endRun
{
    if (modalSession != NULL) {
        [NSApp endModalSession:modalSession];
        modalSession = NULL;
    }
    [findButton setEnabled:YES];
    [replaceButton setEnabled:YES];
    [stopButton setEnabled:NO];
}

/* Lets the panel handle its events (about ten times a second at most).  NO if Stop was pressed. */
- (BOOL)pumpIfDue
{
    NSTimeInterval now;

    if (modalSession == NULL) return !stopRequested;
    now = [NSDate timeIntervalSinceReferenceDate];
    if (now - lastPump >= 0.1) {
        lastPump = now;
        [NSApp runModalSession:modalSession];
    }
    return !stopRequested;
}

- (void)useFileFolder:(id)sender
{
    EditorDoc *d = [owner frontDocument];

    if (d != nil) [folderField setStringValue:[d workingDirectory]];
}

- (int)flags
{
    int f = 0;

    if ([regexSwitch state] == NSOnState) f |= SEARCH_REGEX;
    if ([caseSwitch state] != NSOnState) f |= SEARCH_ICASE;
    if ([wordSwitch state] == NSOnState) f |= SEARCH_WORD;
    return f;
}

/* The compiled search for the panel's text and switches (the caller frees it); NULL, with a message, if it is empty or bad. */
- (Search *)compiledSearch
{
    NSString *pat = [findField stringValue];
    Search *s;
    char err[100];
    unsigned int n;
    u16 *u;

    if ([pat length] == 0) { [self say:@"Type the text to find."]; return NULL; }
    u = units_of(pat, &n);
    if (u == NULL) { [self say:@"Out of memory."]; return NULL; }
    s = search_new(u, n, [self flags], err, sizeof err);
    free(u);
    if (s == NULL) [self say:[NSString stringWithFormat:@"Bad pattern: %s", err]];
    return s;
}

/* ---- the list ---- */

- (int)numberOfRowsInTableView:(NSTableView *)tv { return (int)[rowText count]; }

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(int)row
{
    if (row < 0 || row >= (int)[rowText count]) return @"";
    return [rowText objectAtIndex:row];
}

- (void)clearRows
{
    [rowText removeAllObjects];
    [rowPath removeAllObjects];
    [rowLine removeAllObjects];
    [table reloadData];
}

- (void)openRow:(id)sender
{
    int row = [table clickedRow];
    EditorDoc *d;

    if (row < 0) row = [table selectedRow];
    if (row < 0 || row >= (int)[rowPath count]) return;
    d = [owner openPath:[rowPath objectAtIndex:row]];
    if (d != nil) [d goToLine:[[rowLine objectAtIndex:row] intValue]];
}

/* ---- walking the folder ---- */

- (void)collectFilesIn:(NSString *)dir recursive:(BOOL)rec patterns:(const char *)pats into:(NSMutableArray *)found
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [[fm directoryContentsAtPath:dir] sortedArrayUsingSelector:@selector(compare:)];
    unsigned int i;

    for (i = 0; i < [names count] && [found count] < MAX_FILES && [self pumpIfDue]; i++) {
        NSString *name = [names objectAtIndex:i];
        NSString *full = [dir stringByAppendingPathComponent:name];
        NSString *type = [[fm fileAttributesAtPath:full traverseLink:NO] fileType];

        if (type == nil) continue;
        if ([type isEqualToString:NSFileTypeDirectory]) {
            if (rec && !starts_with(name, @".") && ![name isEqualToString:@"CVS"])
                [self collectFilesIn:full recursive:rec patterns:pats into:found];
        } else if ([type isEqualToString:NSFileTypeRegular]) {
            if (glob_match_any(pats, UI_CPATH(name))) [found addObject:full];
        }
    }
}

/* The text of a file as the editor would see it (one LF per line): from its window if it is open there, else from disk.  nil
 * if it is not text we may touch (too big, a NUL, not UTF-8); *mixed is set if the line endings are mixed. */
- (NSString *)textOfFile:(NSString *)file eol:(int *)eol mixed:(int *)mixed doc:(EditorDoc **)doc
{
    NSData *data;
    NSString *text;
    char *bytes;
    unsigned int n;

    *eol = 0;
    *mixed = 0;
    *doc = [owner documentForPath:file];
    if (*doc != nil) return [*doc expandedString:[[*doc textView] string]];
    if ([[[NSFileManager defaultManager] fileAttributesAtPath:file traverseLink:YES] fileSize] > MAX_FILESIZE) return nil;
    data = [NSData dataWithContentsOfFile:file];
    if (data == nil) return nil;
    n = [data length];
    if (!grep_bytes_are_text((const unsigned char *)[data bytes], n)) return nil;
    bytes = (char *)malloc(n + 1);
    if (bytes == NULL) return nil;
    [data getBytes:bytes];
    *eol = eol_detect(bytes, n, mixed);
    n = eol_normalize(bytes, n);
    bytes[n] = '\0';
    text = ui_string_from_utf8(bytes);
    free(bytes);
    return text;
}

static NSString *clip_line(NSString *text, unsigned int a, unsigned int b)
{
    NSString *l;
    unsigned int i, n;
    NSMutableString *r;

    if (b - a > 200) b = a + 200;
    l = [text substringWithRange:NSMakeRange(a, b - a)];
    n = [l length];
    r = [NSMutableString stringWithCapacity:n];
    for (i = 0; i < n; i++) {                                     /* a tab would show as a box in the list */
        unichar ch = [l characterAtIndex:i];
        [r appendString:ch == '\t' ? @"    " : [NSString stringWithCharacters:&ch length:1]];
    }
    return r;
}

/* Searches the files, filling the list.  Returns the number of matching lines; hitFiles gets the files that had any. */
- (unsigned int)scanFiles:(NSArray *)files search:(Search *)s filesWithHits:(NSMutableArray *)hitFiles
{
    NSString *root = [[folderField stringValue] stringByStandardizingPath];
    unsigned int i, total = 0;

    skippedFiles = 0;
    for (i = 0; i < [files count] && total < MAX_ROWS && [self pumpIfDue]; i++) {
        NSString *file = [files objectAtIndex:i];
        NSString *text;
        EditorDoc *doc;
        int eol, mixed;
        GrepHits hits = { NULL, 0, 0 };
        u16 *u;
        unsigned int n, k, h;

        if (i % 25 == 0) [self say:[NSString stringWithFormat:@"Searching... %u of %u files", i, (unsigned)[files count]]];
        text = [self textOfFile:file eol:&eol mixed:&mixed doc:&doc];
        if (text == nil) { skippedFiles++; continue; }
        u = units_of(text, &n);
        if (u == NULL) continue;
        k = grep_text(s, u, n, &hits, MAX_ROWS - total);
        free(u);
        if (k > 0) {
            NSString *rel = file;

            if (starts_with(file, root) && [file length] > [root length] + 1) rel = [file substringFromIndex:[root length] + 1];
            [hitFiles addObject:file];
            for (h = 0; h < hits.n; h++) {
                NSString *l = clip_line(text, hits.hit[h].lstart, hits.hit[h].lend);

                [rowText addObject:[NSString stringWithFormat:@"%@:%u: %@", rel, hits.hit[h].line, l]];
                [rowPath addObject:file];
                [rowLine addObject:[NSNumber numberWithInt:(int)hits.hit[h].line]];
            }
            total += k;
        }
        grep_free(&hits);
    }
    return total;
}

/* Gathers what the panel asks for.  NO (with a message) if it cannot go ahead. */
static NSString *plural(unsigned int n, NSString *one, NSString *many)
{
    return [NSString stringWithFormat:@"%u %@", n, n == 1 ? one : many];
}

- (void)findAll:(id)sender
{
    NSString *folder = [[folderField stringValue] stringByStandardizingPath];
    NSMutableArray *files = [NSMutableArray array], *hitFiles = [NSMutableArray array];
    NSData *pats = ui_utf8_cstring([patternField stringValue]);
    BOOL isDir;
    Search *s;
    unsigned int total;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    [self clearRows];
    if (![[NSFileManager defaultManager] fileExistsAtPath:folder isDirectory:&isDir] || !isDir) {
        [self say:@"That folder is not there."];
        return;
    }
    s = [self compiledSearch];
    if (s == NULL) return;
    [ud setObject:[folderField stringValue] forKey:@"FilesFolder"];
    [ud setObject:[patternField stringValue] forKey:@"FilesPattern"];
    [self say:@"Looking for files..."];
    [self beginRun];
    [self collectFilesIn:folder recursive:[subSwitch state] == NSOnState patterns:(const char *)[pats bytes] into:files];
    total = [self scanFiles:files search:s filesWithHits:hitFiles];
    [self endRun];
    search_free(s);
    [table reloadData];
    [self say:[NSString stringWithFormat:@"%@%@ in %@ (of %@ searched%@%@)", stopRequested ? @"Stopped: " : @"",
               plural(total, @"line", @"lines"), plural([hitFiles count], @"file", @"files"), plural([files count], @"file", @"files"),
               skippedFiles > 0 ? [NSString stringWithFormat:@"; %u not text or too big", skippedFiles] : @"",
               total >= MAX_ROWS ? @"; list is full, more may follow" : @""]];
}

- (void)replaceAll:(id)sender
{
    NSString *folder = [[folderField stringValue] stringByStandardizingPath];
    NSMutableArray *files = [NSMutableArray array], *hitFiles = [NSMutableArray array];
    NSData *pats = ui_utf8_cstring([patternField stringValue]);
    BOOL isDir, regex = [regexSwitch state] == NSOnState, backups = [backupSwitch state] == NSOnState;
    Search *s;
    unsigned int total, i, openDocs = 0;
    int choice;

    [self clearRows];
    if (![[NSFileManager defaultManager] fileExistsAtPath:folder isDirectory:&isDir] || !isDir) {
        [self say:@"That folder is not there."];
        return;
    }
    s = [self compiledSearch];
    if (s == NULL) return;
    [self say:@"Looking for files..."];
    [self beginRun];
    [self collectFilesIn:folder recursive:[subSwitch state] == NSOnState patterns:(const char *)[pats bytes] into:files];
    total = [self scanFiles:files search:s filesWithHits:hitFiles];
    [self endRun];
    [table reloadData];
    if (stopRequested) {
        search_free(s);
        [self say:@"Stopped; nothing replaced."];
        return;
    }
    if (total == 0) {
        search_free(s);
        [self say:@"Nothing found, nothing replaced."];
        return;
    }
    for (i = 0; i < [hitFiles count]; i++)
        if ([owner documentForPath:[hitFiles objectAtIndex:i]] != nil) openDocs++;
    choice = NSRunAlertPanel(@"Replace in Files",
                             @"Replace in %@ (%@ with a match)?%@  This cannot be undone for files that are not open.%@",
                             @"Replace", @"Cancel", nil,
                             plural([hitFiles count], @"file", @"files"), plural(total, @"line", @"lines"),
                             openDocs > 0 ? [NSString stringWithFormat:@" %u of them are open in windows and change there (not saved).", openDocs] : @"",
                             backups ? @"  Each changed file is kept as name.bak." : @"");
    if (choice != NSAlertDefaultReturn) {
        search_free(s);
        [self say:@"Cancelled."];
        return;
    }
    [self beginRun];
    {
        NSString *summary = [self replaceInFiles:hitFiles search:s with:[replaceField stringValue] literal:!regex backups:backups];

        [self endRun];
        [self say:stopRequested ? [@"Stopped part way. " stringByAppendingString:summary] : summary];
    }
    search_free(s);
}

/* Replaces in each of the files (those open in a window change there, the rest on disk).  Returns the summary to show. */
- (NSString *)replaceInFiles:(NSArray *)hitFiles search:(Search *)s with:(NSString *)replacement literal:(BOOL)literal backups:(BOOL)backups
{
    unsigned int i, nrepl, changedFiles = 0, matches = 0, refused = 0;
    u16 *repl = units_of(replacement, &nrepl);

    if (repl == NULL) return @"Out of memory.";
    for (i = 0; i < [hitFiles count] && [self pumpIfDue]; i++) {
        NSString *file = [hitFiles objectAtIndex:i], *text;
        EditorDoc *doc;
        int eol, mixed;
        u16 *u, *out = NULL;
        unsigned int n, olen = 0, count;

        if (i % 10 == 0) [self say:[NSString stringWithFormat:@"Replacing... %u of %u files", i, (unsigned)[hitFiles count]]];
        text = [self textOfFile:file eol:&eol mixed:&mixed doc:&doc];
        if (text == nil || (doc == nil && mixed)) { refused++; continue; }
        u = units_of(text, &n);
        if (u == NULL) continue;
        count = grep_replace(s, u, n, repl, nrepl, literal, &out, &olen);
        free(u);
        if (count == 0) continue;
        {
            NSString *ns = [NSString stringWithCharacters:out length:olen];

            if (doc != nil) {
                [doc expandAllFolds];
                [doc replaceRange:NSMakeRange(0, [[[doc textView] string] length]) with:ns select:NSMakeRange(0, 0)];
            } else {
                NSData *enc = ui_utf8_cstring(ns);
                unsigned int en = [enc length] - 1;
                size_t outn = eol_expanded_size((const char *)[enc bytes], en, eol);
                char *buf = (char *)malloc(outn + 1);
                NSData *result;

                if (buf == NULL) { free(out); refused++; continue; }
                outn = eol_expand((const char *)[enc bytes], en, eol, buf);
                result = [NSData dataWithBytes:buf length:outn];
                free(buf);
                if (backups) [[NSData dataWithContentsOfFile:file] writeToFile:[file stringByAppendingString:@".bak"] atomically:YES];
                if (![result writeToFile:file atomically:YES]) { free(out); refused++; continue; }
            }
        }
        free(out);
        changedFiles++;
        matches += count;
    }
    free(repl);
    return [NSString stringWithFormat:@"Replaced %@ in %@%@.", plural(matches, @"match", @"matches"),
               plural(changedFiles, @"file", @"files"),
               refused > 0 ? [NSString stringWithFormat:@"; %u left alone (mixed line endings, or could not be written)", refused] : @""];
}

@end
