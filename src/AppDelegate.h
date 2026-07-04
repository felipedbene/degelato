//
//  AppDelegate.h
//  DeGelato — fio 1
//

#import <Cocoa/Cocoa.h>
#import "DGMediaKeyTap.h"

@class DGNowPlayingWindowController;
@class DGLibraryWindowController;
@class DGPreferencesController;

@interface AppDelegate : NSObject <DGMediaKeyTapDelegate> {
    DGNowPlayingWindowController *_nowPlaying;
    DGLibraryWindowController    *_library;
    DGPreferencesController      *_prefs;
    DGMediaKeyTap               *_mediaKeyTap;
}
@end
