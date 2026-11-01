#import "Appearance.h"
#import "HKSyntaxDefinition.h"
#import "HKSyntaxHighlighter.h"
#import "UIHelpers.h"

static BOOL dark = NO;
static NSColor *customBackground = nil;
static NSColor *customText = nil;
static NSString *fontName = nil;
static float fontSize = 0.0;
static NSString *includePath = nil;
static BOOL callTips = YES;
static BOOL reopenLast = NO;
static BOOL showAllFonts = NO;
#ifdef OPENSTEP
static int previewCharset = 1;                  /* NeXT's own RTF reader takes \'hh as NeXTSTEP encoding */
#else
static int previewCharset = 0;
#endif
static int previewLinks = 2;
static NSString *browserPath = nil;
static NSString *browserArgs = nil;
#define DEFAULT_BROWSER_PATH @"/LocalApps/OmniWeb.app"
static int remoteProgram = 0;
static NSString *remotePaths[2];
static NSString *remoteExtra = nil;
#define DEFAULT_STEPSSH_PATH @"/usr/local/bin/stepssh"
#define DEFAULT_OPENSSH_PATH @"/usr/local/bin/ssh"
static BOOL foldMargin = YES;

#define DEFAULT_INCLUDE_PATH @"/usr/include:/usr/local/include:/NextDeveloper/Headers:/LocalDeveloper/Headers:/NextLibrary/Frameworks:/LocalLibrary/Frameworks"

static NSString *color_string(NSColor *c)
{
    NSColor *rgb = [c colorUsingColorSpaceName:NSCalibratedRGBColorSpace];

    if (rgb == nil) return nil;
    return [NSString stringWithFormat:@"%.4f %.4f %.4f", (double)[rgb redComponent], (double)[rgb greenComponent], (double)[rgb blueComponent]];
}

static NSColor *color_from_string(NSString *s)
{
    NSScanner *sc;
    float r, g, b;

    if (s == nil) return nil;
    sc = [NSScanner scannerWithString:s];
    if ([sc scanFloat:&r] && [sc scanFloat:&g] && [sc scanFloat:&b])
        return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];
    return nil;
}

static BOOL get_bool(NSUserDefaults *ud, NSString *key, BOOL def)
{
    NSString *v = [ud stringForKey:key];

    return v == nil ? def : [v isEqualToString:@"YES"];
}

@implementation Appearance

/* A font the system lists can still be unusable (an incomplete install, a composite font), and laying text out in one has crashed the editor.
   So ask for the things drawing needs, and put the font in the editor only if they all make sense. */
+ (BOOL)fontUsable:(NSString *)name
{
    NSFont *f;
    float asc, desc, w;

    if (name == nil) return YES;
    f = [NSFont fontWithName:name size:12.0];
    if (f == nil) return NO;
    asc = [f ascender];
    desc = [f descender];
    w = [f widthOfString:@"Mi"];
    return asc - desc > 0.0 && asc - desc < 200.0 && w > 0.0 && w < 400.0;
}

+ (void)push
{
    NSString *use = fontName;

    if (use != nil && ![self fontUsable:use]) {
        SSTrace("font %s has no usable metrics; using the default font", SSCS(use));
        use = nil;
    }
    [HKSyntaxDefinition setDarkMode:dark];
    [HKSyntaxHighlighter setFontName:use size:fontSize];
}

