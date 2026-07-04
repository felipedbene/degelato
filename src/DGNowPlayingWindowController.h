//
//  DGNowPlayingWindowController.h
//  DeGelato — fios 1–3
//
//  The single, fully programmatic now-playing window (no NIB).
//   fio 1: poll /spot/api/1/now every 2 s, render the snapshot as text.
//   fio 2: a Listen/Stop button that discovers the Icecast MP3 URL from
//          /spot/stream.pls and plays it (DGAudioStreamer), waking the device
//          (wake?play=1) first when /now is idle.
//   fio 3: transport — Prev / Play-Pause / Next, a seek slider, and a volume
//          slider, each a /spot/api/1 command that returns a fresh /now.
//
//  The "Listen" button controls the LOCAL audio stream (do I hear it here);
//  the transport Play/Pause controls SPOTIFY playback on the device.
//

#import <Cocoa/Cocoa.h>
#import "DGGopherClient.h"
#import "DGAudioStreamer.h"

@class DGNowSnapshot;

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
    NSTextField *_deviceLabel;
    NSTextField *_timeLabel;
    NSTextField *_volumeLabel;
    NSTextField *_audioLabel;
    NSTextField *_statusLabel;

    NSSlider    *_seekSlider;
    NSSlider    *_volumeSlider;
    NSButton    *_prevButton;
    NSButton    *_playPauseButton;
    NSButton    *_nextButton;
    NSButton    *_listenButton;
    NSButton    *_refreshButton;

    NSTimer         *_pollTimer;
    NSTimer         *_tickTimer;    // 1 Hz, advances the seek bar between polls
    DGGopherClient  *_client;       // in-flight /now poll
    DGGopherClient  *_plsClient;    // in-flight /spot/stream.pls
    DGGopherClient  *_wakeClient;   // in-flight wake?play=1
    DGGopherClient  *_cmdClient;    // in-flight transport command
    DGNowSnapshot   *_lastSnapshot;
    BOOL             _userSeeking;  // suppress tick updates while dragging seek

    DGAudioStreamer *_streamer;
    NSString        *_streamURL;
    DGAudioUIState   _audioState;
    NSString        *_audioError;
}

- (void)startPolling;
- (void)stopPolling;
- (void)refresh:(id)sender;

// Audio (fio 2)
- (void)toggleListen:(id)sender;

// Transport (fio 3)
- (void)onPlayPause:(id)sender;
- (void)onPrev:(id)sender;
- (void)onNext:(id)sender;
- (void)onSeek:(id)sender;
- (void)onVolume:(id)sender;

@end
