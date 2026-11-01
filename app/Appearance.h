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
+ (BOOL)fontUsable:(NSString *)name;          /* can the system give metrics for it?  (a font that cannot is never put in the editor) */
+ (NSString *)fontName;                        /* nil: the user's fixed-pitch font */
+ (float)fontSize;                             /* 0: the font's own */
+ (void)setFontName:(NSString *)name size:(float)size;
+ (NSString *)includePath;                     /* directories (colon separated) searched for #include files */
+ (void)setIncludePath:(NSString *)path;
+ (BOOL)callTips;
+ (void)setCallTips:(BOOL)flag;
+ (int)remoteProgram;                     /* what remote editing runs: 0 StepSSH's stepssh, 1 OpenSSH's ssh */
+ (void)setRemoteProgram:(int)which;
+ (NSString *)remotePathFor:(int)which;   /* where that program is (defaults: /usr/local/bin/stepssh, /usr/local/bin/ssh) */
+ (void)setRemotePath:(NSString *)path for:(int)which;
+ (NSString *)remoteExtra;                /* extra arguments for it (such as -p 2222), put before the host name */
+ (void)setRemoteExtra:(NSString *)extra;
+ (NSString *)browserPath;                /* what a click on a link in the Markdown preview runs: an .app (its executable is used) or a program */
+ (void)setBrowserPath:(NSString *)path;
+ (NSString *)browserArgs;                /* arguments before the address; "%u" in them stands for the address (else it is added last) */
+ (void)setBrowserArgs:(NSString *)args;
+ (int)previewCharset;                    /* how the Markdown preview writes accents: 0 Windows-1252, 1 NeXTSTEP, 2 \\u escapes only */
+ (void)setPreviewCharset:(int)which;
+ (int)previewLinks;                      /* what a link shows in the preview: 0 its text, 1 its address, 2 "text (address)" */
+ (void)setPreviewLinks:(int)which;
+ (BOOL)showAllFonts;                      /* list every font in Preferences, not only the fixed-pitch ones (composite CJK fonts are not) */
+ (void)setShowAllFonts:(BOOL)flag;
+ (BOOL)reopenLastSession;                /* open the previous session's files at launch */
+ (void)setReopenLastSession:(BOOL)flag;
+ (BOOL)foldMargin;
+ (void)setFoldMargin:(BOOL)flag;
@end
