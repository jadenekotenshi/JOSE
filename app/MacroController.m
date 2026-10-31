#import "MacroController.h"
#import "EditorDoc.h"
#import "AppController.h"
#import "FindController.h"
#import "ShellController.h"
#import "UIHelpers.h"
#include "macro.h"
#include <stdlib.h>
#include <string.h>

/* The actions of the text view that a macro may contain: keys, not anything that could do harm if a macro file named it. */
static const char *const actions[] = {
    "insertNewline:", "insertTab:", "insertBacktab:", "deleteBackward:", "deleteForward:", "delete:", "deleteWordBackward:", "deleteWordForward:", "deleteToBeginningOfLine:", "deleteToEndOfLine:", "moveUp:", "moveDown:", "moveLeft:", "moveRight:", "moveBackward:", "moveForward:", "moveWordBackward:", "moveWordForward:", "moveWordLeft:", "moveWordRight:", "moveToBeginningOfLine:", "moveToEndOfLine:", "moveToBeginningOfParagraph:", "moveToEndOfParagraph:", "moveToBeginningOfDocument:", "moveToEndOfDocument:", "pageUp:", "pageDown:", "moveUpAndModifySelection:", "moveDownAndModifySelection:", "moveLeftAndModifySelection:", "moveRightAndModifySelection:", "moveWordBackwardAndModifySelection:", "moveWordForwardAndModifySelection:", "moveToBeginningOfLineAndModifySelection:", "moveToEndOfLineAndModifySelection:", "selectAll:", "selectLine:", "selectWord:", "copy:", "cut:", "paste:",
    NULL
};

#define MAX_REPEATS 1000000
#define MAX_LINES 100000

/* Macro files are UTF-8 text. */
static NSString *read_text(NSString *path)
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSMutableData *z;

    if (data == nil) return nil;
    z = [NSMutableData dataWithData:data];
    [z appendBytes:"" length:1];
    return ui_string_from_utf8((const char *)[z bytes]);
}

static BOOL write_text(NSString *text, NSString *path)
{
    NSData *enc = ui_utf8_cstring(text);                /* with a NUL that is not written */

    return [[NSData dataWithBytes:[enc bytes] length:[enc length] - 1] writeToFile:path atomically:YES];
}

@interface MacroController (Private)
- (void)addLine:(NSString *)line;
- (void)flushInsert;
- (NSString *)quoted:(NSString *)s;
- (BOOL)runOp:(MacroOp *)op in:(EditorDoc *)d;
- (void)repeatOK:(id)sender;
- (void)repeatCancel:(id)sender;
- (void)saveLastToDisk;
@end

@implementation MacroController

- (id)initWithOwner:(id)anOwner
{
    self = [super init];
    if (self) {
        owner = anOwner;
        lines = [[NSMutableArray alloc] init];
        pendingInsert = [[NSMutableString alloc] init];
        folder = [[NSHomeDirectory() stringByAppendingPathComponent:@".JOSE.macros"] retain];
        /* the macro learned last time, if any */
        {
            NSString *text = read_text([folder stringByAppendingPathComponent:@".last"]);
            if (text != nil) last = [[text componentsSeparatedByString:@"\n"] retain];
        }
    }
    return self;
}

- (void)dealloc
{
    [lines release];
    [pendingInsert release];
    [last release];
    [folder release];
    [repeatPanel release];
    [super dealloc];
}

- (BOOL)recording { return recording; }
- (BOOL)replaying { return replaying; }
- (BOOL)hasMacro { return last != nil && [last count] > 0; }
- (NSString *)folderPath { return folder; }

- (void)setFolderPath:(NSString *)path
{
    [folder release];
    folder = [path copy];
}

- (BOOL)isRecordableAction:(NSString *)name
{
    const char *c = [name cString];
    int i;

    for (i = 0; actions[i] != NULL; i++) if (strcmp(actions[i], c) == 0) return YES;
    return NO;
}

/* ---- learning ---- */

- (NSString *)quoted:(NSString *)s
{
    char *q = macro_quote(UI_CPATH(s));
    NSString *r;

    if (q == NULL) return @"\"\"";
    r = ui_string_from_utf8(q);                          /* non-ASCII bytes pass through, so decode them as UTF-8 */
    free(q);
    return r;
}

