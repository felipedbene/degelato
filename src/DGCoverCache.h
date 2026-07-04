//
//  DGCoverCache.h
//  DeGelato — fio 16
//
//  Two-level cache of album cover JPEG bytes: an in-memory dictionary plus a
//  disk cache under ~/Library/Caches/<bundle id>/covers/<album_id>-<size>.jpg.
//  Covers are immutable per (album_id, size), so nothing expires; memory is
//  bounded by a small access-order cap and disk is backed forever.
//
//  Ported from DeToca's DTCoverCache, adapted for 10.5: NO NSCache (10.6+) — a
//  plain NSMutableDictionary + an insertion/access-order key list; NO fetcher
//  block (10.6+) — this is a PASSIVE store. The caller fetches over the network
//  with its own DGGopherClient and hands the bytes to -storeData:...; the model
//  layer deals in raw JPEG NSData, the UI turns that into an NSImage. Pure
//  Foundation — unit-testable.
//

#import <Foundation/Foundation.h>

@interface DGCoverCache : NSObject {
    NSMutableDictionary *_memory;   // "<albumId>-<size>" -> NSData (jpeg)
    NSMutableArray      *_order;    // keys, least-recently-used first (mem cap)
    NSString            *_diskDir;
    NSUInteger           _memCap;
}

// App-wide cache under ~/Library/Caches/<bundle id>/covers.
+ (DGCoverCache *)sharedCache;

// Explicit directory (tests point this at a temp dir).
- (id)initWithDirectory:(NSString *)dir;

// Cached JPEG bytes for (albumId, size): memory, then disk (promoted to memory),
// else nil. A nil/empty albumId yields nil.
- (NSData *)coverDataForAlbum:(NSString *)albumId size:(NSInteger)size;

// Store JPEG bytes to memory + disk. A nil/empty albumId or nil data is a no-op.
- (void)storeData:(NSData *)jpeg forAlbum:(NSString *)albumId size:(NSInteger)size;

+ (NSString *)fileNameForAlbum:(NSString *)albumId size:(NSInteger)size;  // "<id>-<size>.jpg"
- (NSString *)diskPathForAlbum:(NSString *)albumId size:(NSInteger)size;

@end
