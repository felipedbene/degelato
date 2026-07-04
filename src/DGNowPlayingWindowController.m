//
//  DGNowPlayingWindowController.m
//  DeGelato — fio 1
//

#import "DGNowPlayingWindowController.h"
#import "DGApiParser.h"
#import "DGNowSnapshot.h"
#import "DGFontManager.h"

#define DG_HOST          @"10.0.100.112"
#define DG_PORT          70
#define DG_SELECTOR      @"/spot/api/1/now"
#define DG_POLL_INTERVAL 2.0     // the server micro-caches /now (~1s); never faster

@interface DGNowPlayingWindowController ()
- (NSTextField *)addLabelAtY:(CGFloat)y size:(CGFloat)size color:(NSColor *)color;
- (void)render;
- (long long)nowEpochMs;
- (NSString *)clockFromMs:(long long)ms;
@end

@implementation DGNowPlayingWindowController

- (id)init
{
    NSRect frame = NSMakeRect(0, 0, 440, 262);
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
        _trackLabel  = [self addLabelAtY:224 size:15 color:[NSColor controlTextColor]];
        _artistLabel = [self addLabelAtY:200 size:13 color:[NSColor controlTextColor]];
        _albumLabel  = [self addLabelAtY:178 size:13 color:[NSColor grayColor]];

        _stateLabel  = [self addLabelAtY:142 size:12 color:[NSColor grayColor]];
        _timeLabel   = [self addLabelAtY:120 size:12 color:[NSColor grayColor]];
        _volumeLabel = [self addLabelAtY:98  size:12 color:[NSColor grayColor]];
        _deviceLabel = [self addLabelAtY:76  size:12 color:[NSColor grayColor]];

        _statusLabel = [self addLabelAtY:16 size:12 color:[NSColor redColor]];

        _refreshButton = [[[NSButton alloc] initWithFrame:NSMakeRect(332, 10, 92, 30)] autorelease];
        [_refreshButton setBezelStyle:NSRoundedBezelStyle];
        [_refreshButton setTitle:@"Refresh"];
        [_refreshButton setTarget:self];
        [_refreshButton setAction:@selector(refresh:)];
        [[window contentView] addSubview:_refreshButton];

        [self render];   // draw the "connecting" placeholder
    }
    [window release];
    return self;
}

- (void)dealloc
{
    [self stopPolling];
    [_lastSnapshot release];
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
        return;   // a request is already in flight; skip this tick
    }
    _client = [[DGGopherClient clientWithHost:DG_HOST
                                         port:DG_PORT
                                     selector:DG_SELECTOR] retain];
    [_client setDelegate:self];
    [_client start];
}

#pragma mark - DGGopherClientDelegate

- (void)dgGopherClient:(DGGopherClient *)client didFinishWithData:(NSData *)data
{
    NSString *text = [DGApiParser textFromData:data];
    DGNowSnapshot *snap = [DGApiParser snapshotFromResponse:text];

    [_lastSnapshot release];
    _lastSnapshot = [snap retain];

    [_statusLabel setStringValue:@""];
    [self render];

    [_client release];
    _client = nil;
}

- (void)dgGopherClient:(DGGopherClient *)client didFailWithError:(NSError *)error
{
    // Keep the last-known snapshot on screen; just surface the status and keep
    // polling. Recovery is silent once the server answers again.
    [_statusLabel setStringValue:@"offline — retrying"];

    [_client release];
    _client = nil;
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
