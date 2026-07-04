//
//  DGPLSParser.m
//  DeGelato — fio 2
//

#import "DGPLSParser.h"

@implementation DGPLSParser

+ (BOOL)isAllDigits:(NSString *)s
{
    if ([s length] == 0) {
        return YES;   // "File=" with no index → treat as index 1
    }
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return ([s rangeOfCharacterFromSet:nonDigits].location == NSNotFound);
}

+ (NSString *)firstURLFromPlaylistText:(NSString *)text
{
    if (text == nil) {
        return nil;
    }

    NSArray *lines = [text componentsSeparatedByCharactersInSet:
                      [NSCharacterSet newlineCharacterSet]];
    NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];

    NSString *bestPLSURL = nil;
    NSInteger bestIndex = NSIntegerMax;
    NSString *firstBareURL = nil;

    NSUInteger i, n = [lines count];
    for (i = 0; i < n; i++) {
        NSString *line = [[lines objectAtIndex:i] stringByTrimmingCharactersInSet:ws];
        if ([line length] == 0) {
            continue;
        }
        NSString *low = [line lowercaseString];

        // PLS: File<n>=URL
        if ([low hasPrefix:@"file"]) {
            NSRange eq = [line rangeOfString:@"="];
            if (eq.location != NSNotFound && eq.location >= 4) {
                NSString *keyNum = [line substringWithRange:NSMakeRange(4, eq.location - 4)];
                if ([self isAllDigits:keyNum]) {
                    NSInteger idx = [keyNum integerValue];
                    if (idx == 0) {
                        idx = 1;
                    }
                    NSString *val = [[line substringFromIndex:eq.location + 1]
                                     stringByTrimmingCharactersInSet:ws];
                    if ([val length] > 0 && idx < bestIndex) {
                        bestIndex = idx;
                        bestPLSURL = val;
                    }
                    continue;
                }
            }
        }

        // M3U comments / directives.
        if ([line hasPrefix:@"#"]) {
            continue;
        }

        // Plain/Extended M3U: a bare URL line.
        if ([low hasPrefix:@"http://"] || [low hasPrefix:@"https://"]) {
            if (firstBareURL == nil) {
                firstBareURL = line;
            }
        }
    }

    if (bestPLSURL != nil) {
        return bestPLSURL;
    }
    return firstBareURL;
}

@end
