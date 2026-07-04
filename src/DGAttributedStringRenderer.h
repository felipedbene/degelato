//
//  DGAttributedStringRenderer.h
//  DeGelato — fio 21
//
//  DGANSISpan[] -> NSAttributedString for the type-0 text viewer. The only
//  AppKit-touching piece of the ANSI pipeline. Ported from DeToca's
//  AttributedStringRenderer.
//

#import <Cocoa/Cocoa.h>

@interface DGAttributedStringRenderer : NSObject

+ (NSColor *)defaultForegroundColor;   // light, for the dark text-view background
+ (NSAttributedString *)attributedStringFromString:(NSString *)text font:(NSFont *)font;
+ (NSAttributedString *)attributedStringFromData:(NSData *)data font:(NSFont *)font;

@end
