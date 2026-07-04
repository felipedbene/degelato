//
//  AppDelegate.h
//  DeGelato — fio 1
//

#import <Cocoa/Cocoa.h>

@class DGNowPlayingWindowController;
@class DGSearchWindowController;

@interface AppDelegate : NSObject {
    DGNowPlayingWindowController *_nowPlaying;
    DGSearchWindowController     *_search;
}
@end
