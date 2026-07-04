//
//  DGNowSnapshot.h
//  DeGelato — fio 1
//
//  The parsed /spot/api/1/now snapshot: an immutable value object holding the
//  machine API's view of what the player should show. The API is a type-0 text
//  document of `key<TAB>value` lines (UTF-8, CRLF); see gopher-spot API.md.
//  DGApiParser turns a raw response body into one of these.
//
//  Per the v1 freeze, unknown keys are ignored (forward-compatible) and a
//  client keys off `state` first: track…duration_ms are absent when stopped,
//  and volume is absent when no device reports one.
//
//  ppc32 / 10.5 note: every ivar is declared explicitly (fragile Obj-C ABI),
//  and the object is immutable once built — properties are readonly.
//

#import <Foundation/Foundation.h>

typedef enum {
    DGPlaybackStopped = 0,
    DGPlaybackPlaying,
    DGPlaybackPaused
} DGPlaybackState;

// Whether gopher-spot's librespot device is the account's current player.
// `device` is always present in a fio-S3 /now; DGDeviceUnknown covers an older
// server that omits it. `idle` means playback is on another device (or lost) and
// the audio stream won't carry it — recover with wake (a later fio). See API.md.
typedef enum {
    DGDeviceUnknown = 0,
    DGDeviceActive,
    DGDeviceIdle
} DGDeviceState;

@interface DGNowSnapshot : NSObject {
    DGPlaybackState _state;
    NSString  *_track;
    NSString  *_artist;
    NSString  *_album;
    NSString  *_albumId;     // Spotify album id (for /cover); nil when absent
    NSString  *_trackId;
    long long  _positionMs;
    long long  _durationMs;
    long long  _ts;          // unix epoch ms of the snapshot (for interpolation)
    NSInteger  _volume;      // 0–100, or -1 when the device reported none
    NSInteger  _queueLen;
    NSInteger  _apiVersion;
    DGDeviceState _device;
}

@property (nonatomic, readonly) DGPlaybackState state;
@property (nonatomic, readonly, copy) NSString *track;
@property (nonatomic, readonly, copy) NSString *artist;
@property (nonatomic, readonly, copy) NSString *album;
@property (nonatomic, readonly, copy) NSString *albumId;
@property (nonatomic, readonly, copy) NSString *trackId;
@property (nonatomic, readonly) long long positionMs;
@property (nonatomic, readonly) long long durationMs;
@property (nonatomic, readonly) long long ts;
@property (nonatomic, readonly) NSInteger volume;
@property (nonatomic, readonly) NSInteger queueLen;
@property (nonatomic, readonly) NSInteger apiVersion;
@property (nonatomic, readonly) DGDeviceState device;

// Designated initializer: build from an already-split { key: value } dict (see
// DGApiParser +fieldsFromResponse:). Missing keys default sensibly (state
// stopped, volume -1, numbers 0); unknown keys are simply never read.
- (id)initWithFields:(NSDictionary *)fields;

// Whether a track is loaded (track name present).
- (BOOL)hasTrack;
// Whether the device reported a volume.
- (BOOL)hasVolume;
// Whether gopher-spot is NOT the current player (device idle) — the audio
// stream won't carry what /now reports; recover with wake in a later fio.
- (BOOL)deviceIsIdle;

// Estimated position now, for a smooth progress readout between polls: while
// playing, positionMs + (nowEpochMs − ts), clamped to [0, durationMs]. When not
// playing (or ts unknown), just positionMs.
- (long long)interpolatedPositionMsAtEpochMs:(long long)nowEpochMs;

@end
