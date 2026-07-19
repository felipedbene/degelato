//
//  DGServerPrefs.m
//  DeGelato — fio 15
//

#import "DGServerPrefs.h"

NSString * const DGSpotHostKey = @"DGSpotHost";
NSString * const DGSpotPortKey = @"DGSpotPort";
NSString * const DGServerPrefsDidChangeNotification = @"DGServerPrefsDidChangeNotification";

#define DG_SPOT_DEFAULT_HOST @"192.0.2.10"
#define DG_SPOT_DEFAULT_PORT 70

@implementation DGServerPrefs

+ (NSString *)trimmedHost:(NSString *)host
{
    if (host == nil) {
        return @"";
    }
    return [host stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - Validation

+ (BOOL)isValidHost:(NSString *)host
{
    return ([[self trimmedHost:host] length] > 0);
}

+ (BOOL)isValidPort:(NSInteger)port
{
    return (port >= 1 && port <= 65535);
}

+ (BOOL)isValidHost:(NSString *)host port:(NSInteger)port
{
    return ([self isValidHost:host] && [self isValidPort:port]);
}

#pragma mark - Effective values

+ (NSString *)defaultHost { return DG_SPOT_DEFAULT_HOST; }
+ (NSInteger)defaultPort  { return DG_SPOT_DEFAULT_PORT; }

+ (NSString *)host
{
    NSString *stored = [[NSUserDefaults standardUserDefaults]
                        objectForKey:DGSpotHostKey];
    stored = [self trimmedHost:stored];
    return ([stored length] > 0) ? stored : DG_SPOT_DEFAULT_HOST;
}

+ (NSInteger)port
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d objectForKey:DGSpotPortKey] == nil) {
        return DG_SPOT_DEFAULT_PORT;
    }
    NSInteger p = [d integerForKey:DGSpotPortKey];
    return [self isValidPort:p] ? p : DG_SPOT_DEFAULT_PORT;
}

#pragma mark - Persist

+ (BOOL)saveHost:(NSString *)host port:(NSInteger)port
{
    NSString *trimmed = [self trimmedHost:host];
    if (![self isValidHost:trimmed port:port]) {
        return NO;
    }

    BOOL changed = (![trimmed isEqualToString:[self host]] || port != [self port]);

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:trimmed forKey:DGSpotHostKey];
    [d setInteger:port forKey:DGSpotPortKey];
    [d synchronize];

    return changed;
}

@end
