//
//  DGMediaKeyTap.h
//  DeGelato — fio 19
//
//  Global capture of the keyboard's media keys (⏮ ⏯ ⏭) via a Quartz event tap,
//  so the radinho responds even when not frontmost — and so the key is consumed
//  and iTunes doesn't launch on ⏯. A kCGSessionEventTap for NX_SYSDEFINED events,
//  decoding subtype-8 aux-button presses, on a dedicated run-loop thread (so a
//  modal sheet on the main loop can't stall it). Decode → DGMediaKeyRouter (pure);
//  this class is the Quartz/AppKit plumbing only.
//
//  10.5 note: unlike DeToca's 10.6 tap, the session tap here requires "Enable
//  access for assistive devices" (System Preferences ▸ Universal Access). If it's
//  off, -start returns NO and the app simply runs without media-key support.
//

#import <Cocoa/Cocoa.h>
#import "DGMediaKeyRouter.h"

@class DGMediaKeyTap;

@protocol DGMediaKeyTapDelegate <NSObject>
// Called on the MAIN thread for every media-key event we capture (down/up/repeat).
// The delegate applies policy via DGMediaKeyRouter. `kind` is never DGMediaKeyNone.
- (void)mediaKeyTap:(DGMediaKeyTap *)tap
        receivedKey:(DGMediaKeyKind)kind
            pressed:(BOOL)pressed
           isRepeat:(BOOL)isRepeat;
@end

@interface DGMediaKeyTap : NSObject {
    id <DGMediaKeyTapDelegate> _delegate;   // not retained
    CFMachPortRef      _tapPort;
    CFRunLoopSourceRef _runLoopSource;
    CFRunLoopRef       _tapRunLoop;          // the dedicated thread's run loop
    NSThread          *_thread;
}

- (id)initWithDelegate:(id <DGMediaKeyTapDelegate>)delegate;

// Install the tap and begin watching. Returns NO if the tap can't be created
// (assistive access off / OS denied); the app then runs without media keys.
- (BOOL)start;

// Disable and tear down the tap. Safe to call more than once.
- (void)stop;

@end