+ (void)loadSettings
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *v;

    dark = [[ud stringForKey:@"Scheme"] isEqualToString:@"Dark"];
    [customBackground release];
    customBackground = [color_from_string([ud stringForKey:@"BackgroundRGB"]) retain];
    [customText release];
    customText = [color_from_string([ud stringForKey:@"TextRGB"]) retain];
    [fontName release];
    fontName = [[ud stringForKey:@"FontName"] copy];
    v = [ud stringForKey:@"FontSize"];
    fontSize = v != nil ? (float)[v floatValue] : 0.0;
    [includePath release];
    includePath = [[ud stringForKey:@"IncludePath"] copy];
    callTips = get_bool(ud, @"CallTips", YES);
    reopenLast = get_bool(ud, @"ReopenLastSession", NO);
    showAllFonts = get_bool(ud, @"ShowAllFonts", NO);
    [browserPath release];
    browserPath = [[ud stringForKey:@"BrowserPath"] copy];
    [browserArgs release];
    browserArgs = [[ud stringForKey:@"BrowserArgs"] copy];
    v = [ud stringForKey:@"PreviewCharset"];
    if (v != nil && [v intValue] >= 0 && [v intValue] <= 2) previewCharset = [v intValue];
    v = [ud stringForKey:@"PreviewLinks"];
    if (v != nil && [v intValue] >= 0 && [v intValue] <= 2) previewLinks = [v intValue];
    v = [ud stringForKey:@"RemoteProgram"];
    remoteProgram = (v != nil && [v intValue] == 1) ? 1 : 0;
    [remotePaths[0] release];
    remotePaths[0] = [[ud stringForKey:@"StepsshPath"] copy];
    [remotePaths[1] release];
    remotePaths[1] = [[ud stringForKey:@"OpensshPath"] copy];
    [remoteExtra release];
    remoteExtra = [[ud stringForKey:@"RemoteExtra"] copy];
    foldMargin = get_bool(ud, @"FoldMargin", YES);
    [self push];
}

+ (void)saveSettings
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    [ud setObject:dark ? @"Dark" : @"Light" forKey:@"Scheme"];
    if (customBackground != nil) [ud setObject:color_string(customBackground) forKey:@"BackgroundRGB"];
    else [ud removeObjectForKey:@"BackgroundRGB"];
    if (customText != nil) [ud setObject:color_string(customText) forKey:@"TextRGB"];
    else [ud removeObjectForKey:@"TextRGB"];
    if (fontName != nil) [ud setObject:fontName forKey:@"FontName"];
    else [ud removeObjectForKey:@"FontName"];
    [ud setObject:[NSString stringWithFormat:@"%g", fontSize] forKey:@"FontSize"];
    if (includePath != nil) [ud setObject:includePath forKey:@"IncludePath"];
    else [ud removeObjectForKey:@"IncludePath"];
    [ud setObject:callTips ? @"YES" : @"NO" forKey:@"CallTips"];
    [ud setObject:reopenLast ? @"YES" : @"NO" forKey:@"ReopenLastSession"];
    [ud setObject:showAllFonts ? @"YES" : @"NO" forKey:@"ShowAllFonts"];
    if (browserPath != nil) [ud setObject:browserPath forKey:@"BrowserPath"]; else [ud removeObjectForKey:@"BrowserPath"];
    if (browserArgs != nil) [ud setObject:browserArgs forKey:@"BrowserArgs"]; else [ud removeObjectForKey:@"BrowserArgs"];
    [ud setObject:[NSString stringWithFormat:@"%d", previewCharset] forKey:@"PreviewCharset"];
    [ud setObject:[NSString stringWithFormat:@"%d", previewLinks] forKey:@"PreviewLinks"];
    [ud setObject:[NSString stringWithFormat:@"%d", remoteProgram] forKey:@"RemoteProgram"];
    if (remotePaths[0] != nil) [ud setObject:remotePaths[0] forKey:@"StepsshPath"]; else [ud removeObjectForKey:@"StepsshPath"];
    if (remotePaths[1] != nil) [ud setObject:remotePaths[1] forKey:@"OpensshPath"]; else [ud removeObjectForKey:@"OpensshPath"];
    if (remoteExtra != nil) [ud setObject:remoteExtra forKey:@"RemoteExtra"]; else [ud removeObjectForKey:@"RemoteExtra"];
    [ud setObject:foldMargin ? @"YES" : @"NO" forKey:@"FoldMargin"];
    [ud synchronize];
}

+ (BOOL)dark { return dark; }

+ (void)setDark:(BOOL)flag
{
    dark = flag;
    [self resetColors];
    [self push];
}

+ (NSColor *)backgroundColor
{
    if (customBackground != nil) return customBackground;
    return dark ? [NSColor colorWithCalibratedRed:0.10 green:0.11 blue:0.13 alpha:1.0] : [NSColor whiteColor];
}

