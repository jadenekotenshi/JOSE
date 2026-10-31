#import "Compat.h"

/* The Preferences panel: colour scheme, colours, font, include path, call tips, fold margin.  Changes take effect at once in
 * every window and are saved. */
@interface PrefsController : NSObject
{
    id               owner;               /* the AppController: -appearanceChanged */
    NSPanel         *panel;
    NSPopUpButton   *schemePopup;
    NSColorWell     *backgroundWell;
    NSColorWell     *textWell;
    NSPopUpButton   *fontPopup;
    NSPopUpButton   *sizePopup;
    NSTextField     *pathField;
    NSButton        *tipsSwitch;
    NSButton        *marginSwitch;
    NSArray         *fixedFonts;          /* the names of the fixed-pitch fonts, found the first time the panel opens */
}
- (id)initWithOwner:(id)anOwner;
- (void)showPanel;
@end
