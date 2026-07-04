//
//  DGQueueWindowController.m
//  DeGelato — fio 6
//

#import "DGQueueWindowController.h"
#import "DGApiParser.h"
#import "DGTrackItem.h"
#import "DGFontManager.h"
#import "DGServerPrefs.h"


@interface DGQueueWindowController ()
- (NSString *)clockFromMs:(long long)ms;
@end

@implementation DGQueueWindowController

- (id)init
{
    NSRect frame = NSMakeRect(0, 0, 520, 400);
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask |
                       NSMiniaturizableWindowMask | NSResizableWindowMask;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"DeGelato — Queue"];
    [window setReleasedWhenClosed:NO];
    [window center];

    self = [super initWithWindow:window];
    if (self != nil) {
        NSView *c = [window contentView];
        NSFont *font = [DGFontManager documentFontOfSize:12];

        NSButton *refresh = [[[NSButton alloc] initWithFrame:NSMakeRect(436, 366, 68, 28)] autorelease];
        [refresh setBezelStyle:NSRoundedBezelStyle];
        [refresh setTitle:@"Refresh"];
        [refresh setTarget:self];
        [refresh setAction:@selector(refreshQueue:)];
        [refresh setAutoresizingMask:(NSViewMinXMargin | NSViewMinYMargin)];
        [c addSubview:refresh];

        NSTextField *heading = [[[NSTextField alloc] initWithFrame:NSMakeRect(16, 370, 400, 20)] autorelease];
        [heading setEditable:NO];
        [heading setSelectable:NO];
        [heading setBordered:NO];
        [heading setBezeled:NO];
        [heading setDrawsBackground:NO];
        [heading setFont:[DGFontManager documentFontOfSize:13]];
        [heading setStringValue:@"Up next"];
        [heading setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
        [c addSubview:heading];

        NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(16, 44, 488, 314)] autorelease];
        [scroll setHasVerticalScroller:YES];
        [scroll setBorderType:NSBezelBorder];
        [scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

        _table = [[[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]] autorelease];
        [_table setAllowsMultipleSelection:NO];
        [_table setUsesAlternatingRowBackgroundColors:YES];

        NSTableColumn *numCol = [[[NSTableColumn alloc] initWithIdentifier:@"num"] autorelease];
        [[numCol headerCell] setStringValue:@"#"];
        [numCol setWidth:28];
        NSTableColumn *trackCol = [[[NSTableColumn alloc] initWithIdentifier:@"track"] autorelease];
        [[trackCol headerCell] setStringValue:@"Track"];
        [trackCol setWidth:230];
        NSTableColumn *artistCol = [[[NSTableColumn alloc] initWithIdentifier:@"artist"] autorelease];
        [[artistCol headerCell] setStringValue:@"Artist"];
        [artistCol setWidth:170];
        NSTableColumn *timeCol = [[[NSTableColumn alloc] initWithIdentifier:@"time"] autorelease];
        [[timeCol headerCell] setStringValue:@"Time"];
        [timeCol setWidth:52];

        [[numCol dataCell] setFont:font];
        [[trackCol dataCell] setFont:font];
        [[artistCol dataCell] setFont:font];
        [[timeCol dataCell] setFont:font];

        [_table addTableColumn:numCol];
        [_table addTableColumn:trackCol];
        [_table addTableColumn:artistCol];
        [_table addTableColumn:timeCol];
        [_table setDataSource:self];
        [_table setDelegate:self];
        [scroll setDocumentView:_table];
        [c addSubview:scroll];

        _statusLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(16, 14, 488, 20)] autorelease];
        [_statusLabel setEditable:NO];
        [_statusLabel setSelectable:YES];
        [_statusLabel setBordered:NO];
        [_statusLabel setBezeled:NO];
        [_statusLabel setDrawsBackground:NO];
        [_statusLabel setFont:font];
        [_statusLabel setStringValue:@""];
        [_statusLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
        [c addSubview:_statusLabel];
    }
    [window release];
    return self;
}

- (void)dealloc
{
    [_queueClient cancel];
    [_queueClient release];
    [_items release];
    [super dealloc];
}

- (void)showWindow:(id)sender
{
    [super showWindow:sender];
    [self refreshQueue:sender];
}

- (void)refreshQueue:(id)sender
{
    [_queueClient cancel];
    [_queueClient release];
    _queueClient = [[DGGopherClient clientWithHost:[DGServerPrefs host] port:[DGServerPrefs port]
                                          selector:@"/spot/api/1/queue"] retain];
    [_queueClient setDelegate:self];
    [_statusLabel setStringValue:@"loading…"];
    [_queueClient start];
}

#pragma mark - DGGopherClientDelegate

- (void)dgGopherClient:(DGGopherClient *)client didFinishWithData:(NSData *)data
{
    if (client != _queueClient) {
        return;
    }
    NSString *text = [DGApiParser textFromData:data];
    NSDictionary *fields = [DGApiParser fieldsFromResponse:text];
    [_queueClient release];
    _queueClient = nil;

    NSString *errCode = [fields objectForKey:@"error"];
    if (errCode != nil) {
        [_statusLabel setStringValue:[NSString stringWithFormat:@"error: %@", errCode]];
        return;
    }
    [_items release];
    _items = [[DGTrackItem itemsFromFields:fields] retain];
    [_table reloadData];
    NSUInteger n = [_items count];
    [_statusLabel setStringValue:(n == 0 ? @"queue is empty"
        : [NSString stringWithFormat:@"%lu upcoming", (unsigned long)n])];
}

- (void)dgGopherClient:(DGGopherClient *)client didFailWithError:(NSError *)error
{
    if (client != _queueClient) {
        return;
    }
    [_queueClient release];
    _queueClient = nil;
    [_statusLabel setStringValue:@"could not load the queue — offline?"];
}

#pragma mark - NSTableView data source (informal on 10.5)

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)[_items count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    if (row < 0 || (NSUInteger)row >= [_items count]) {
        return @"";
    }
    DGTrackItem *item = [_items objectAtIndex:(NSUInteger)row];
    NSString *ident = [column identifier];
    if ([ident isEqualToString:@"num"]) {
        return [NSString stringWithFormat:@"%ld", (long)(row + 1)];
    }
    if ([ident isEqualToString:@"track"]) {
        return (item.track ? item.track : @"");
    }
    if ([ident isEqualToString:@"artist"]) {
        return (item.artist ? item.artist : @"");
    }
    if ([ident isEqualToString:@"time"]) {
        return [self clockFromMs:item.durationMs];
    }
    return @"";
}

- (NSString *)clockFromMs:(long long)ms
{
    if (ms < 0) { ms = 0; }
    long long totalSec = ms / 1000;
    return [NSString stringWithFormat:@"%lld:%02lld", totalSec / 60, totalSec % 60];
}

@end
