//
//  DGNowPlayingWindowController.m
//  DeGelato — fio 1 + fio 2
//

#import "DGNowPlayingWindowController.h"
#import "DGApiParser.h"
#import "DGNowSnapshot.h"
#import "DGPLSParser.h"
#import "DGFontManager.h"

#define DG_HOST          @"10.0.100.112"
#define DG_PORT          70
#define DG_SELECTOR      @"/spot/api/1/now"
#define DG_PLS_SELECTOR  @"/spot/stream.pls"
#define DG_WAKE_SELECTOR @"/spot/api/1/wake?play=1"
#define DG_POLL_INTERVAL 2.0     // the server micro-caches /now (~1s); never faster
#define DG_STREAM_VOLUME 0.75f

@interface DGNowPlayingWindowController ()
- (NSTextField *)addLabelAtY:(CGFloat)y size:(CGFloat)size color:(NSColor *)color;
- (void)render;
- (void)renderAudio;
- (void)beginDiscovery;
- (void)startStreamerWithURL:(NSString *)url;
- (void)stopAudio;
- (long long)nowEpochMs;
- (NSString *)clockFromMs:(long long)ms;
@end

@implementation DGNowPlayingWindowController

- (id)init
{
    NSRect frame = NSMakeRect(0, 0, 440, 300);
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"DeGelato — Now Playing"];
    [window setReleasedWhenClosed:NO];
    [window center];

    self = [super initWithWindow:window];
    if (self != nil) {
        _trackLabel  = [self addLabelAtY:262 size:15 color:[NSColor controlTextColor]];
        _artistLabel = [self addLabelAtY:238 size:13 color:[NSColor controlTextColor]];
        _albumLabel  = [self addLabelAtY:216 size:13 color:[NSColor grayColor]];

        _stateLabel  = [self addLabelAtY:182 size:12 color:[NSColor grayColor]];
        _timeLabel   = [self addLabelAtY:160 size:12 color:[NSColor grayColor]];
        _volumeLabel = [self addLabelAtY:138 size:12 color:[NSColor grayColor]];
        _deviceLabel = [self addLabelAtY:116 size:12 color:[NSColor grayColor]];

        _audioLabel  = [self addLabelAtY:88 size:12 color:[NSColor controlTextColor]];
        _statusLabel = [self addLabelAtY:62 size:12 color:[NSColor redColor]];

        _playButton = [[[NSButton alloc] initWithFrame:NSMakeRect(232, 14, 92, 30)] autorelease];
        [_playButton setBezelStyle:NSRoundedBezelStyle];
        [_playButton setTitle:@"Play"];
        [_playButton setTarget:self];
        [_playButton setAction:@selector(togglePlay:)];
        [[window contentView] addSubview:_playButton];

        _refreshButton = [[[NSButton alloc] initWithFrame:NSMakeRect(332, 14, 92, 30)] autorelease];
        [_refreshButton setBezelStyle:NSRoundedBezelStyle];
        [_refreshButton setTitle:@"Refresh"];
        [_refreshButton setTarget:self];
        [_refreshButton setAction:@selector(refresh:)];
        [[window contentView] addSubview:_refreshButton];

        _audioState = DGAudioIdle;
        [self render];
        [self renderAudio];
    }
    [window release];
    return self;
}

- (void)dealloc
{
    [self stopPolling];
    [self stopAudio];
    [_lastSnapshot release];
    [_streamURL release];
    [_audioError release];
    [super dealloc];
}

- (NSTextField *)addLabelAtY:(CGFloat)y size:(CGFloat)size color:(NSColor *)color
{
    NSTextField *label = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(16, y, 408, 20)] autorelease];
    [label setEditable:NO];
    [label setSelectable:YES];
    [label setBordered:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setFont:[DGFontManager documentFontOfSize:size]];
    [label setTextColor:color];
    [label setStringValue:@""];
    [[[self window] contentView] addSubview:label];
    return label;
}

#pragma mark - Polling

- (void)startPolling
{
    [self refresh:nil];
    if (_pollTimer == nil) {
        _pollTimer = [[NSTimer scheduledTimerWithTimeInterval:DG_POLL_INTERVAL
                                                       target:self
                                                     selector:@selector(pollTick:)
                                                     userInfo:nil
                                                      repeats:YES] retain];
    }
}

- (void)stopPolling
{
    [_pollTimer invalidate];
    [_pollTimer release];
    _pollTimer = nil;
    [_client cancel];
    [_client release];
    _client = nil;
}

