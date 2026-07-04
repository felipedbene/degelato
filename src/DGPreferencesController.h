//
//  DGPreferencesController.h
//  DeGelato — fio 15
//
//  The Preferences window (⌘,). One section for now: the gopher-spot server
//  address (host/port), backed by DGServerPrefs. Live-validates to gate Save,
//  offers a non-blocking Test Connection (a real /now round-trip with latency),
//  and on a changed Save posts DGServerPrefsDidChangeNotification so the
//  now-playing window reconnects. Programmatic, no NIB.
//

#import <Cocoa/Cocoa.h>
#import "DGGopherClient.h"

@interface DGPreferencesController : NSWindowController <DGGopherClientDelegate> {
    NSTextField    *_hostField;
    NSTextField    *_portField;
    NSButton       *_testButton;
    NSButton       *_saveButton;
    NSTextField    *_resultLabel;

    DGGopherClient *_testClient;    // in-flight Test Connection probe
    long long       _testStartMs;
}

@end
