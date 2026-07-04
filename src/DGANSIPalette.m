//
//  DGANSIPalette.m
//  DeGelato — fio 21
//

#import "DGANSIPalette.h"

// The 16 base colors (xterm defaults). 0-7 normal, 8-15 bright.
static const DGANSIRGB kBase16[16] = {
    {0x00, 0x00, 0x00}, {0x80, 0x00, 0x00}, {0x00, 0x80, 0x00}, {0x80, 0x80, 0x00},
    {0x00, 0x00, 0x80}, {0x80, 0x00, 0x80}, {0x00, 0x80, 0x80}, {0xc0, 0xc0, 0xc0},
    {0x80, 0x80, 0x80}, {0xff, 0x00, 0x00}, {0x00, 0xff, 0x00}, {0xff, 0xff, 0x00},
    {0x00, 0x00, 0xff}, {0xff, 0x00, 0xff}, {0x00, 0xff, 0xff}, {0xff, 0xff, 0xff}
};

@implementation DGANSIPalette

+ (DGANSIRGB)rgbForIndex:(NSInteger)index
{
    if (index < 0)   { index = 0; }
    if (index > 255) { index = 255; }

    if (index < 16) {
        return kBase16[index];
    }

    if (index < 232) {
        // 6x6x6 cube. Level v in 0..5 -> 0 for v==0, else 55 + v*40.
        NSInteger n = index - 16;
        NSInteger ri = (n / 36) % 6;
        NSInteger gi = (n / 6) % 6;
        NSInteger bi = n % 6;
        DGANSIRGB c;
        c.r = (unsigned char)(ri == 0 ? 0 : 55 + ri * 40);
        c.g = (unsigned char)(gi == 0 ? 0 : 55 + gi * 40);
        c.b = (unsigned char)(bi == 0 ? 0 : 55 + bi * 40);
        return c;
    }

    // Grayscale ramp: 24 steps from 8 to 238 in increments of 10.
    NSInteger level = 8 + (index - 232) * 10;
    DGANSIRGB c;
    c.r = (unsigned char)level;
    c.g = (unsigned char)level;
    c.b = (unsigned char)level;
    return c;
}

@end
