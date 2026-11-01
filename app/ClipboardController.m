#import "ClipboardController.h"
#import "AppController.h"
#import "EditorDoc.h"
#import "UIHelpers.h"
#include <stdlib.h>
#include <string.h>

@interface ClipboardController (Private)
- (void)buildPanel;
- (void)pasteButton:(id)sender;
- (void)currentButton:(id)sender;
- (void)deleteButton:(id)sender;
- (void)clearButton:(id)sender;
- (void)closeButton:(id)sender;
- (void)showSelected;
@end

@implementation ClipboardController

- (id)initWithOwner:(id)anOwner
{
    self = [super init];
    if (self) {
        owner = anOwner;
        clip_init(&ring);
        lastChange = -2;
    }
    return self;
}

- (void)dealloc
{
    clip_free(&ring);
    [super dealloc];
}

- (int)count { return ring.n; }

- (NSString *)previewAt:(int)i
{
    char buf[200];

    if (i < 0 || i >= ring.n) return @"";
    clip_preview(&ring, i, buf, sizeof buf, 50);
    return ui_string_from_utf8(buf);
}

- (void)note
{
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *s;
    NSData *enc;
    EditorDoc *d;

    if ([pb respondsToSelector:@selector(changeCount)]) {
        int cc = [pb changeCount];

        if (cc == lastChange) return;
        lastChange = cc;
    }
    if ([[pb types] indexOfObject:NSStringPboardType] == NSNotFound) return;
    s = [pb stringForType:NSStringPboardType];
    if (s == nil || [s length] == 0) return;
    enc = ui_utf8_cstring(s);
    d = [owner frontDocument];
    if (clip_add(&ring, (const char *)[enc bytes], [enc length] - 1, d != nil && [d pasteIsRectangle])) {
        if ([owner respondsToSelector:@selector(clipboardHistoryChanged)]) [owner clipboardHistoryChanged];
        [table reloadData];
    }
}

