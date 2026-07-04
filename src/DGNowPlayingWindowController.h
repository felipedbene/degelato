//
//  DGNowPlayingWindowController.h
//  DeGelato — fio 1
//
//  The single, fully programmatic now-playing window (no NIB). Polls
//  /spot/api/1/now every 2 s over DGGopherClient, renders the snapshot as text
//  in Cascadia Code, and shows an "offline — retrying" status line on failure
//  while continuing to poll — recovering silently when the server returns.
//

#import <Cocoa/Cocoa.h>
#import "DGGopherClient.h"

@class DGNowSnapshot;

@interface DGNowPlayingWindowController : NSWindowController <DGGopherClientDelegate> {
    NSTextField *_trackLabel;
    NSTextField *_artistLabel;
    NSTextField *_albumLabel;
    NSTextField *_stateLabel;
    NSTextField *_timeLabel;
    NSTextField *_volumeLabel;
    NSTextField *_deviceLabel;
    NSTextField *_statusLabel;
    NSButton    *_refreshButton;

    NSTimer         *_pollTimer;
    DGGopherClient  *_client;      // in-flight request, or nil
    DGNowSnapshot   *_lastSnapshot;
}

// Kick off the 2 s poll loop (also fetches immediately).
- (void)startPolling;
- (void)stopPolling;

// Refresh button / manual poke.
- (void)refresh:(id)sender;

@end
