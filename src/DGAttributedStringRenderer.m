//
//  DGAttributedStringRenderer.m
//  DeGelato — fio 21
//

#import "DGAttributedStringRenderer.h"
#import "DGANSIParser.h"
#import "DGANSISpan.h"
#import "DGANSIPalette.h"
#import "DGGopherMenuParser.h"

@implementation DGAttributedStringRenderer

// Light default so uncolored text is readable on the dark terminal-style
// background of the type-0 viewer (ANSI art assumes a dark terminal).
+ (NSColor *)defaultForegroundColor
{
    return [NSColor colorWithDeviceWhite:0.90 alpha:1.0];
}

+ (NSColor *)colorFromRGB:(DGANSIRGB)rgb
{
    return [NSColor colorWithDeviceRed:(rgb.r / 255.0)
                                green:(rgb.g / 255.0)
                                 blue:(rgb.b / 255.0)
                                alpha:1.0];
}

+ (NSAttributedString *)attributedStringFromData:(NSData *)data font:(NSFont *)font
{
    return [self attributedStringFromString:[DGGopherMenuParser stringFromData:data] font:font];
}

+ (NSAttributedString *)attributedStringFromString:(NSString *)text font:(NSFont *)font
{
    if (font == nil) {
        font = [NSFont userFixedPitchFontOfSize:12.0];
    }
    // Bold variant of the same face (Cascadia Code static Regular has no bold
    // member, so bold falls back to regular rather than a mismatched face that
    // would break braille alignment).
    NSFont *boldFont = [[NSFontManager sharedFontManager] convertFont:font
                                                          toHaveTrait:NSBoldFontMask];

    NSMutableAttributedString *result = [[[NSMutableAttributedString alloc] init] autorelease];

    NSArray *spans = [DGANSIParser spansFromString:text];
    NSUInteger i, n = [spans count];
    for (i = 0; i < n; i++) {
        DGANSISpan *span = [spans objectAtIndex:i];
        NSString *runText = [span text];
        if ([runText length] == 0) {
            continue;
        }

        NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
        [attrs setObject:([span bold] ? boldFont : font) forKey:NSFontAttributeName];
        if ([span hasForeground]) {
            [attrs setObject:[self colorFromRGB:[span foreground]] forKey:NSForegroundColorAttributeName];
        } else {
            [attrs setObject:[self defaultForegroundColor] forKey:NSForegroundColorAttributeName];
        }
        if ([span hasBackground]) {
            [attrs setObject:[self colorFromRGB:[span background]] forKey:NSBackgroundColorAttributeName];
        }

        NSAttributedString *piece = [[NSAttributedString alloc] initWithString:runText attributes:attrs];
        [result appendAttributedString:piece];
        [piece release];
    }
    return result;
}

@end