+ (NSColor *)textColor
{
    if (customText != nil) return customText;
    return dark ? [NSColor colorWithCalibratedRed:0.85 green:0.85 blue:0.85 alpha:1.0] : [NSColor blackColor];
}

+ (void)setBackgroundColor:(NSColor *)color
{
    [color retain];
    [customBackground release];
    customBackground = color;
}

+ (void)setTextColor:(NSColor *)color
{
    [color retain];
    [customText release];
    customText = color;
}

+ (void)resetColors
{
    [self setBackgroundColor:nil];
    [self setTextColor:nil];
}

/* The margin keeps to the scheme: a little away from the background. */
+ (NSColor *)gutterBackground
{
    return dark ? [NSColor colorWithCalibratedWhite:0.19 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.88 alpha:1.0];
}

+ (NSColor *)gutterText
{
    return dark ? [NSColor colorWithCalibratedWhite:0.62 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.35 alpha:1.0];
}

+ (NSColor *)foldMarkerColor
{
    return dark ? [NSColor colorWithCalibratedRed:0.55 green:0.75 blue:1.0 alpha:1.0] : [NSColor colorWithCalibratedRed:0.1 green:0.3 blue:0.7 alpha:1.0];
}

+ (NSString *)fontName { return fontName; }
+ (float)fontSize { return fontSize; }

+ (void)setFontName:(NSString *)name size:(float)size
{
    [fontName release];
    fontName = [name copy];
    fontSize = size;
    [self push];
}

+ (NSString *)includePath { return includePath != nil ? includePath : DEFAULT_INCLUDE_PATH; }

+ (void)setIncludePath:(NSString *)path
{
    [includePath release];
    includePath = [path length] > 0 ? [path copy] : nil;
}

+ (BOOL)callTips { return callTips; }
+ (void)setCallTips:(BOOL)flag { callTips = flag; }
+ (NSString *)browserPath { return browserPath != nil ? browserPath : DEFAULT_BROWSER_PATH; }
+ (void)setBrowserPath:(NSString *)path { [browserPath release]; browserPath = [path length] > 0 ? [path copy] : nil; }
+ (NSString *)browserArgs { return browserArgs != nil ? browserArgs : @""; }
+ (void)setBrowserArgs:(NSString *)args { [browserArgs release]; browserArgs = [args length] > 0 ? [args copy] : nil; }
+ (int)previewCharset { return previewCharset; }
+ (void)setPreviewCharset:(int)which { previewCharset = (which >= 0 && which <= 2) ? which : 0; }
+ (int)previewLinks { return previewLinks; }
+ (void)setPreviewLinks:(int)which { previewLinks = (which >= 0 && which <= 2) ? which : 2; }
+ (int)remoteProgram { return remoteProgram; }
+ (void)setRemoteProgram:(int)which { remoteProgram = which == 1 ? 1 : 0; }
+ (NSString *)remotePathFor:(int)which
{
    which = which == 1 ? 1 : 0;
    return remotePaths[which] != nil ? remotePaths[which] : (which == 1 ? DEFAULT_OPENSSH_PATH : DEFAULT_STEPSSH_PATH);
}
+ (void)setRemotePath:(NSString *)path for:(int)which
{
    which = which == 1 ? 1 : 0;
    [remotePaths[which] release];
    remotePaths[which] = [path length] > 0 ? [path copy] : nil;
}
+ (NSString *)remoteExtra { return remoteExtra != nil ? remoteExtra : @""; }
+ (void)setRemoteExtra:(NSString *)extra
{
    [remoteExtra release];
    remoteExtra = [extra length] > 0 ? [extra copy] : nil;
}
+ (BOOL)showAllFonts { return showAllFonts; }
+ (void)setShowAllFonts:(BOOL)flag { showAllFonts = flag; }
+ (BOOL)reopenLastSession { return reopenLast; }
+ (void)setReopenLastSession:(BOOL)flag { reopenLast = flag; }
+ (BOOL)foldMargin { return foldMargin; }
+ (void)setFoldMargin:(BOOL)flag { foldMargin = flag; }

@end