- (void)addLine:(NSString *)line
{
    [self flushInsert];
    [lines addObject:line];
}

- (void)flushInsert
{
    if ([pendingInsert length] > 0) {
        [lines addObject:[NSString stringWithFormat:@"insert %@", [self quoted:pendingInsert]]];
        [pendingInsert setString:@""];
    }
}

- (void)toggleLearning
{
    if (recording) {
        [self flushInsert];
        recording = NO;
        [last release];
        last = [[NSArray arrayWithArray:lines] retain];
        [self saveLastToDisk];
    } else {
        if (replaying) { NSBeep(); return; }
        [lines removeAllObjects];
        [pendingInsert setString:@""];
        recording = YES;
    }
}

- (void)noteInsert:(NSString *)text
{
    if (!recording || replaying || [text length] == 0) return;
    [pendingInsert appendString:text];
}

- (void)noteAction:(NSString *)name
{
    if (!recording || replaying || ![self isRecordableAction:name]) return;
    [self addLine:[NSString stringWithFormat:@"action %@", name]];
}

- (void)noteCommand:(NSString *)name
{
    if (!recording || replaying) return;
    [self addLine:[NSString stringWithFormat:@"command %@", name]];
}

- (void)noteFind:(NSString *)pattern flags:(NSString *)flags
{
    if (!recording || replaying) return;
    [self addLine:[NSString stringWithFormat:@"find %@ %@", flags, [self quoted:pattern]]];
}

- (void)noteReplace:(NSString *)verb pattern:(NSString *)pattern replacement:(NSString *)replacement flags:(NSString *)flags
{
    if (!recording || replaying) return;
    [self addLine:[NSString stringWithFormat:@"%@ %@ %@ %@", verb, flags, [self quoted:pattern], [self quoted:replacement]]];
}

- (void)noteFilter:(NSString *)verb command:(NSString *)command
{
    if (!recording || replaying) return;
    [self addLine:[NSString stringWithFormat:@"%@ %@", verb, [self quoted:command]]];
}

/* ---- running ---- */

- (BOOL)runOp:(MacroOp *)op in:(EditorDoc *)d
{
    NSTextView *tv = [d textView];
    FindController *finder = [owner finder];
    NSString *s1 = op->s1 != NULL ? ui_string_from_utf8(op->s1) : nil, *s2 = op->s2 != NULL ? ui_string_from_utf8(op->s2) : nil;
    NSString *word = [NSString stringWithCString:op->word];

    switch (op->kind) {
    case MOP_INSERT:
        [tv insertText:s1];
        return YES;
    case MOP_ACTION:
        if ([self isRecordableAction:word] && [tv respondsToSelector:NSSelectorFromString(word)]) {
            [tv performSelector:NSSelectorFromString(word) withObject:nil];
            return YES;
        }
        return NO;
    case MOP_COMMAND:
        return [owner macroCommand:word];
    case MOP_FIND:
        return [finder macroFind:s1 flags:word];
    case MOP_REPLACE:
        return [finder macroReplaceKind:0 pattern:s1 replacement:s2 flags:word];
    case MOP_REPLACE_ALL:
        return [finder macroReplaceKind:1 pattern:s1 replacement:s2 flags:word];
    case MOP_REPLACE_SEL:
        return [finder macroReplaceKind:2 pattern:s1 replacement:s2 flags:word];
    case MOP_FILTER:
        return [[owner shellController] macroFilter:s1];
    case MOP_EXEC:
        return [[owner shellController] macroExecute:s1];
    default:
        return YES;
    }
}

/* Runs the lines in the front window.  NO if one of them could not be done (a search that finds nothing, a line that is not
 * valid): the macro stops there. */
- (BOOL)runLines:(NSArray *)macroLines
{
    EditorDoc *d = [owner frontDocument];
    unsigned int i;
    BOOL ok = YES;

    if (d == nil || recording || replaying) { NSBeep(); return NO; }
    replaying = YES;
    NS_DURING
        for (i = 0; i < [macroLines count] && ok; i++) {
            MacroOp op;
            char err[100];

            if (macro_parse_line(UI_CPATH([macroLines objectAtIndex:i]), &op, err, sizeof err) != 0) {
                NSRunAlertPanel(@"Macro", @"Line %u: %s", @"OK", nil, nil, i + 1, err);
                ok = NO;
                break;
            }
            ok = [self runOp:&op in:d];
            macro_op_free(&op);
        }
    NS_HANDLER
        SSTrace("macro: %s -- %s", SSCS([localException name]), SSCS([localException reason]));
        ok = NO;
    NS_ENDHANDLER
    replaying = NO;
    if (!ok) NSBeep();
    return ok;
}

