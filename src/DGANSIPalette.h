//
//  DGANSIPalette.h
//  DeGelato — fio 21
//
//  The standard xterm 256-color palette: 16 base colors, a 6x6x6 color cube, and
//  24 grayscale steps. Pure Foundation (plain RGB byte triples); the AppKit layer
//  maps these to NSColor. Ported from DeToca's ANSIPalette.
//

#import <Foundation/Foundation.h>

typedef struct {
    unsigned char r;
    unsigned char g;
    unsigned char b;
} DGANSIRGB;

@interface DGANSIPalette : NSObject

// RGB for a palette index 0-255. Out-of-range indices are clamped.
+ (DGANSIRGB)rgbForIndex:(NSInteger)index;

@end
