//
//  DGGopherResource.m
//  DeGelato — fio 20
//

#import "DGGopherResource.h"
#import "DGGopherItem.h"

@implementation DGGopherResource

@synthesize host = _host;
@synthesize port = _port;
@synthesize type = _type;
@synthesize selector = _selector;
@synthesize displayString = _displayString;

+ (id)resourceWithHost:(NSString *)host
                  port:(NSInteger)port
                  type:(unichar)type
              selector:(NSString *)selector
               display:(NSString *)display
{
    DGGopherResource *r = [[[self alloc] init] autorelease];
    [r setHost:host];
    [r setPort:(port > 0 ? port : 70)];
    [r setType:type];
    [r setSelector:(selector ? selector : @"")];
    [r setDisplayString:display];
    return r;
}

+ (id)resourceWithItem:(DGGopherItem *)item
{
    return [self resourceWithHost:[item host]
                             port:[item port]
                             type:[item type]
                         selector:[item selector]
                          display:[item displayString]];
}

+ (id)resourceFromLocationString:(NSString *)location
{
    if (location == nil) {
        return nil;
    }
    NSString *s = [location stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s length] == 0) {
        return nil;
    }

    // Any scheme is treated as gopher for parsing purposes.
    NSRange schemeRange = [s rangeOfString:@"://"];
    if (schemeRange.location != NSNotFound) {
        s = [s substringFromIndex:schemeRange.location + schemeRange.length];
    }
    if ([s length] == 0) {
        return nil;
    }

    // Split authority (host[:port]) from path at the first '/'.
    NSString *authority = s;
    NSString *path = @"";
    NSRange slash = [s rangeOfString:@"/"];
    if (slash.location != NSNotFound) {
        authority = [s substringToIndex:slash.location];
        path = [s substringFromIndex:slash.location + 1];
    }
    if ([authority length] == 0) {
        return nil;
    }

    NSString *host = authority;
    NSInteger port = 70;
    NSRange colon = [authority rangeOfString:@":"];
    if (colon.location != NSNotFound) {
        host = [authority substringToIndex:colon.location];
        NSInteger p = [[authority substringFromIndex:colon.location + 1] integerValue];
        if (p > 0) { port = p; }
    }
    if ([host length] == 0) {
        return nil;
    }

    // First path char is the item type; the rest is the selector. No path ->
    // the root menu (type '1').
    unichar type = '1';
    NSString *selector = @"";
    if ([path length] > 0) {
        type = [path characterAtIndex:0];
        selector = [path substringFromIndex:1];
    }

    return [self resourceWithHost:host port:port type:type
                         selector:selector display:host];
}

- (void)dealloc
{
    [_host release];
    [_selector release];
    [_displayString release];
    [super dealloc];
}

- (NSString *)locationSummary
{
    NSString *sel = (_selector ? _selector : @"");
    NSString *path = [sel hasPrefix:@"/"] ? sel : [@"/" stringByAppendingString:sel];
    return [NSString stringWithFormat:@"%@:%ld%@", (_host ? _host : @""), (long)_port, path];
}

- (NSString *)urlString
{
    return [NSString stringWithFormat:@"gopher://%@:%ld/%C%@",
            (_host ? _host : @""), (long)_port, _type, (_selector ? _selector : @"")];
}

@end