- (BOOL)replay
{
    if (![self hasMacro]) { NSBeep(); return NO; }
    return [self runLines:last];
}

- (void)repeatOK:(id)sender { accepted = YES; [NSApp stopModalWithCode:NSOKButton]; }
- (void)repeatCancel:(id)sender { accepted = NO; [NSApp stopModalWithCode:NSCancelButton]; }

- (void)repeatDialog
{
    int n = 1;
    BOOL until = NO;
    EditorDoc *d = [owner frontDocument];

    if (d == nil || ![self hasMacro]) { NSBeep(); return; }
    repeatPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 330, 130)
                                             styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                               backing:NSBackingStoreBuffered defer:NO];
    [repeatPanel setTitle:@"Repeat Macro"];
    [[repeatPanel contentView] addSubview:ui_label(@"Repeat it this many times:", NSMakeRect(16, 96, 180, 18))];
    repeatField = ui_field(NSMakeRect(204, 94, 106, 22));
    [repeatField setStringValue:@"10"];
    [[repeatPanel contentView] addSubview:repeatField];
    untilSwitch = ui_switch(@"Until it fails (a search finds nothing)", NSMakeRect(16, 64, 300, 20));
    [[repeatPanel contentView] addSubview:untilSwitch];
    [[repeatPanel contentView] addSubview:ui_button(@"Repeat", NSMakeRect(240, 12, 70, 28), self, @selector(repeatOK:))];
    [[repeatPanel contentView] addSubview:ui_button(@"Cancel", NSMakeRect(160, 12, 70, 28), self, @selector(repeatCancel:))];
    [repeatPanel center];
    [repeatPanel makeFirstResponder:repeatField];
    accepted = NO;
    [NSApp runModalForWindow:repeatPanel];
    if (accepted) {
        n = [[repeatField stringValue] intValue];
        until = [untilSwitch state] == NSOnState;
    }
    [repeatPanel close];
    [repeatPanel release];
    repeatPanel = nil;
    if (!accepted) return;
    if (n < 1) n = 1;
    if (n > MAX_REPEATS) n = MAX_REPEATS;
    {
        int i;
        for (i = 0; i < (until ? MAX_REPEATS : n); i++) {
            NSRange before = [[d textView] selectedRange];
            unsigned int lenBefore = [[[d textView] string] length];

            if (![self runLines:last]) break;
            if (until) {                                  /* a pass that changed nothing would go on for ever */
                NSRange after = [[d textView] selectedRange];
                if (after.location == before.location && after.length == before.length && [[[d textView] string] length] == lenBefore) break;
            }
        }
    }
}

- (NSString *)lastAsText
{
    return last != nil ? [[last componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] : @"";
}

/* ---- saved macros ---- */

- (void)saveLastToDisk
{
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir;

    if (![fm fileExistsAtPath:folder isDirectory:&isDir]) [fm createDirectoryAtPath:folder attributes:nil];
    write_text([self lastAsText], [folder stringByAppendingPathComponent:@".last"]);
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

- (BOOL)saveLastAs:(NSString *)name
{
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir;

    name = ui_trim(name);
    if ([name length] == 0 || [name rangeOfString:@"/"].length > 0 || [name characterAtIndex:0] == '.' || ![self hasMacro]) return NO;
    if (![fm fileExistsAtPath:folder isDirectory:&isDir]) [fm createDirectoryAtPath:folder attributes:nil];
    return write_text([@"# JOSE macro\n" stringByAppendingString:[self lastAsText]], [folder stringByAppendingPathComponent:name]);
}

- (BOOL)runSaved:(NSString *)name
{
    NSString *text = read_text([folder stringByAppendingPathComponent:name]);

    if (text == nil) { NSBeep(); return NO; }
    return [self runLines:[text componentsSeparatedByString:@"\n"]];
}

@end
