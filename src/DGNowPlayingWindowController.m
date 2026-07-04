//
//  DGNowPlayingWindowController.m
//  DeGelato — fios 1–4
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
#define DG_POLL_INTERVAL 2.0
#define DG_TICK_INTERVAL 1.0
#define DG_STREAM_VOLUME 1.0f    // loudness is controlled via the API device volume

@interface DGNowPlayingWindowController ()
- (NSTextField *)addLabelAtX:(CGFloat)x y:(CGFloat)y width:(CGFloat)w size:(CGFloat)size color:(NSColor *)color;
- (NSButton *)addButtonWithFrame:(NSRect)frame title:(NSString *)title action:(SEL)action;
- (void)sendCommand:(NSString *)selector;
- (void)commitSeek:(NSTimer *)timer;
- (void)catchUpPoll:(NSTimer *)timer;
- (DGPlaybackState)effectiveState;
- (void)updateCoverForSnapshot:(DGNowSnapshot *)snap;
- (void)render;
- (void)renderProgress;
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
    NSRect frame = NSMakeRect(0, 0, 480, 360);
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
        NSView *c = [window contentView];

        // Cover art, top-left; now-playing text to its right.
        _coverView = [[[NSImageView alloc] initWithFrame:NSMakeRect(16, 204, 148, 148)] autorelease];
        [_coverView setImageScaling:NSImageScaleProportionallyUpOrDown];
        [_coverView setImageFrameStyle:NSImageFrameGrayBezel];
        [_coverView setEditable:NO];
        [c addSubview:_coverView];

        _trackLabel  = [self addLabelAtX:176 y:326 width:288 size:15 color:[NSColor controlTextColor]];
        _artistLabel = [self addLabelAtX:176 y:304 width:288 size:13 color:[NSColor controlTextColor]];
        _albumLabel  = [self addLabelAtX:176 y:282 width:288 size:12 color:[NSColor grayColor]];
        _stateLabel  = [self addLabelAtX:176 y:256 width:288 size:12 color:[NSColor grayColor]];
        _deviceLabel = [self addLabelAtX:176 y:234 width:288 size:12 color:[NSColor grayColor]];

        // Controls band, full width, below the cover.
        _timeLabel   = [self addLabelAtX:16 y:178 width:448 size:12 color:[NSColor grayColor]];

        _seekSlider = [[[NSSlider alloc] initWithFrame:NSMakeRect(16, 158, 448, 16)] autorelease];
        [_seekSlider setMinValue:0.0];
        [_seekSlider setMaxValue:1.0];
        [_seekSlider setDoubleValue:0.0];
        [_seekSlider setContinuous:YES];      // live scrub; seek committed after a short debounce
        [_seekSlider setTarget:self];
        [_seekSlider setAction:@selector(onSeek:)];
        [c addSubview:_seekSlider];

        // Transport row, centered (window mid-x = 240).
        _prevButton      = [self addButtonWithFrame:NSMakeRect(140, 120, 60, 30)
                                              title:@"Prev" action:@selector(onPrev:)];
        _playPauseButton = [self addButtonWithFrame:NSMakeRect(208, 120, 64, 30)
                                              title:@"Play" action:@selector(onPlayPause:)];
        _nextButton      = [self addButtonWithFrame:NSMakeRect(280, 120, 60, 30)
                                              title:@"Next" action:@selector(onNext:)];

        _volumeLabel = [self addLabelAtX:16 y:88 width:120 size:12 color:[NSColor grayColor]];
        _volumeSlider = [[[NSSlider alloc] initWithFrame:NSMakeRect(146, 88, 300, 16)] autorelease];
        [_volumeSlider setMinValue:0.0];
        [_volumeSlider setMaxValue:100.0];
        [_volumeSlider setDoubleValue:100.0];
        [_volumeSlider setContinuous:NO];     // apply on release (avoid API spam)
        [_volumeSlider setTarget:self];
        [_volumeSlider setAction:@selector(onVolume:)];
        [c addSubview:_volumeSlider];

        _audioLabel  = [self addLabelAtX:16 y:60 width:448 size:12 color:[NSColor controlTextColor]];
        _statusLabel = [self addLabelAtX:16 y:36 width:220 size:12 color:[NSColor redColor]];

        _listenButton  = [self addButtonWithFrame:NSMakeRect(272, 8, 92, 30)
                                            title:@"Listen" action:@selector(toggleListen:)];
        _refreshButton = [self addButtonWithFrame:NSMakeRect(372, 8, 92, 30)
                                            title:@"Refresh" action:@selector(refresh:)];

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
    [_cmdClient cancel];
    [_cmdClient release];
    [_coverClient cancel];
    [_coverClient release];
    [_coverAlbumId release];
    [_lastSnapshot release];
    [_streamURL release];
    [_audioError release];
    [super dealloc];
}

