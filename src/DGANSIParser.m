//
//  DGANSIParser.m
//  DeGelato — fio 21
//

#import "DGANSIParser.h"
#import "DGANSISpan.h"
#import "DGANSIPalette.h"

#define DG_ANSI_ESC 0x1B
#define DG_ANSI_BEL 0x07

// Emit the accumulated run (if any) as a span with the current attributes.
static void FlushRun(NSMutableArray *spans,
                     const unichar *runBuf, NSUInteger *runLen,
                     BOOL bold,
                     BOOL hasFG, DGANSIRGB fg,
                     BOOL hasBG, DGANSIRGB bg)
{
    if (*runLen == 0) {
        return;
    }
    DGANSISpan *span = [[DGANSISpan alloc] init];
    NSString *t = [[NSString alloc] initWithCharacters:runBuf length:*runLen];
    [span setText:t];
    [t release];
    [span setBold:bold];
    [span setHasForeground:hasFG];
    [span setForeground:fg];
    [span setHasBackground:hasBG];
    [span setBackground:bg];
    [spans addObject:span];
    [span release];
    *runLen = 0;
}

@implementation DGANSIParser

+ (NSArray *)spansFromString:(NSString *)text
{
    NSMutableArray *spans = [NSMutableArray array];
    if (text == nil) {
        return spans;
    }
    NSUInteger len = [text length];
    if (len == 0) {
        return spans;
    }

    unichar *chars = (unichar *)malloc(len * sizeof(unichar));
    unichar *runBuf = (unichar *)malloc(len * sizeof(unichar));
    if (chars == NULL || runBuf == NULL) {
        free(chars);
        free(runBuf);
        return spans;
    }
    [text getCharacters:chars range:NSMakeRange(0, len)];
    NSUInteger runLen = 0;

    BOOL bold = NO;
    BOOL hasFG = NO;  DGANSIRGB fg = {0, 0, 0};
    BOOL hasBG = NO;  DGANSIRGB bg = {0, 0, 0};

    NSUInteger i = 0;
    while (i < len) {
        unichar c = chars[i];

        if (c != DG_ANSI_ESC) {
            runBuf[runLen++] = c;
            i++;
            continue;
        }
        if (i + 1 >= len) {
            i++;
            break;   // lone trailing ESC
        }

        unichar next = chars[i + 1];

        if (next == '[') {
            // CSI: params/intermediates until a final byte (0x40-0x7E).
            NSUInteger j = i + 2;
            NSUInteger paramStart = j;
            while (j < len) {
                unichar b = chars[j];
                if (b >= 0x40 && b <= 0x7E) { break; }
                j++;
            }
            if (j >= len) {
                i = len;
                break;   // unterminated CSI
            }

            unichar finalByte = chars[j];
            if (finalByte == 'm') {
                FlushRun(spans, runBuf, &runLen, bold, hasFG, fg, hasBG, bg);

                NSString *paramStr = [[NSString alloc]
                    initWithCharacters:(chars + paramStart) length:(j - paramStart)];
                NSArray *parts = [paramStr componentsSeparatedByString:@";"];
                [paramStr release];

                NSUInteger np = [parts count];
                NSInteger *codes = (NSInteger *)malloc((np > 0 ? np : 1) * sizeof(NSInteger));
                NSUInteger p;
                for (p = 0; p < np; p++) {
                    codes[p] = [[parts objectAtIndex:p] integerValue];
                }
                // "ESC[m" -> one empty component -> reset.

                NSUInteger k = 0;
                while (k < np) {
                    NSInteger code = codes[k];
                    if (code == 0) {
                        bold = NO; hasFG = NO; hasBG = NO; k++;
                    } else if (code == 1) {
                        bold = YES; k++;
                    } else if (code == 22) {
                        bold = NO; k++;
                    } else if (code >= 30 && code <= 37) {
                        hasFG = YES; fg = [DGANSIPalette rgbForIndex:(code - 30)]; k++;
                    } else if (code == 39) {
                        hasFG = NO; k++;
                    } else if (code >= 40 && code <= 47) {
                        hasBG = YES; bg = [DGANSIPalette rgbForIndex:(code - 40)]; k++;
                    } else if (code == 49) {
                        hasBG = NO; k++;
                    } else if (code >= 90 && code <= 97) {
                        hasFG = YES; fg = [DGANSIPalette rgbForIndex:(code - 90 + 8)]; k++;
                    } else if (code >= 100 && code <= 107) {
                        hasBG = YES; bg = [DGANSIPalette rgbForIndex:(code - 100 + 8)]; k++;
                    } else if (code == 38 || code == 48) {
                        BOOL isFG = (code == 38);
                        // Consume extended-color sub-params exactly (fbterm case-38 fix).
                        if (k + 1 < np && codes[k + 1] == 5) {
                            if (k + 2 < np) {
                                DGANSIRGB rgb = [DGANSIPalette rgbForIndex:codes[k + 2]];
                                if (isFG) { hasFG = YES; fg = rgb; } else { hasBG = YES; bg = rgb; }
                            }
                            k += 3;
                        } else if (k + 1 < np && codes[k + 1] == 2) {
                            if (k + 4 < np) {
                                DGANSIRGB rgb;
                                rgb.r = (unsigned char)codes[k + 2];
                                rgb.g = (unsigned char)codes[k + 3];
                                rgb.b = (unsigned char)codes[k + 4];
                                if (isFG) { hasFG = YES; fg = rgb; } else { hasBG = YES; bg = rgb; }
                            }
                            k += 5;
                        } else {
                            k++;   // malformed intro: skip only this code
                        }
                    } else {
                        k++;   // unsupported SGR: ignore, keep attributes
                    }
                }
                free(codes);
            }
            // Non-SGR CSI: stripped, no state change, no flush.
            i = j + 1;
            continue;
        }
        else if (next == ']') {
            // OSC: strip until BEL or ST (ESC '\') or end.
            NSUInteger j = i + 2;
            while (j < len) {
                if (chars[j] == DG_ANSI_BEL) { j++; break; }
                if (chars[j] == DG_ANSI_ESC && j + 1 < len && chars[j + 1] == '\\') { j += 2; break; }
                j++;
            }
            i = j;
            continue;
        }
        else {
            i += 2;   // two-char escape / unknown: strip both
            continue;
        }
    }

    FlushRun(spans, runBuf, &runLen, bold, hasFG, fg, hasBG, bg);
    free(chars);
    free(runBuf);
    return spans;
}

@end
