//
//  DGNowSnapshot.m
//  DeGelato — fio 1
//

#import "DGNowSnapshot.h"

@implementation DGNowSnapshot

@synthesize state = _state;
@synthesize track = _track;
@synthesize artist = _artist;
@synthesize album = _album;
@synthesize albumId = _albumId;
@synthesize trackId = _trackId;
@synthesize positionMs = _positionMs;
@synthesize durationMs = _durationMs;
@synthesize ts = _ts;
@synthesize volume = _volume;
@synthesize queueLen = _queueLen;
@synthesize apiVersion = _apiVersion;
@synthesize device = _device;

static DGPlaybackState DGPlaybackStateFromString(NSString *s)
{
    if ([s isEqualToString:@"playing"]) {
        return DGPlaybackPlaying;
    }
    if ([s isEqualToString:@"paused"]) {
        return DGPlaybackPaused;
    }
    return DGPlaybackStopped;
}

static DGDeviceState DGDeviceStateFromString(NSString *s)
{
    if ([s isEqualToString:@"active"]) {
        return DGDeviceActive;
    }
    if ([s isEqualToString:@"idle"]) {
        return DGDeviceIdle;
    }
    return DGDeviceUnknown;   // absent (older server) or unrecognized
}

- (id)initWithFields:(NSDictionary *)f
{
    self = [super init];
    if (self != nil) {
        _state      = DGPlaybackStateFromString([f objectForKey:@"state"]);
        _track      = [[f objectForKey:@"track"] copy];
        _artist     = [[f objectForKey:@"artist"] copy];
        _album      = [[f objectForKey:@"album"] copy];
        _albumId    = [[f objectForKey:@"album_id"] copy];
        _trackId    = [[f objectForKey:@"track_id"] copy];
        _positionMs = [[f objectForKey:@"position_ms"] longLongValue];
        _durationMs = [[f objectForKey:@"duration_ms"] longLongValue];
        _ts         = [[f objectForKey:@"ts"] longLongValue];
        _queueLen   = [[f objectForKey:@"queue_len"] integerValue];
        _apiVersion = [[f objectForKey:@"api"] integerValue];
        _device     = DGDeviceStateFromString([f objectForKey:@"device"]);

        NSString *vol = [f objectForKey:@"volume"];
        _volume = (vol != nil) ? [vol integerValue] : -1;   // unknown until reported
    }
    return self;
}

- (id)init
{
    return [self initWithFields:[NSDictionary dictionary]];
}

- (void)dealloc
{
    [_track release];
    [_artist release];
    [_album release];
    [_albumId release];
    [_trackId release];
    [super dealloc];
}

- (BOOL)hasTrack
{
    return ([_track length] > 0);
}

- (BOOL)hasVolume
{
    return (_volume >= 0);
}

- (BOOL)deviceIsIdle
{
    return (_device == DGDeviceIdle);
}

- (long long)interpolatedPositionMsAtEpochMs:(long long)nowEpochMs
{
    if (_state != DGPlaybackPlaying || _ts <= 0) {
        return _positionMs;
    }
    long long est = _positionMs + (nowEpochMs - _ts);
    if (est < 0) {
        est = 0;
    }
    if (_durationMs > 0 && est > _durationMs) {
        est = _durationMs;
    }
    return est;
}

@end
