//
//  DGNowPlayingWindowController.h
//  DeGelato — fio 1 + fio 2
//
//  The single, fully programmatic now-playing window (no NIB). Polls
//  /spot/api/1/now every 2 s over DGGopherClient and renders the snapshot as
//  text in Cascadia Code. Fio 2 adds audio: a Play/Stop button that discovers
//  the Icecast MP3 URL from /spot/stream.pls and plays it via DGAudioStreamer,
//  waking the gopher-spot device first (wake?play=1) when /now reports it idle.
//

#import <Cocoa/Cocoa.h>
#import "DGGopherClient.h"
#import "DGAudioStreamer.h"

@class DGNowSnapshot;

// Audio pipeline UI state.
typedef enum {
    DGAudioIdle = 0,
    DGAudioWaking,        // wake?play=1 in flight
    DGAudioDiscovering,   // fetching /spot/stream.pls
    DGAudioBuffering,     // streamer priming buffers
    DGAudioPlaying,
    DGAudioError
} DGAudioUIState;

@interface DGNowPlayingWindowController : NSWindowController
    <DGGopherClientDelegate, DGAudioStreamerDelegate> {
    NSTextField *_trackLabel;
    NSTextField *_artistLabel;
    NSTextField *_albumLabel;
    NSTextField *_stateLabel;
    NSTextField *_timeLabel;
    NSTextField *_volumeLabel;
    NSTextField *_deviceLabel;
    NSTextField *_audioLabel;
    NSTextField *_statusLabel;
    NSButton    *_playButton;
    NSButton    *_refreshButton;

    NSTimer         *_pollTimer;
    DGGopherClient  *_client;       // in-flight /now poll, or nil
    DGGopherClient  *_plsClient;    // in-flight /spot/stream.pls, or nil
    DGGopherClient  *_wakeClient;   // in-flight wake?play=1, or nil
    DGNowSnapshot   *_lastSnapshot;

    DGAudioStreamer *_streamer;
    NSString        *_streamURL;
    DGAudioUIState   _audioState;
    NSString        *_audioError;
}

- (void)startPolling;
- (void)stopPolling;
- (void)refresh:(id)sender;
- (void)togglePlay:(id)sender;

@end
