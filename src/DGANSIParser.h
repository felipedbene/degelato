//
//  DGANSIParser.h
//  DeGelato — fio 21
//
//  ANSI SGR state machine: text with escape sequences -> DGANSISpan[]. Supports
//  reset, bold on/off, basic/bright fg+bg, 256-color (38;5;n / 48;5;n) and
//  truecolor (38;2;r;g;b); strips every other CSI/OSC/escape. Keeps the fbterm
//  "case 38" fix (consumes extended-color sub-params exactly). Ported from
//  DeToca's ANSIParser. Pure Foundation.
//

#import <Foundation/Foundation.h>

@interface DGANSIParser : NSObject
+ (NSArray *)spansFromString:(NSString *)text;   // -> DGANSISpan[]
@end