- (NSTextField *)addLabelAtX:(CGFloat)x y:(CGFloat)y width:(CGFloat)w size:(CGFloat)size color:(NSColor *)color
{
    NSTextField *label = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(x, y, w, 20)] autorelease];
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

- (NSButton *)addButtonWithFrame:(NSRect)frame title:(NSString *)title action:(SEL)action
{
    NSButton *b = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [b setBezelStyle:NSRoundedBezelStyle];
    [b setTitle:title];
    [b setTarget:self];
    [b setAction:action];
    [[[self window] contentView] addSubview:b];
    return b;
}

#pragma mark - Polling

- (void)startPolling
{
    [self refresh:nil];
    NSRunLoop *rl = [NSRunLoop currentRunLoop];
    // Common modes so the poll keeps running while the user drags a slider or
    // holds a button (the run loop is in event-tracking mode then).
    if (_pollTimer == nil) {
        _pollTimer = [[NSTimer timerWithTimeInterval:DG_POLL_INTERVAL
                                              target:self selector:@selector(pollTick:)
                                            userInfo:nil repeats:YES] retain];
        [rl addTimer:_pollTimer forMode:NSRunLoopCommonModes];
    }
    if (_tickTimer == nil) {
        _tickTimer = [[NSTimer timerWithTimeInterval:DG_TICK_INTERVAL
                                              target:self selector:@selector(clockTick:)
                                            userInfo:nil repeats:YES] retain];
        [rl addTimer:_tickTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)stopPolling
{
    [_pollTimer invalidate];
    [_pollTimer release];
    _pollTimer = nil;
    [_tickTimer invalidate];
    [_tickTimer release];
    _tickTimer = nil;
    [_seekCommitTimer invalidate];
    [_seekCommitTimer release];
    _seekCommitTimer = nil;
    [_catchUpTimer invalidate];
    [_catchUpTimer release];
    _catchUpTimer = nil;
    [_client cancel];
    [_client release];
    _client = nil;
}

- (void)pollTick:(NSTimer *)timer
{
    NSLog(@"DG-PROBE pollTick _client=%p", _client);   // DG-PROBE
    [self refresh:nil];
}

- (void)clockTick:(NSTimer *)timer
{
    // Advance the seek bar / time between polls without a network hit.
    [self renderProgress];
}

- (void)refresh:(id)sender
{
    if (_client != nil) {
        NSLog(@"DG-PROBE refresh GUARD-HIT _client=%p (skipping)", _client);   // DG-PROBE
        return;
    }
    _client = [[DGGopherClient clientWithHost:DG_HOST port:DG_PORT
                                     selector:DG_SELECTOR] retain];
    NSLog(@"DG-PROBE refresh created _client=%p", _client);   // DG-PROBE
    [_client setDelegate:self];
    [_client start];
}

#pragma mark - Transport (fio 3)

- (void)sendCommand:(NSString *)selector
{
    // Last press wins: cancel any in-flight command rather than silently
    // dropping the new one, so rapid transport taps stay responsive.
    NSLog(@"DG-PROBE sendCommand %@ (cancel _cmdClient=%p) _client=%p", selector, _cmdClient, _client);   // DG-PROBE
    if (_cmdClient != nil) {
        [_cmdClient cancel];
        [_cmdClient release];
        _cmdClient = nil;
    }
    _cmdClient = [[DGGopherClient clientWithHost:DG_HOST port:DG_PORT
                                        selector:selector] retain];
    [_cmdClient setDelegate:self];
    [_cmdClient start];

    // Commands are eventual-consistent (~1-2 s); re-poll /now a couple of times to
    // bracket that window so the settled state (new track, paused, …) shows fast
    // instead of waiting for the regular 2 s cycle to happen to land after it
    // settles. Two polls at ~1.2 s and ~2.4 s straddle the typical settle time.
    _catchUpsLeft = 2;
    [_catchUpTimer invalidate];
    [_catchUpTimer release];
    _catchUpTimer = [[NSTimer timerWithTimeInterval:1.2
                                             target:self
                                           selector:@selector(catchUpPoll:)
                                           userInfo:nil
                                            repeats:NO] retain];
    [[NSRunLoop currentRunLoop] addTimer:_catchUpTimer forMode:NSRunLoopCommonModes];
}

- (void)catchUpPoll:(NSTimer *)timer
{
    [_catchUpTimer release];
    _catchUpTimer = nil;
    // Force a fresh /now even if a poll is mid-flight.
    NSLog(@"DG-PROBE catchUpPoll cancel+nil _client=%p left=%ld", _client, (long)_catchUpsLeft);   // DG-PROBE
    [_client cancel];
    [_client release];
    _client = nil;
    [self refresh:nil];

    _catchUpsLeft -= 1;
    if (_catchUpsLeft > 0) {
        _catchUpTimer = [[NSTimer timerWithTimeInterval:1.2
                                                 target:self
                                               selector:@selector(catchUpPoll:)
                                               userInfo:nil
                                                repeats:NO] retain];
        [[NSRunLoop currentRunLoop] addTimer:_catchUpTimer forMode:NSRunLoopCommonModes];
    }
}

// The state to display: the optimistic play/pause target during its hold window,
// else the last snapshot's state. Keeps the transport feeling instant despite the
// server's eventual consistency.
- (DGPlaybackState)effectiveState
{
    if ([self nowEpochMs] < _stateHoldUntilMs) {
        return (DGPlaybackState)_intendedState;
    }
    return (_lastSnapshot != nil) ? [_lastSnapshot state] : DGPlaybackStopped;
}

// Fetch the 300px cover when the album changes; covers are immutable per
// album_id, so a single-entry cache (the currently shown album) is enough for
// now. No blocks / NSCache — both are 10.6+.
- (void)updateCoverForSnapshot:(DGNowSnapshot *)snap
{
    NSString *aid = [snap albumId];
    if ([aid length] == 0) {
        if (_coverAlbumId != nil) {
            [_coverClient cancel];
            [_coverClient release];
            _coverClient = nil;
            [_coverAlbumId release];
            _coverAlbumId = nil;
            [_coverView setImage:nil];
        }
        return;
    }
    if ([aid isEqualToString:_coverAlbumId]) {
        return;   // already showing (or fetching) this album's cover
    }
    [_coverAlbumId release];
    _coverAlbumId = [aid copy];

    [_coverClient cancel];
    [_coverClient release];
    _coverClient = [[DGGopherClient clientWithHost:DG_HOST port:DG_PORT
        selector:[NSString stringWithFormat:@"/spot/api/1/cover/%@/300", aid]] retain];
    [_coverClient setDelegate:self];
    [_coverClient start];
}

- (void)onPlayPause:(id)sender
{
    BOOL playing = ([self effectiveState] == DGPlaybackPlaying);
    // Optimistic: flip to the intended state now and hold it past the settle
    // window, so the button responds instantly instead of looking dead for ~2 s.
    _intendedState = playing ? DGPlaybackPaused : DGPlaybackPlaying;
    _stateHoldUntilMs = [self nowEpochMs] + 2500;
    [self sendCommand:(playing ? @"/spot/api/1/pause" : @"/spot/api/1/play")];
    [self render];
}

- (void)onPrev:(id)sender { [self sendCommand:@"/spot/api/1/prev"]; }
- (void)onNext:(id)sender { [self sendCommand:@"/spot/api/1/next"]; }

- (void)wakeDevice:(id)sender { [self sendCommand:@"/spot/api/1/wake"]; }

- (void)onSeek:(id)sender
{
    long long dur = (_lastSnapshot != nil) ? [_lastSnapshot durationMs] : 0;
    double frac = [_seekSlider doubleValue];
    long long ms = (long long)(frac * (double)dur);

    // Live time readout as the knob moves (mouse drag OR keyboard arrows).
    [_timeLabel setStringValue:[NSString stringWithFormat:@"time     %@ / %@",
        [self clockFromMs:ms], [self clockFromMs:dur]]];

    // Hold reconciliation off the seek slider through the drag AND the command's
    // eventual-consistency window, so the knob doesn't snap back to a stale /now.
    _seekHoldUntilMs = [self nowEpochMs] + 3000;

    // Debounce: commit the seek once movement settles. This is input-agnostic —
    // no NSLeftMouseUp sniffing — so keyboard adjustment commits too and never
    // latches the slider.
    [_seekCommitTimer invalidate];
    [_seekCommitTimer release];
    _seekCommitTimer = [[NSTimer timerWithTimeInterval:0.35
                                                target:self
                                              selector:@selector(commitSeek:)
                                              userInfo:nil
                                               repeats:NO] retain];
    [[NSRunLoop currentRunLoop] addTimer:_seekCommitTimer forMode:NSRunLoopCommonModes];
}

- (void)commitSeek:(NSTimer *)timer
{
    [_seekCommitTimer release];
    _seekCommitTimer = nil;

    long long dur = (_lastSnapshot != nil) ? [_lastSnapshot durationMs] : 0;
    if (dur <= 0) {
        return;
    }
    long long ms = (long long)([_seekSlider doubleValue] * (double)dur);
    // Extend the hold so the ~1–2 s stale command reply can't rewind the knob.
    _seekHoldUntilMs = [self nowEpochMs] + 3000;
    [self sendCommand:[NSString stringWithFormat:@"/spot/api/1/seek?%lld", ms]];
}

- (void)onVolume:(id)sender
{
    NSInteger pct = (NSInteger)([_volumeSlider doubleValue] + 0.5);
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    [_volumeLabel setStringValue:[NSString stringWithFormat:@"volume  %ld%%", (long)pct]];
    // Hold reconciliation off the volume slider through the eventual-consistency
    // window, or the stale command reply snaps the thumb back to the old value.
    _volumeHoldUntilMs = [self nowEpochMs] + 3000;
    [self sendCommand:[NSString stringWithFormat:@"/spot/api/1/volume?%ld", (long)pct]];
}

#pragma mark - Audio control (fio 2)

- (void)toggleListen:(id)sender
{
    if (_streamer != nil || _audioState != DGAudioIdle) {
        [self stopAudio];
        return;
    }
    if (_lastSnapshot != nil && [_lastSnapshot deviceIsIdle]) {
        _audioState = DGAudioWaking;
        [self renderAudio];
        _wakeClient = [[DGGopherClient clientWithHost:DG_HOST port:DG_PORT
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
    _plsClient = [[DGGopherClient clientWithHost:DG_HOST port:DG_PORT
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
    if (client == _coverClient) {
        // Binary: raw JPEG on success, a tab-KV error document otherwise.
        [_coverClient release];
        _coverClient = nil;
        if ([DGApiParser dataIsJPEG:data]) {
            NSImage *img = [[[NSImage alloc] initWithData:data] autorelease];
            [_coverView setImage:img];   // nil-safe if the bytes won't decode
        } else {
            [_coverView setImage:nil];   // not_found / bad_range
        }
        return;
    }

    NSString *text = [DGApiParser textFromData:data];

    if (client == _cmdClient) {
        // A command's reply IS a /now snapshot, but Spotify is eventual-consistent
        // (~1-2 s): right after a pause it can still report "playing", after next
        // it still reports the old track. Adopting it makes commands look broken
        // and can flicker the UI, so we DON'T adopt it — we only surface an error.
        // The catch-up poll scheduled by -sendCommand (plus the 2 s poll) converge
        // on the settled state, and play/pause is reflected optimistically.
        NSDictionary *fields = [DGApiParser fieldsFromResponse:text];
        NSString *errCode = [fields objectForKey:@"error"];
        [_cmdClient release];
        _cmdClient = nil;
        if (errCode != nil) {
            [_statusLabel setStringValue:[NSString stringWithFormat:@"error: %@", errCode]];
        }
        return;
    }

    if (client == _client || client == _wakeClient) {
        // The poll (and the Listen-flow wake) carry authoritative /now state.
        NSDictionary *fields = [DGApiParser fieldsFromResponse:text];
        NSString *errCode = [fields objectForKey:@"error"];
        BOOL looksLikeNow = ([fields objectForKey:@"state"] != nil ||
                             [fields objectForKey:@"api"] != nil);
        if (errCode != nil) {
            // The stable code is short; the human `message` can be long and would
            // truncate in the status line.
            [_statusLabel setStringValue:[NSString stringWithFormat:@"error: %@", errCode]];
            _online = NO;   // no fresh state — freeze the clock instead of racing to 100%
        } else if (looksLikeNow) {
            DGNowSnapshot *snap = [DGApiParser snapshotFromFields:fields];
            [_lastSnapshot release];
            _lastSnapshot = [snap retain];
            _online = YES;
            [_statusLabel setStringValue:@""];
            [self render];
        }
        // else: a bodyless / ack reply carrying no /now fields — keep the last
        // snapshot rather than blanking the display with an all-defaults one.

        BOOL wasWake = (client == _wakeClient);
        if (client == _client)     { NSLog(@"DG-PROBE didFinish _client=%p -> nil (looksLikeNow=%d err=%@)", _client, looksLikeNow, errCode); [_client release];     _client = nil; }   // DG-PROBE
        if (client == _wakeClient) { [_wakeClient release]; _wakeClient = nil; }

        if (wasWake && _audioState == DGAudioWaking) {
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
            _audioError = [@"audio    no stream URL in playlist" copy];
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
    if (client == _coverClient) {
        [_coverClient release];
        _coverClient = nil;
        [_coverView setImage:nil];   // best-effort; keep _coverAlbumId (no retry spam)
        return;
    }
    if (client == _client) {
        NSLog(@"DG-PROBE didFail _client=%p -> nil (%@)", _client, [error localizedDescription]);   // DG-PROBE
        [_statusLabel setStringValue:@"offline — retrying"];
        _online = NO;   // freeze interpolation; keep the last snapshot on screen
        [_client release];
        _client = nil;
        return;
    }
    if (client == _cmdClient) {
        [_statusLabel setStringValue:@"command failed"];
        [_cmdClient release];
        _cmdClient = nil;
        return;
    }
    if (client == _wakeClient) {
        [_wakeClient release];
        _wakeClient = nil;
        if (_audioState == DGAudioWaking) {
            [self beginDiscovery];
        }
        return;
    }
    if (client == _plsClient) {
        [_plsClient release];
        _plsClient = nil;
        [_audioError release];
        _audioError = [@"audio    stream unavailable" copy];
        _audioState = DGAudioError;
        [self renderAudio];
        return;
    }
}

#pragma mark - DGAudioStreamerDelegate (main thread)

- (void)audioStreamerDidStartPlaying:(DGAudioStreamer *)streamer
{
    if (streamer != _streamer) { return; }
    _audioState = DGAudioPlaying;
    [self renderAudio];
}

- (void)audioStreamer:(DGAudioStreamer *)streamer didFailWithMessage:(NSString *)message
{
    if (streamer != _streamer) { return; }
    [_audioError release];
    _audioError = [[NSString stringWithFormat:@"audio    %@", message] copy];
    [self stopAudio];
    _audioState = DGAudioError;
    [self renderAudio];
}

- (void)audioStreamerDidFinish:(DGAudioStreamer *)streamer
{
    if (streamer != _streamer) { return; }
    [self stopAudio];
}

#pragma mark - Rendering

- (void)render
{
    DGNowSnapshot *s = _lastSnapshot;
    [self updateCoverForSnapshot:s];
    if (s == nil) {
        [_trackLabel setStringValue:@"connecting…"];
        [_artistLabel setStringValue:@""];
        [_albumLabel setStringValue:@""];
        [_stateLabel setStringValue:@""];
        [_deviceLabel setStringValue:@""];
        [_timeLabel setStringValue:@""];
        [_volumeLabel setStringValue:@"volume"];
        [_playPauseButton setTitle:@"Play"];
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

    DGPlaybackState eff = [self effectiveState];
    NSString *state;
    switch (eff) {
        case DGPlaybackPlaying: state = @"playing"; break;
        case DGPlaybackPaused:  state = @"paused";  break;
        default:                state = @"stopped"; break;
    }
    [_stateLabel setStringValue:[NSString stringWithFormat:@"state    %@", state]];

    NSString *device;
    switch ([s device]) {
        case DGDeviceActive: device = @"active"; break;
        case DGDeviceIdle:   device = @"idle (playing elsewhere)"; break;
        default:             device = @"unknown"; break;
    }
    [_deviceLabel setStringValue:[NSString stringWithFormat:@"device   %@", device]];

    [_playPauseButton setTitle:(eff == DGPlaybackPlaying ? @"Pause" : @"Play")];

    // Don't reconcile the volume slider while the user's just-set value is still
    // settling on the server (see onVolume:).
    if ([self nowEpochMs] >= _volumeHoldUntilMs) {
        if ([s hasVolume]) {
            [_volumeLabel setStringValue:[NSString stringWithFormat:@"volume  %ld%%", (long)[s volume]]];
            [_volumeSlider setDoubleValue:(double)[s volume]];
        } else {
            [_volumeLabel setStringValue:@"volume  —"];
        }
    }

    [self renderProgress];
}

- (void)renderProgress
{
    DGNowSnapshot *s = _lastSnapshot;
    long long now = [self nowEpochMs];
    BOOL holdSeek = (now < _seekHoldUntilMs);   // user is scrubbing / just sought
    if (holdSeek) {
        return;   // leave the knob + time where onSeek: put them
    }
    if (s == nil || ![s hasTrack]) {
        [_timeLabel setStringValue:@"time     —"];
        [_seekSlider setDoubleValue:0.0];
        return;
    }
    long long dur = [s durationMs];
    // Freeze at the snapshot's stored position when offline / after an error —
    // otherwise the 1 Hz tick keeps interpolating a stale "playing" snapshot and
    // the bar races to 100% during an outage.
    long long pos = _online ? [s interpolatedPositionMsAtEpochMs:now] : [s positionMs];
    [_timeLabel setStringValue:[NSString stringWithFormat:@"time     %@ / %@",
        [self clockFromMs:pos], [self clockFromMs:dur]]];
    [_seekSlider setDoubleValue:(dur > 0 ? (double)pos / (double)dur : 0.0)];
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
            button = @"Listen";
            color = [NSColor redColor];
            break;
        default:                 audio = @"audio    idle";          button = @"Listen"; break;
    }
    [_audioLabel setTextColor:color];
    [_audioLabel setStringValue:audio];
    [_listenButton setTitle:button];
}

- (long long)nowEpochMs
{
    return (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

- (NSString *)clockFromMs:(long long)ms
{
    if (ms < 0) { ms = 0; }
    long long totalSec = ms / 1000;
    return [NSString stringWithFormat:@"%lld:%02lld", totalSec / 60, totalSec % 60];
}

@end
