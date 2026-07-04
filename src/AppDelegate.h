//
//  AppDelegate.h
//  DeGelato — fio 1
//

#import <Cocoa/Cocoa.h>
#import "DGMediaKeyTap.h"

@class DGNowPlayingWindowController;
@class DGLibraryWindowController;
@class DGPreferencesController;
@class DGGopherResource;

@interface AppDelegate : NSObject <DGMediaKeyTapDelegate> {
    DGNowPlayingWindowController *_nowPlaying;
    DGLibraryWindowController    *_library;
    DGPreferencesController      *_prefs;
    DGMediaKeyTap               *_mediaKeyTap;
    NSMutableArray              *_gopherWindows;   // open DGGopherWindowControllers
}

// Open a gopher resource in a new cascaded window (called by gopher windows when
// a link is activated, and by the Gopher menu). A nil parent centers.
- (void)openGopherResource:(DGGopherResource *)res fromWindow:(NSWindow *)parent;

@end
