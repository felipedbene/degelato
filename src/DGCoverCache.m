//
//  DGCoverCache.m
//  DeGelato — fio 16
//

#import "DGCoverCache.h"

#define DG_COVER_MEM_CAP 96   // enough for a playlist of 64px thumbnails + a 300

@interface DGCoverCache ()
- (NSString *)keyForAlbum:(NSString *)albumId size:(NSInteger)size;
- (void)touchKey:(NSString *)key;
@end

@implementation DGCoverCache

+ (DGCoverCache *)sharedCache
{
    static DGCoverCache *shared = nil;
    if (shared == nil) {
        NSArray *caches = NSSearchPathForDirectoriesInDomains(
            NSCachesDirectory, NSUserDomainMask, YES);
        NSString *base = ([caches count] > 0) ? [caches objectAtIndex:0]
                                              : NSTemporaryDirectory();
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        if ([bundleId length] == 0) {
            bundleId = @"DeGelato";
        }
        NSString *dir = [[base stringByAppendingPathComponent:bundleId]
                         stringByAppendingPathComponent:@"covers"];
        shared = [[DGCoverCache alloc] initWithDirectory:dir];
    }
    return shared;
}

- (id)initWithDirectory:(NSString *)dir
{
    self = [super init];
    if (self != nil) {
        _diskDir = [dir copy];
        _memory = [[NSMutableDictionary alloc] init];
        _order = [[NSMutableArray alloc] init];
        _memCap = DG_COVER_MEM_CAP;
        [[NSFileManager defaultManager] createDirectoryAtPath:_diskDir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
    }
    return self;
}

- (void)dealloc
{
    [_memory release];
    [_order release];
    [_diskDir release];
    [super dealloc];
}

#pragma mark - Keys / paths

+ (NSString *)fileNameForAlbum:(NSString *)albumId size:(NSInteger)size
{
    // Spotify album ids are base62, but sanitize defensively so the id can never
    // escape the cache dir or collide with a path separator.
    NSMutableString *safe = [NSMutableString stringWithCapacity:[albumId length]];
    NSCharacterSet *ok = [NSCharacterSet alphanumericCharacterSet];
    NSUInteger i, n = [albumId length];
    for (i = 0; i < n; i++) {
        unichar ch = [albumId characterAtIndex:i];
        [safe appendString:([ok characterIsMember:ch]
                            ? [NSString stringWithCharacters:&ch length:1] : @"_")];
    }
    return [NSString stringWithFormat:@"%@-%ld.jpg", safe, (long)size];
}

- (NSString *)diskPathForAlbum:(NSString *)albumId size:(NSInteger)size
{
    return [_diskDir stringByAppendingPathComponent:
            [DGCoverCache fileNameForAlbum:albumId size:size]];
}

- (NSString *)keyForAlbum:(NSString *)albumId size:(NSInteger)size
{
    return [NSString stringWithFormat:@"%@-%ld", albumId, (long)size];
}

#pragma mark - Lookup / store

- (NSData *)coverDataForAlbum:(NSString *)albumId size:(NSInteger)size
{
    if ([albumId length] == 0) {
        return nil;
    }
    NSString *key = [self keyForAlbum:albumId size:size];

    NSData *hit = [_memory objectForKey:key];
    if (hit != nil) {
        [self touchKey:key];   // access-order LRU
        return hit;
    }

    NSData *disk = [NSData dataWithContentsOfFile:
                    [self diskPathForAlbum:albumId size:size]];
    if ([disk length] > 0) {
        [_memory setObject:disk forKey:key];   // promote to memory
        [self touchKey:key];
        return disk;
    }
    return nil;
}

- (void)storeData:(NSData *)jpeg forAlbum:(NSString *)albumId size:(NSInteger)size
{
    if ([albumId length] == 0 || [jpeg length] == 0) {
        return;
    }
    [jpeg writeToFile:[self diskPathForAlbum:albumId size:size] atomically:YES];
    NSString *key = [self keyForAlbum:albumId size:size];
    [_memory setObject:jpeg forKey:key];
    [self touchKey:key];
}

// Move key to the most-recently-used end; evict the LRU entry past the cap.
- (void)touchKey:(NSString *)key
{
    [key retain];
    [_order removeObject:key];
    [_order addObject:key];
    [key release];
    while ([_order count] > _memCap) {
        NSString *lru = [_order objectAtIndex:0];
        [_memory removeObjectForKey:lru];
        [_order removeObjectAtIndex:0];
    }
}

@end
