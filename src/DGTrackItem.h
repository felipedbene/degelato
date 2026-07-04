//
//  DGTrackItem.h
//  DeGelato — fio 5
//
//  One track in a v1 **list** response. /queue and /search share the same
//  `item.<i>.*` block (see gopher-spot API.md), so one model + parser serve both.
//  Pure Foundation — no gopher, no AppKit.
//

#import <Foundation/Foundation.h>

@interface DGTrackItem : NSObject {
    NSString *_uri;         // spotify:track:<id>
    NSString *_track;       // track name
    NSString *_artist;      // artist name(s), joined with ", "
    NSString *_albumId;     // Spotify album id (for /cover); nil when absent
    long long _durationMs;  // track length in ms (0 if absent)
}

@property (nonatomic, copy)   NSString *uri;
@property (nonatomic, copy)   NSString *track;
@property (nonatomic, copy)   NSString *artist;
@property (nonatomic, copy)   NSString *albumId;
@property (nonatomic, assign) long long durationMs;

// Parse the ordered `item.<i>.{uri,track,artist,album_id,duration_ms}` block from
// an already-split fields dict (see +[DGApiParser fieldsFromResponse:]). Scans
// i = 0, 1, 2, … and stops at the first index with no `item.<i>.uri` line, so an
// empty list (no item.* lines) yields an empty array. Never returns nil.
+ (NSArray *)itemsFromFields:(NSDictionary *)fields;

// Convenience: split a raw v1 list body, then parse it.
+ (NSArray *)itemsFromResponse:(NSString *)body;

@end
