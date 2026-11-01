#import "Compat.h"

@class EditorDoc;

/* EXPERIMENTAL: Windows > Unicode View shows the text of a document read-only in a window of its own, drawn by Pilcrow with FreeType from
 * font files you choose (Windows > Unicode View Fonts...), not by the system's text system -- so it can show Japanese, Korean, Chinese,
 * Greek, Cyrillic and so on from any TrueType/OpenType font, which the 4.2 text system cannot.  It follows the document half a second
 * after each edit.  Only built with FreeType (make FT=1). */
@interface UnicodeController : NSObject
{
    id              owner;               /* the AppController */
    NSMutableArray *items;               /* one per document that has a Unicode view */
}
- (id)initWithOwner:(id)anOwner;
- (BOOL)hasViewFor:(EditorDoc *)d;
- (void)toggleFor:(EditorDoc *)d;        /* open the view of this document, or close it */
- (void)documentChanged:(EditorDoc *)d;
- (void)documentClosed:(EditorDoc *)d;
- (void)chooseFonts;                     /* ask for the font files (the first is the main font); every view is drawn again */
@end
