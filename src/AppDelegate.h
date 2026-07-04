//
//  AppDelegate.h
//  DeGelato — fio 1
//

#import <Cocoa/Cocoa.h>

@class DGNowPlayingWindowController;
@class DGLibraryWindowController;
@class DGPreferencesController;

@interface AppDelegate : NSObject {
    DGNowPlayingWindowController *_nowPlaying;
    DGLibraryWindowController    *_library;
    DGPreferencesController      *_prefs;
}
@end
