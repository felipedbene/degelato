//
//  DGPlaylistItem.h
//  DeGelato — fio 17
//
//  One playlist in a v1 /spot/api/1/playlists list response: the `item.<i>.*`
//  block carries {id, name, tracks_len}. Play is by CONTEXT (spotify:playlist:id)
//  so next/prev follow the playlist order. Ported from DeToca's DTPlaylistItem.
//  Pure Foundation — no gopher, no AppKit.
//

#import <Foundation/Foundation.h>

@interface DGPlaylistItem : NSObject {
    NSString *_playlistId;   // Spotify playlist id
    NSString *_name;         // display name
    NSInteger _tracksLen;    // number of tracks (0 if absent)
}

@property (nonatomic, copy)   NSString *playlistId;
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, assign) NSInteger tracksLen;

// spotify:playlist:<id>, or nil when the id is missing.
- (NSString *)contextURI;

// Parse the ordered `item.<i>.{id,name,tracks_len}` block from an already-split
// fields dict. Scans i = 0,1,2,… and stops at the first index with no
// `item.<i>.id` line. Never returns nil.
+ (NSArray *)itemsFromFields:(NSDictionary *)fields;
+ (NSArray *)itemsFromResponse:(NSString *)body;

@end
