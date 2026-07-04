//
//  DGFontManager.m
//  DeGelato — fio 1
//

#import "DGFontManager.h"

NSString * const DGDefaultFontName = @"Cascadia Code";

#define DG_DEFAULT_FONT_SIZE 13.0

@implementation DGFontManager

+ (NSFont *)documentFontOfSize:(CGFloat)size
{
    NSFont *font = [NSFont fontWithName:DGDefaultFontName size:size];
    if (font != nil) {
        return font;
    }
    // Cascadia not present: fall back to a monospaced face that ships with 10.5.
    font = [NSFont fontWithName:@"Monaco" size:size];
    if (font != nil) {
        return font;
    }
    return [NSFont userFixedPitchFontOfSize:size];
}

+ (NSFont *)documentFont
{
    return [self documentFontOfSize:DG_DEFAULT_FONT_SIZE];
}

+ (BOOL)cascadiaAvailable
{
    return ([NSFont fontWithName:DGDefaultFontName size:DG_DEFAULT_FONT_SIZE] != nil);
}

@end
