//
//  DGGopherMenuParser.m
//  DeGelato — fio 20
//

#import "DGGopherMenuParser.h"
#import "DGGopherItem.h"

@implementation DGGopherMenuParser

+ (NSString *)stringFromData:(NSData *)data
{
    if (data == nil) {
        return @"";
    }
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (s == nil) {
        // Many legacy Gopher servers are Latin-1; it never fails to decode.
        s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    }
    if (s == nil) {
        s = [[NSString alloc] initWithString:@""];
    }
    return [s autorelease];
}

+ (NSArray *)parseMenuData:(NSData *)data
{
    return [self parseMenu:[self stringFromData:data]];
}

+ (NSArray *)parseMenu:(NSString *)text
{
    NSMutableArray *items = [NSMutableArray array];
    if (text == nil) {
        return items;
    }

    // Split on LF; strip a trailing CR so CRLF and bare LF both work. (Don't use
    // a character set — that would collapse CRLF into an empty line.)
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    NSUInteger i, count = [lines count];
    for (i = 0; i < count; i++) {
        NSString *line = [lines objectAtIndex:i];
        if ([line hasSuffix:@"\r"]) {
            line = [line substringToIndex:[line length] - 1];
        }
        if ([line isEqualToString:@"."]) {
            break;      // RFC 1436 terminator
        }
        if ([line length] == 0) {
            continue;   // blank fragment (e.g. after a trailing newline)
        }

        unichar type = [line characterAtIndex:0];
        NSString *rest = [line substringFromIndex:1];
        NSArray *fields = [rest componentsSeparatedByString:@"\t"];
        NSUInteger nf = [fields count];

        NSString *display  = (nf > 0) ? [fields objectAtIndex:0] : @"";
        NSString *selector = (nf > 1) ? [fields objectAtIndex:1] : @"";
        NSString *host     = (nf > 2) ? [fields objectAtIndex:2] : @"";
        NSString *portStr  = (nf > 3) ? [fields objectAtIndex:3] : @"";

        NSInteger port = 70;
        if ([portStr length] > 0) {
            port = [portStr integerValue];
            if (port <= 0) { port = 70; }
        }

        [items addObject:[DGGopherItem itemWithType:type
                                            display:display
                                           selector:selector
                                               host:host
                                               port:port]];
    }
    return items;
}

@end
