//
//  DGGopherWindowController.h
//  DeGelato — fio 20
//
//  One Gopher resource in one window (TurboGopher-style: every link opens a new
//  cascaded window). Menus render as a monospace table of typed rows; type-0
//  text renders in a scrolling text view (plain for now — ANSI styling is
//  fio 21). Ported/adapted from DeToca's GopherWindowController.
//

#import <Cocoa/Cocoa.h>
#import "DGGopherClient.h"

@class DGGopherResource;

@interface DGGopherWindowController : NSWindowController <DGGopherClientDelegate> {
    DGGopherResource    *_resource;
    DGGopherClient      *_client;
    NSArray             *_items;       // DGGopherItem[] in menu mode
    BOOL                 _menuMode;

    NSView              *_bodyArea;
    NSScrollView        *_scroll;
    NSTableView         *_table;
    NSTextView          *_textView;
    NSTextField         *_statusLabel;
    NSProgressIndicator *_spinner;
}

- (id)initWithResource:(DGGopherResource *)resource parentWindow:(NSWindow *)parent;
- (void)load;                                 // begin the network fetch
- (void)loadLocalMenuText:(NSString *)text;   // render a menu from local text (bookmarks)
- (DGGopherResource *)resource;               // for "Add Bookmark"

@end
