#import "Compat.h"

/* How the editor looks: the colour scheme (light or dark, with the background and text colours changeable), the font, and a
 * few settings that go with the Preferences panel (the include search path, call tips, the fold margin).  Everything is
 * class-level state, read from and saved to NSUserDefaults (as strings, the one form every release reads back alike). */
@interface Appearance : NSObject
+ (void)loadSettings;                                /* from the defaults, and tell the highlighter */
+ (void)saveSettings;
+ (BOOL)dark;
+ (void)setDark:(BOOL)flag;                    /* resets the background and text colours to the scheme's own */
+ (NSColor *)backgroundColor;
+ (NSColor *)textColor;
+ (void)setBackgroundColor:(NSColor *)color;   /* nil: the scheme's */
+ (void)setTextColor:(NSColor *)color;
+ (void)resetColors;
+ (NSColor *)gutterBackground;                 /* the line-number margin */
+ (NSColor *)gutterText;
+ (NSColor *)foldMarkerColor;
+ (NSString *)fontName;                        /* nil: the user's fixed-pitch font */
+ (float)fontSize;                             /* 0: the font's own */
+ (void)setFontName:(NSString *)name size:(float)size;
+ (NSString *)includePath;                     /* directories (colon separated) searched for #include files */
+ (void)setIncludePath:(NSString *)path;
+ (BOOL)callTips;
+ (void)setCallTips:(BOOL)flag;
+ (BOOL)reopenLastSession;                /* open the previous session's files at launch */
+ (void)setReopenLastSession:(BOOL)flag;
+ (BOOL)foldMargin;
+ (void)setFoldMargin:(BOOL)flag;
@end
