//
//  AppDelegate.h
//  DeGelato — fio 1
//

#import <Cocoa/Cocoa.h>

@class DGNowPlayingWindowController;
@class DGSearchWindowController;
@class DGQueueWindowController;
@class DGPreferencesController;

@interface AppDelegate : NSObject {
    DGNowPlayingWindowController *_nowPlaying;
    DGSearchWindowController     *_search;
    DGQueueWindowController      *_queue;
    DGPreferencesController      *_prefs;
}
@end
