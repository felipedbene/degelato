//
//  DGPLSParser.h
//  DeGelato — fio 2
//
//  Extracts the first stream URL from a playlist. Handles PLS
//  ("File1=http://…") and Extended/plain M3U (bare "http://…" lines).
//  gopher-spot serves its audio stream behind a PLS at /spot/stream.pls, whose
//  File1 points at the Icecast MP3 (a separate MetalLB LoadBalancer IP, :8000).
//  Pure Foundation, unit-testable — no gopher, no audio.
//

#import <Foundation/Foundation.h>

@interface DGPLSParser : NSObject

// The first playable URL in the playlist text, or nil if none is found.
+ (NSString *)firstURLFromPlaylistText:(NSString *)text;

@end