- (BOOL)makeCurrent:(int)i
{
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *s;

    if (i < 0 || i >= ring.n) return NO;
    s = ui_string_from_utf8(ring.item[i].text);
    [pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [pb setString:s forType:NSStringPboardType];
    if (ring.item[i].rect) [EditorDoc setRectClip:s];
    if ([pb respondsToSelector:@selector(changeCount)]) lastChange = [pb changeCount];       /* our own change: not a new copy */
    {
        NSData *enc = ui_utf8_cstring(s);

        clip_add(&ring, (const char *)[enc bytes], [enc length] - 1, ring.item[i].rect);          /* it moves to the front */
    }
    if ([owner respondsToSelector:@selector(clipboardHistoryChanged)]) [owner clipboardHistoryChanged];
    [table reloadData];
    return YES;
}

- (void)pasteEntry:(int)i
{
    EditorDoc *d = [owner frontDocument];

    if (d == nil || ![self makeCurrent:i]) { NSBeep(); return; }
    if ([[d window] isVisible]) [[d window] makeKeyAndOrderFront:nil];
    [[d window] makeFirstResponder:[d textView]];
    [[d textView] paste:nil];
}

/* ---- the panel ---- */

- (int)numberOfRowsInTableView:(NSTableView *)tv { return ring.n; }

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(int)row
{
    if (row < 0 || row >= ring.n) return @"";
    return [NSString stringWithFormat:@"%d  %@%@", row + 1, ring.item[row].rect ? @"[rectangle] " : @"", [self previewAt:row]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)n
{
    [self showSelected];
}

- (void)showSelected
{
    int row = [table selectedRow];
    NSString *full;

    if (row < 0 || row >= ring.n) { [detail setStringValue:@""]; return; }
    full = ui_string_from_utf8(ring.item[row].text);
    if ([full length] > 300) full = [[full substringToIndex:300] stringByAppendingString:@"..."];
    [detail setStringValue:[NSString stringWithFormat:@"%u characters.  %@", (unsigned)ring.item[row].len, full]];
}

- (void)buildPanel
{
    NSView *c;
    NSTableColumn *col;
    NSScrollView *sv;

    if (panel != nil) return;
    panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 480, 360)
                                       styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask)
                                         backing:NSBackingStoreBuffered defer:NO];
    [panel setTitle:@"Clipboard History"];
    [panel setReleasedWhenClosed:NO];
    [panel setMinSize:NSMakeSize(360, 260)];
    c = [panel contentView];
    table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 440, 200)] autorelease];
    col = [[[NSTableColumn alloc] initWithIdentifier:@"clip"] autorelease];
    [[col headerCell] setStringValue:@"Newest first (double-click to paste)"];
    [col setWidth:1200];
    [col setEditable:NO];
    [table addTableColumn:col];
    [table setDataSource:(id)self];
    [table setDelegate:(id)self];
    [table setAllowsMultipleSelection:NO];
    [table setTarget:self];
    [table setDoubleAction:@selector(pasteButton:)];
    sv = [[[NSScrollView alloc] initWithFrame:NSMakeRect(14, 120, 452, 226)] autorelease];
    [sv setHasVerticalScroller:YES];
    [sv setHasHorizontalScroller:YES];
    [sv setBorderType:NSBezelBorder];
    [sv setDocumentView:table];
    [sv setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [c addSubview:sv];
    detail = ui_wrapping_label(@"", NSMakeRect(14, 52, 452, 62), NO);
    [detail setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
    [c addSubview:detail];
    {
        NSButton *b;

        b = ui_button(@"Paste", NSMakeRect(14, 12, 76, 28), self, @selector(pasteButton:));
        [b setAutoresizingMask:(NSViewMaxXMargin | NSViewMaxYMargin)]; [c addSubview:b];
        b = ui_button(@"Make Current", NSMakeRect(94, 12, 104, 28), self, @selector(currentButton:));
        [b setAutoresizingMask:(NSViewMaxXMargin | NSViewMaxYMargin)]; [c addSubview:b];
        b = ui_button(@"Delete", NSMakeRect(202, 12, 70, 28), self, @selector(deleteButton:));
        [b setAutoresizingMask:(NSViewMaxXMargin | NSViewMaxYMargin)]; [c addSubview:b];
        b = ui_button(@"Clear All", NSMakeRect(276, 12, 80, 28), self, @selector(clearButton:));
        [b setAutoresizingMask:(NSViewMaxXMargin | NSViewMaxYMargin)]; [c addSubview:b];
        b = ui_button(@"Close", NSMakeRect(396, 12, 70, 28), self, @selector(closeButton:));
        [b setAutoresizingMask:(NSViewMinXMargin | NSViewMaxYMargin)]; [c addSubview:b];
    }
    [panel center];
}

- (void)showPanel
{
    [self note];
    [self buildPanel];
    [table reloadData];
    if (ring.n > 0) [table selectRow:0 byExtendingSelection:NO];
    [self showSelected];
    [panel makeKeyAndOrderFront:nil];
}

- (void)pasteButton:(id)sender
{
    int row = [table clickedRow];

    if (row < 0) row = [table selectedRow];
    [self pasteEntry:row];
}

- (void)currentButton:(id)sender
{
    int row = [table selectedRow];

    if ([self makeCurrent:row]) [table selectRow:0 byExtendingSelection:NO];
}

- (void)deleteButton:(id)sender
{
    int row = [table selectedRow];

    if (row < 0) return;
    clip_remove(&ring, row);
    [table reloadData];
    if (ring.n > 0) [table selectRow:(row < ring.n ? row : ring.n - 1) byExtendingSelection:NO];
    [self showSelected];
    if ([owner respondsToSelector:@selector(clipboardHistoryChanged)]) [owner clipboardHistoryChanged];
}

- (void)clearButton:(id)sender
{
    clip_free(&ring);
    [table reloadData];
    [self showSelected];
    if ([owner respondsToSelector:@selector(clipboardHistoryChanged)]) [owner clipboardHistoryChanged];
}

- (void)closeButton:(id)sender
{
    [panel orderOut:nil];
}

@end
