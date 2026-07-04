//
//  DGFontManager.h
//  DeGelato — fio 1
//
//  Resolves the app's monospaced document font. The bundled Cascadia Code TTF
//  is registered automatically by the OS at launch via the ATSApplicationFontsPath
//  key in Info.plist (supported on 10.5) — so, unlike DeToca's 10.6 CTFontManager
//  path, there is no registration code here: we only look the face up by name and
//  fall back gracefully if it is somehow missing.
//

#import <Cocoa/Cocoa.h>

extern NSString * const DGDefaultFontName;   // @"Cascadia Code"

@interface DGFontManager : NSObject

// The document font at the default size, resolving Cascadia Code → Monaco →
// the system fixed-pitch font. Never returns nil.
+ (NSFont *)documentFontOfSize:(CGFloat)size;

// Convenience at the standard now-playing size.
+ (NSFont *)documentFont;

// YES when Cascadia Code actually resolved (for diagnostics/tests).
+ (BOOL)cascadiaAvailable;

@end