- (void)pollTick:(NSTimer *)timer
{
    [self refresh:nil];
}

- (void)refresh:(id)sender
{
    if (_client != nil) {
        return;   // a poll is already in flight; skip this tick
    }
    _client = [[DGGopherClient clientWithHost:DG_HOST
                                         port:DG_PORT
                                     selector:DG_SELECTOR] retain];
    [_client setDelegate:self];
    [_client start];
}

#pragma mark - Audio control

- (void)togglePlay:(id)sender
{
    if (_streamer != nil || _audioState != DGAudioIdle) {
        [self stopAudio];   // also cancels an in-flight wake/discovery
        return;
    }

    // Fresh start. If the gopher-spot device is idle, the audio pipe won't carry
    // the current playback — wake it (and resume) before streaming.
    if (_lastSnapshot != nil && [_lastSnapshot deviceIsIdle]) {
        _audioState = DGAudioWaking;
        [self renderAudio];
        _wakeClient = [[DGGopherClient clientWithHost:DG_HOST
                                                 port:DG_PORT
                                             selector:DG_WAKE_SELECTOR] retain];
        [_wakeClient setDelegate:self];
        [_wakeClient start];
    } else {
        [self beginDiscovery];
    }
}

- (void)beginDiscovery
{
    _audioState = DGAudioDiscovering;
    [self renderAudio];
    _plsClient = [[DGGopherClient clientWithHost:DG_HOST
                                            port:DG_PORT
                                        selector:DG_PLS_SELECTOR] retain];
    [_plsClient setDelegate:self];
    [_plsClient start];
}

- (void)startStreamerWithURL:(NSString *)url
{
    [_streamURL release];
    _streamURL = [url copy];

    _streamer = [[DGAudioStreamer alloc] initWithURLString:_streamURL];
    [_streamer setDelegate:self];
    [_streamer setVolume:DG_STREAM_VOLUME];
    _audioState = DGAudioBuffering;
    [self renderAudio];
    [_streamer start];
}

- (void)stopAudio
{
    if (_streamer != nil) {
        [_streamer setDelegate:nil];
        [_streamer stop];
        [_streamer release];
        _streamer = nil;
    }
    [_plsClient cancel];
    [_plsClient release];
    _plsClient = nil;
    [_wakeClient cancel];
    [_wakeClient release];
    _wakeClient = nil;

    _audioState = DGAudioIdle;
    [self renderAudio];
}

#pragma mark - DGGopherClientDelegate

- (void)dgGopherClient:(DGGopherClient *)client didFinishWithData:(NSData *)data
{
    NSString *text = [DGApiParser textFromData:data];

    if (client == _client) {
        // /now poll.
        DGNowSnapshot *snap = [DGApiParser snapshotFromResponse:text];
        [_lastSnapshot release];
        _lastSnapshot = [snap retain];
        [_statusLabel setStringValue:@""];
        [self render];
        [_client release];
        _client = nil;
        return;
    }

    if (client == _wakeClient) {
        // wake?play=1 returns a fresh /now snapshot; adopt it, then discover.
        DGNowSnapshot *snap = [DGApiParser snapshotFromResponse:text];
        [_lastSnapshot release];
        _lastSnapshot = [snap retain];
        [self render];
        [_wakeClient release];
        _wakeClient = nil;
        if (_audioState == DGAudioWaking) {
            [self beginDiscovery];
        }
        return;
    }

    if (client == _plsClient) {
        NSString *url = [DGPLSParser firstURLFromPlaylistText:text];
        [_plsClient release];
        _plsClient = nil;
        if ([url length] == 0) {
            [_audioError release];
            _audioError = [@"audio: no stream URL in playlist" copy];
            _audioState = DGAudioError;
            [self renderAudio];
            return;
        }
        [self startStreamerWithURL:url];
        return;
    }
}

- (void)dgGopherClient:(DGGopherClient *)client didFailWithError:(NSError *)error
{
    if (client == _client) {
        [_statusLabel setStringValue:@"offline — retrying"];
        [_client release];
        _client = nil;
        return;
    }
    if (client == _wakeClient) {
        [_wakeClient release];
        _wakeClient = nil;
        // Wake failed, but the stream may still carry something — try anyway.
        if (_audioState == DGAudioWaking) {
            [self beginDiscovery];
        }
        return;
    }
    if (client == _plsClient) {
        [_plsClient release];
        _plsClient = nil;
        [_audioError release];
        _audioError = [@"audio: stream unavailable" copy];
        _audioState = DGAudioError;
        [self renderAudio];
        return;
    }
}

