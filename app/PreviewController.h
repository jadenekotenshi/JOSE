#import "Compat.h"

@class EditorDoc;

/* Live Markdown preview: Windows > Markdown Preview opens a read-only window beside the document that shows its text as formatted
 * (headings, emphasis, lists, quotes, code, tables, links as "text (address)"), made with the Markdown-to-RTF converter of MarkStep.
 * It follows the document half a second after each edit, and keeps about the same place in the text as the document is scrolled to.
 * Which accent encoding the RTF uses and how links show are set in Preferences > Markdown. */
@interface PreviewController : NSObject
{
    id              owner;               /* the AppController */
    NSMutableArray *items;               /* one per document that has a preview */
}
- (id)initWithOwner:(id)anOwner;
- (BOOL)hasPreviewFor:(EditorDoc *)d;
- (void)toggleFor:(EditorDoc *)d;        /* open the preview of this document, or close it */
- (void)documentChanged:(EditorDoc *)d;  /* its text changed: the preview follows shortly (nothing if it has none) */
- (void)documentClosed:(EditorDoc *)d;
- (void)settingsChanged;                 /* the accent or link settings changed: every preview is made again */
- (NSString *)previewStringFor:(EditorDoc *)d;   /* the text the preview shows (for tests); nil if none */
- (void)refreshNowFor:(EditorDoc *)d;            /* make it again without waiting */
+ (BOOL)openURLString:(NSString *)url;   /* run the browser from Preferences > Markdown on this address (YES if it started); alerts if it cannot */
@end
