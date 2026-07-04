//
//  DGSearchWindowController.h
//  DeGelato — fio 5
//
//  A separate, fully programmatic window (no NIB): a search field over a table
//  of track results. Enter runs /spot/api/1/search?q=<urlencoded>; double-click
//  (or Play) starts the track on the gopher-spot device via the human
//  /spot/play?uri=<track uri> selector (fire-and-forget). Table data-source and
//  delegate methods are informal (the formal NSTableViewDataSource protocol is
//  10.6+), so they are simply implemented, not declared.
//

#import <Cocoa/Cocoa.h>
#import "DGGopherClient.h"

@interface DGSearchWindowController : NSWindowController <DGGopherClientDelegate> {
    NSSearchField  *_queryField;
    NSTableView    *_table;
    NSTextField    *_statusLabel;

    NSArray        *_results;       // of DGTrackItem
    DGGopherClient *_searchClient;  // in-flight /search
    DGGopherClient *_playClient;    // in-flight /spot/play
    DGGopherClient *_queueClient;   // in-flight /queue/add
}

- (void)doSearch:(id)sender;
- (void)playSelected:(id)sender;
- (void)queueSelected:(id)sender;

@end