#pragma mark - DGAudioStreamerDelegate (already on the main thread)

- (void)audioStreamerDidStartPlaying:(DGAudioStreamer *)streamer
{
    if (streamer != _streamer) {
        return;
    }
    _audioState = DGAudioPlaying;
    [self renderAudio];
}

- (void)audioStreamer:(DGAudioStreamer *)streamer didFailWithMessage:(NSString *)message
{
    if (streamer != _streamer) {
        return;
    }
    [_audioError release];
    _audioError = [[NSString stringWithFormat:@"audio: %@", message] copy];
    [self stopAudio];              // tears the streamer down; sets state idle
    _audioState = DGAudioError;    // ...then surface the error
    [self renderAudio];
}

- (void)audioStreamerDidFinish:(DGAudioStreamer *)streamer
{
    if (streamer != _streamer) {
        return;
    }
    [self stopAudio];
}

#pragma mark - Rendering

- (void)render
{
    DGNowSnapshot *s = _lastSnapshot;
    if (s == nil) {
        [_trackLabel setStringValue:@"connecting…"];
        [_artistLabel setStringValue:@""];
        [_albumLabel setStringValue:@""];
        [_stateLabel setStringValue:@""];
        [_timeLabel setStringValue:@""];
        [_volumeLabel setStringValue:@""];
        [_deviceLabel setStringValue:@""];
        return;
    }

    if ([s hasTrack]) {
        [_trackLabel setStringValue:[s track]];
        [_artistLabel setStringValue:([s artist] ? [s artist] : @"")];
        [_albumLabel setStringValue:([s album] ? [s album] : @"")];
    } else {
        [_trackLabel setStringValue:@"— nothing playing —"];
        [_artistLabel setStringValue:@""];
        [_albumLabel setStringValue:@""];
    }

    NSString *state;
    switch ([s state]) {
        case DGPlaybackPlaying: state = @"playing"; break;
        case DGPlaybackPaused:  state = @"paused";  break;
        default:                state = @"stopped"; break;
    }
    [_stateLabel setStringValue:[NSString stringWithFormat:@"state    %@", state]];

    if ([s hasTrack]) {
        long long pos = [s interpolatedPositionMsAtEpochMs:[self nowEpochMs]];
        [_timeLabel setStringValue:[NSString stringWithFormat:@"time     %@ / %@",
            [self clockFromMs:pos], [self clockFromMs:[s durationMs]]]];
    } else {
        [_timeLabel setStringValue:@"time     —"];
    }

    if ([s hasVolume]) {
        [_volumeLabel setStringValue:[NSString stringWithFormat:@"volume   %ld%%", (long)[s volume]]];
    } else {
        [_volumeLabel setStringValue:@"volume   —"];
    }

    NSString *device;
    switch ([s device]) {
        case DGDeviceActive: device = @"active"; break;
        case DGDeviceIdle:   device = @"idle (playing elsewhere)"; break;
        default:             device = @"unknown"; break;
    }
    [_deviceLabel setStringValue:[NSString stringWithFormat:@"device   %@", device]];
}

- (void)renderAudio
{
    NSString *audio;
    NSString *button;
    NSColor  *color = [NSColor controlTextColor];
    switch (_audioState) {
        case DGAudioWaking:      audio = @"audio    waking device…"; button = @"…";    break;
        case DGAudioDiscovering: audio = @"audio    connecting…";    button = @"…";    break;
        case DGAudioBuffering:   audio = @"audio    buffering…";     button = @"Stop"; break;
        case DGAudioPlaying:     audio = @"audio    playing";        button = @"Stop"; break;
        case DGAudioError:
            audio = (_audioError ? _audioError : @"audio    error");
            button = @"Play";
            color = [NSColor redColor];
            break;
        default:                 audio = @"audio    idle";          button = @"Play"; break;
    }
    [_audioLabel setTextColor:color];
    [_audioLabel setStringValue:audio];
    [_playButton setTitle:button];
}

- (long long)nowEpochMs
{
    return (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

- (NSString *)clockFromMs:(long long)ms
{
    if (ms < 0) {
        ms = 0;
    }
    long long totalSec = ms / 1000;
    long long m = totalSec / 60;
    long long sec = totalSec % 60;
    return [NSString stringWithFormat:@"%lld:%02lld", m, sec];
}

@end
