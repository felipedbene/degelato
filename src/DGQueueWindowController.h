//
//  DGQueueWindowController.h
//  DeGelato — fio 6
//
//  A separate, fully programmatic window listing the upcoming queue
//  (/spot/api/1/queue) as a table of DGTrackItem rows. Refreshed on open and via
//  the Refresh button. Table data-source/delegate methods are informal (the
//  formal NSTableView protocols are 10.6+), so they are implemented, not declared.
//

#import <Cocoa/Cocoa.h>
#import "DGGopherClient.h"

@interface DGQueueWindowController : NSWindowController <DGGopherClientDelegate> {
    NSTableView    *_table;
    NSTextField    *_statusLabel;
    NSArray        *_items;         // of DGTrackItem
    DGGopherClient *_queueClient;   // in-flight /queue
}

- (void)refreshQueue:(id)sender;

@end
