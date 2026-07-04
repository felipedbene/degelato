//
//  DGANSITests.m
//  DeGelato — fio 21. xterm palette + ANSI SGR parser. Offline.
//

#import <SenTestingKit/SenTestingKit.h>
#import "DGANSIPalette.h"
#import "DGANSIParser.h"
#import "DGANSISpan.h"

@interface DGANSITests : SenTestCase
@end

@implementation DGANSITests

#pragma mark - Palette

- (void)testPaletteBase16
{
    DGANSIRGB black = [DGANSIPalette rgbForIndex:0];
    STAssertEquals((int)black.r + (int)black.g + (int)black.b, 0, @"0 = black");
    DGANSIRGB brightRed = [DGANSIPalette rgbForIndex:9];
    STAssertEquals((int)brightRed.r, 255, @"9 = bright red");
    STAssertEquals((int)brightRed.g, 0, @"bright red g");
    DGANSIRGB white = [DGANSIPalette rgbForIndex:15];
    STAssertEquals((int)white.r, 255, @"15 = bright white");
    STAssertEquals((int)white.b, 255, @"bright white b");
}

- (void)testPaletteCubeAndGray
{
    DGANSIRGB cube0 = [DGANSIPalette rgbForIndex:16];   // first cube = 0,0,0
    STAssertEquals((int)cube0.r + (int)cube0.g + (int)cube0.b, 0, @"cube base black");
    DGANSIRGB cubeMax = [DGANSIPalette rgbForIndex:231]; // last cube = 255,255,255
    STAssertEquals((int)cubeMax.r, 255, @"cube max r");
    DGANSIRGB gray0 = [DGANSIPalette rgbForIndex:232];   // 8,8,8
    STAssertEquals((int)gray0.r, 8, @"gray ramp start");
    DGANSIRGB gray23 = [DGANSIPalette rgbForIndex:255];  // 238,238,238
    STAssertEquals((int)gray23.r, 238, @"gray ramp end");
}

- (void)testPaletteClamps
{
    STAssertEquals((int)[DGANSIPalette rgbForIndex:-5].r, 0, @"negative -> 0 (black)");
    STAssertEquals((int)[DGANSIPalette rgbForIndex:999].r, 238, @"over 255 -> 255 (gray end)");
}

#pragma mark - Parser

- (void)testPlainText
{
    NSArray *s = [DGANSIParser spansFromString:@"hello"];
    STAssertEquals([s count], (NSUInteger)1, @"one span");
    DGANSISpan *sp = [s objectAtIndex:0];
    STAssertEqualObjects([sp text], @"hello", @"text");
    STAssertFalse([sp hasForeground], @"no color");
    STAssertFalse([sp bold], @"not bold");
}

- (void)testBasicColorAndReset
{
    NSArray *s = [DGANSIParser spansFromString:@"a\033[31mb\033[0mc"];
    STAssertEquals([s count], (NSUInteger)3, @"a / b / c");
    DGANSISpan *b = [s objectAtIndex:1];
    STAssertEqualObjects([b text], @"b", @"middle text");
    STAssertTrue([b hasForeground], @"b is colored");
    STAssertEquals((int)[b foreground].r, 128, @"red idx1 = 0x80");
    STAssertFalse([[s objectAtIndex:2] hasForeground], @"reset cleared color");
}

- (void)testBold
{
    NSArray *s = [DGANSIParser spansFromString:@"\033[1mX"];
    STAssertTrue([[s objectAtIndex:0] bold], @"bold on");
}

- (void)test256Color
{
    NSArray *s = [DGANSIParser spansFromString:@"\033[38;5;196mX"];
    DGANSISpan *sp = [s objectAtIndex:0];
    DGANSIRGB expect = [DGANSIPalette rgbForIndex:196];
    STAssertEquals((int)[sp foreground].r, (int)expect.r, @"256-color fg");
}

- (void)testTrueColor
{
    NSArray *s = [DGANSIParser spansFromString:@"\033[38;2;10;20;30mX"];
    DGANSISpan *sp = [s objectAtIndex:0];
    STAssertEquals((int)[sp foreground].r, 10, @"truecolor r");
    STAssertEquals((int)[sp foreground].g, 20, @"truecolor g");
    STAssertEquals((int)[sp foreground].b, 30, @"truecolor b");
}

// The fbterm "case 38" bug: after a 256-color intro, following params (here the
// bold "1") must still be applied, not swallowed.
- (void)testCase38DoesNotSwallowFollowingParams
{
    NSArray *s = [DGANSIParser spansFromString:@"\033[38;5;9;1mX"];
    DGANSISpan *sp = [s objectAtIndex:0];
    STAssertTrue([sp hasForeground], @"256-color applied");
    STAssertTrue([sp bold], @"the trailing ;1 (bold) is NOT swallowed");
}

- (void)testNonSGRStrippedTextKept
{
    // ESC[2J (clear) is stripped; the surrounding text stays, one span.
    NSArray *s = [DGANSIParser spansFromString:@"ab\033[2Jcd"];
    NSMutableString *all = [NSMutableString string];
    NSUInteger i;
    for (i = 0; i < [s count]; i++) { [all appendString:[[s objectAtIndex:i] text]]; }
    STAssertEqualObjects(all, @"abcd", @"non-SGR CSI stripped, text preserved");
}

- (void)testBraillePreserved
{
    NSArray *s = [DGANSIParser spansFromString:@"⠁⣿"];
    STAssertEqualObjects([[s objectAtIndex:0] text], @"⠁⣿", @"braille glyphs pass through");
}

- (void)testUnterminatedCSIStripped
{
    NSArray *s = [DGANSIParser spansFromString:@"ok\033[38;5"];
    STAssertEqualObjects([[s objectAtIndex:0] text], @"ok", @"unterminated CSI dropped");
}

@end
