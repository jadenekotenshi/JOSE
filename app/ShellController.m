#import "ShellController.h"
#import "EditorDoc.h"
#import "UIHelpers.h"
#include "shellrun.h"
#include <stdlib.h>
#include <string.h>

#define TIMEOUT_MS 60000U
#define MAX_OUTPUT (64UL * 1024UL * 1024UL)

@interface ShellController (Private)
- (NSString *)askCommandWithTitle:(NSString *)title prompt:(NSString *)prompt key:(NSString *)key;
- (BOOL)run:(NSString *)command input:(NSString *)input in:(EditorDoc *)doc result:(NSString **)output;
- (void)filter:(NSString *)command in:(EditorDoc *)doc;
- (void)commandOK:(id)sender;
- (void)commandCancel:(id)sender;
@end

@implementation ShellController

- (id)initWithOwner:(id)anOwner
{
    self = [super init];
    if (self) owner = anOwner;
    return self;
}

- (void)commandOK:(id)sender
{
    accepted = YES;
    [NSApp stopModalWithCode:NSOKButton];
}

- (void)commandCancel:(id)sender
{
    accepted = NO;
    [NSApp stopModalWithCode:NSCancelButton];
}

/* A small modal panel with one field, which starts with the last command given under `key`.  nil if cancelled or empty. */
- (NSString *)askCommandWithTitle:(NSString *)title prompt:(NSString *)prompt key:(NSString *)key
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *last = [ud stringForKey:key];
    NSString *cmd = nil;
    int result;

    panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 420, 112)
                                       styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                         backing:NSBackingStoreBuffered defer:NO];
    [panel setTitle:title];
    [[panel contentView] addSubview:ui_label(prompt, NSMakeRect(16, 82, 388, 18))];
    field = ui_field(NSMakeRect(16, 54, 388, 22));
    if (last != nil) [field setStringValue:last];
    [field setTarget:self];
    [field setAction:@selector(commandOK:)];
    [[panel contentView] addSubview:field];
    [[panel contentView] addSubview:ui_button(@"OK", NSMakeRect(334, 12, 70, 28), self, @selector(commandOK:))];
    [[panel contentView] addSubview:ui_button(@"Cancel", NSMakeRect(254, 12, 70, 28), self, @selector(commandCancel:))];
    [panel center];
    [panel makeFirstResponder:field];
    accepted = NO;
    result = [NSApp runModalForWindow:panel];
    if (result == NSOKButton && accepted) cmd = ui_trim([field stringValue]);
    [panel close];
    [panel release];
    panel = nil;
    field = nil;
    if (cmd == nil || [cmd length] == 0) return nil;
    [ud setObject:cmd forKey:key];
    [ud synchronize];
    return cmd;
}

/* Runs `command` with `input` as its standard input.  YES (and *output) if it succeeded; otherwise the reason has been shown. */
- (BOOL)run:(NSString *)command input:(NSString *)input in:(EditorDoc *)doc result:(NSString **)output
{
    NSData *in = input != nil ? ui_utf8_cstring(input) : nil;
    ShellResult r;
    BOOL ok = NO;

    if (!shell_run(UI_CPATH(command), UI_CPATH([doc workingDirectory]), in != nil ? (const char *)[in bytes] : NULL,
                   in != nil ? [in length] - 1 : 0, TIMEOUT_MS, MAX_OUTPUT, &r)) {
        NSRunAlertPanel(@"Shell", @"The command could not be started.", @"OK", nil, nil);
    } else if (r.timed_out) {
        NSRunAlertPanel(@"Shell", @"The command ran for more than a minute and was stopped. The text is unchanged.", @"OK", nil, nil);
    } else if (r.truncated) {
        NSRunAlertPanel(@"Shell", @"The command wrote more than 64 MB. The text is unchanged.", @"OK", nil, nil);
    } else {
        if (r.status != 0 || r.nerr > 0) {
            NSString *msg = r.nerr > 0 ? ui_string_from_utf8(r.err) : @"";

            if ([msg length] > 1500) msg = [msg substringToIndex:1500];
            if (r.status != 0) {
                NSRunAlertPanel(@"Shell", @"The command failed (status %d).\n\n%@\n\nThe text is unchanged.", @"OK", nil, nil, r.status, msg);
            } else {
                NSRunAlertPanel(@"Shell", @"The command printed this on its error output:\n\n%@", @"OK", nil, nil, msg);
                ok = YES;
            }
        } else {
            ok = YES;
        }
        if (r.status == 0) ok = YES;
        if (ok) *output = ui_string_from_utf8(r.out);
    }
    shell_result_free(&r);
    return ok;
}

/* The selection (the whole text if there is none) goes through `command` and is replaced by what comes out. */
- (void)filter:(NSString *)command in:(EditorDoc *)doc
{
    NSTextView *tv = [doc textView];
    NSRange sel = [tv selectedRange];
    NSString *text = [tv string], *input, *output = nil;
    NSRange region = sel.length > 0 ? sel : NSMakeRange(0, [text length]);
    BOOL endsInNewline;

    input = [text substringWithRange:region];
    endsInNewline = [input length] > 0 && [input characterAtIndex:[input length] - 1] == '\n';
    if (![self run:command input:input in:doc result:&output]) return;
    /* a filter that ends its output with a newline that the selection did not have should not add one */
    if (!endsInNewline && [output length] > 0 && [output characterAtIndex:[output length] - 1] == '\n')
        output = [output substringToIndex:[output length] - 1];
    if ([output isEqualToString:input]) return;
    [doc replaceRange:region with:output select:NSMakeRange(region.location, [output length])];
}

- (void)filterSelection
{
    EditorDoc *d = [owner frontDocument];
    NSString *cmd;

    if (d == nil) return;
    cmd = [self askCommandWithTitle:@"Filter Selection" prompt:@"Pass the selection (or all the text) through:" key:@"ShellFilterCommand"];
    if (cmd != nil) [self filter:cmd in:d];
}

- (void)sortLines
{
    EditorDoc *d = [owner frontDocument];

    if (d != nil) [self filter:@"sort" in:d];
}

- (void)executeCommand
{
    EditorDoc *d = [owner frontDocument];
    NSString *cmd, *output = nil;
    NSRange sel;

    if (d == nil) return;
    cmd = [self askCommandWithTitle:@"Execute Command" prompt:@"Insert the output of:" key:@"ShellExecCommand"];
    if (cmd == nil) return;
    if (![self run:cmd input:nil in:d result:&output]) return;
    if ([output length] == 0) return;
    sel = [[d textView] selectedRange];
    [d replaceRange:sel with:output select:NSMakeRange(sel.location + [output length], 0)];
}

@end
