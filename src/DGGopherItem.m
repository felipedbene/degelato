//
//  DGGopherItem.m
//  DeGelato — fio 20
//

#import "DGGopherItem.h"

@implementation DGGopherItem

@synthesize type = _type;
@synthesize displayString = _displayString;
@synthesize selector = _selector;
@synthesize host = _host;
@synthesize port = _port;

+ (id)itemWithType:(unichar)type
            display:(NSString *)display
           selector:(NSString *)selector
               host:(NSString *)host
               port:(NSInteger)port
{
    DGGopherItem *item = [[[self alloc] init] autorelease];
    [item setType:type];
    [item setDisplayString:display];
    [item setSelector:selector];
    [item setHost:host];
    [item setPort:port];
    return item;
}

- (void)dealloc
{
    [_displayString release];
    [_selector release];
    [_host release];
    [super dealloc];
}

- (DGGopherItemKind)kind
{
    switch (_type) {
        case '0': return DGGopherItemKindText;
        case '1': return DGGopherItemKindMenu;
        case '7': return DGGopherItemKindSearch;
        case 'i': return DGGopherItemKindInfo;
        case 'h': return DGGopherItemKindHTML;
        case 's': return DGGopherItemKindSound;
        case '3': return DGGopherItemKindError;
        default:  return DGGopherItemKindUnknown;
    }
}

- (BOOL)isClickable
{
    switch ([self kind]) {
        case DGGopherItemKindText:
        case DGGopherItemKindMenu:
        case DGGopherItemKindSearch:
        case DGGopherItemKindSound:
            return YES;
        case DGGopherItemKindHTML:
            return ([self externalURLString] != nil);
        case DGGopherItemKindInfo:
        case DGGopherItemKindError:
        case DGGopherItemKindUnknown:
        default:
            return NO;
    }
}

- (NSString *)externalURLString
{
    if (_selector == nil) {
        return nil;
    }
    if ([_selector hasPrefix:@"URL:"]) {
        NSString *url = [_selector substringFromIndex:4];
        return ([url length] > 0) ? url : nil;
    }
    return nil;
}

@end
