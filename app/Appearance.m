#import "Appearance.h"
#import "HKSyntaxDefinition.h"
#import "HKSyntaxHighlighter.h"

static BOOL dark = NO;
static NSColor *customBackground = nil;
static NSColor *customText = nil;
static NSString *fontName = nil;
static float fontSize = 0.0;
static NSString *includePath = nil;
static BOOL callTips = YES;
static BOOL reopenLast = NO;
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

+ (void)push
{
    [HKSyntaxDefinition setDarkMode:dark];
    [HKSyntaxHighlighter setFontName:fontName size:fontSize];
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
+ (BOOL)reopenLastSession { return reopenLast; }
+ (void)setReopenLastSession:(BOOL)flag { reopenLast = flag; }
+ (BOOL)foldMargin { return foldMargin; }
+ (void)setFoldMargin:(BOOL)flag { foldMargin = flag; }

@end
