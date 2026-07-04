//
//  DGSearchWindowController.m
//  DeGelato — fio 5
//

#import "DGSearchWindowController.h"
#import "DGApiParser.h"
#import "DGTrackItem.h"
#import "DGFontManager.h"
#import "DGServerPrefs.h"


// Percent-escape a string for use as a gopher selector query value: escape the
// gopher/query delimiters and all UTF-8 high bytes, so an arbitrary search string
// (or a spotify: uri) can't break the selector.
static NSString *DGPercentEscape(NSString *s)
{
    if (s == nil) {
        return @"";
    }
    CFStringRef esc = CFURLCreateStringByAddingPercentEscapes(
        NULL, (CFStringRef)s, NULL, CFSTR("?=&+ :#%\t\r\n"), kCFStringEncodingUTF8);
    return [(NSString *)esc autorelease];
}

@interface DGSearchWindowController ()
- (NSString *)clockFromMs:(long long)ms;
@end

@implementation DGSearchWindowController

- (id)init
{
    NSRect frame = NSMakeRect(0, 0, 560, 420);
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask |
                       NSMiniaturizableWindowMask | NSResizableWindowMask;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"DeGelato — Search"];
    [window setReleasedWhenClosed:NO];
    [window center];

    self = [super initWithWindow:window];
    if (self != nil) {
        NSView *c = [window contentView];

        _queryField = [[[NSSearchField alloc] initWithFrame:NSMakeRect(16, 384, 452, 26)] autorelease];
        [_queryField setTarget:self];
        [_queryField setAction:@selector(doSearch:)];
        [_queryField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
        [c addSubview:_queryField];

        NSButton *searchBtn = [[[NSButton alloc] initWithFrame:NSMakeRect(476, 383, 68, 28)] autorelease];
        [searchBtn setBezelStyle:NSRoundedBezelStyle];
        [searchBtn setTitle:@"Search"];
        [searchBtn setTarget:self];
        [searchBtn setAction:@selector(doSearch:)];
        [searchBtn setAutoresizingMask:(NSViewMinXMargin | NSViewMinYMargin)];
        [c addSubview:searchBtn];

        NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(16, 44, 528, 328)] autorelease];
        [scroll setHasVerticalScroller:YES];
        [scroll setBorderType:NSBezelBorder];
        [scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

        _table = [[[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]] autorelease];
        [_table setAllowsMultipleSelection:NO];
        [_table setUsesAlternatingRowBackgroundColors:YES];

        NSTableColumn *trackCol = [[[NSTableColumn alloc] initWithIdentifier:@"track"] autorelease];
        [[trackCol headerCell] setStringValue:@"Track"];
        [trackCol setWidth:250];
        NSTableColumn *artistCol = [[[NSTableColumn alloc] initWithIdentifier:@"artist"] autorelease];
        [[artistCol headerCell] setStringValue:@"Artist"];
        [artistCol setWidth:190];
        NSTableColumn *timeCol = [[[NSTableColumn alloc] initWithIdentifier:@"time"] autorelease];
        [[timeCol headerCell] setStringValue:@"Time"];
        [timeCol setWidth:64];

        NSFont *font = [DGFontManager documentFontOfSize:12];
        [[trackCol dataCell] setFont:font];
        [[artistCol dataCell] setFont:font];
        [[timeCol dataCell] setFont:font];

        [_table addTableColumn:trackCol];
        [_table addTableColumn:artistCol];
        [_table addTableColumn:timeCol];
        [_table setDataSource:self];
        [_table setDelegate:self];
        [_table setTarget:self];
        [_table setDoubleAction:@selector(playSelected:)];
        [scroll setDocumentView:_table];
        [c addSubview:scroll];

        NSButton *queueBtn = [[[NSButton alloc] initWithFrame:NSMakeRect(432, 8, 112, 28)] autorelease];
        [queueBtn setBezelStyle:NSRoundedBezelStyle];
        [queueBtn setTitle:@"Add to Queue"];
        [queueBtn setTarget:self];
        [queueBtn setAction:@selector(queueSelected:)];
        [queueBtn setAutoresizingMask:(NSViewMinXMargin | NSViewMaxYMargin)];
        [c addSubview:queueBtn];

        _statusLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(16, 14, 408, 20)] autorelease];
        [_statusLabel setEditable:NO];
        [_statusLabel setSelectable:YES];
        [_statusLabel setBordered:NO];
        [_statusLabel setBezeled:NO];
        [_statusLabel setDrawsBackground:NO];
        [_statusLabel setFont:font];
        [_statusLabel setStringValue:@"Enter to search · double-click a result to play"];
        [_statusLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
        [c addSubview:_statusLabel];
    }
    [window release];
    return self;
}

- (void)dealloc
{
    [_searchClient cancel];
    [_searchClient release];
    [_playClient cancel];
    [_playClient release];
    [_queueClient cancel];
    [_queueClient release];
    [_results release];
    [super dealloc];
}

#pragma mark - Actions

- (void)doSearch:(id)sender
{
    NSString *q = [[_queryField stringValue]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([q length] == 0) {
        [_statusLabel setStringValue:@"type something to search"];
        return;
    }
    [_searchClient cancel];
    [_searchClient release];
    _searchClient = [[DGGopherClient clientWithHost:[DGServerPrefs host] port:[DGServerPrefs port]
        selector:[NSString stringWithFormat:@"/spot/api/1/search?q=%@", DGPercentEscape(q)]] retain];
    [_searchClient setDelegate:self];
    [_statusLabel setStringValue:@"searching…"];
    [_searchClient start];
}

- (void)playSelected:(id)sender
{
    NSInteger row = [_table selectedRow];
    if (row < 0 || (NSUInteger)row >= [_results count]) {
        return;
    }
    DGTrackItem *item = [_results objectAtIndex:(NSUInteger)row];
    if ([item.uri length] == 0) {
        return;
    }
    [_playClient cancel];
    [_playClient release];
    _playClient = [[DGGopherClient clientWithHost:[DGServerPrefs host] port:[DGServerPrefs port]
        selector:[NSString stringWithFormat:@"/spot/play?uri=%@", DGPercentEscape(item.uri)]] retain];
    [_playClient setDelegate:self];
    [_statusLabel setStringValue:[NSString stringWithFormat:@"playing  %@ — %@",
        (item.track ? item.track : @"?"), (item.artist ? item.artist : @"?")]];
    [_playClient start];
}

- (void)queueSelected:(id)sender
{
    NSInteger row = [_table selectedRow];
    if (row < 0 || (NSUInteger)row >= [_results count]) {
        [_statusLabel setStringValue:@"select a result to queue"];
        return;
    }
    DGTrackItem *item = [_results objectAtIndex:(NSUInteger)row];
    if ([item.uri length] == 0) {
        return;
    }
    [_queueClient cancel];
    [_queueClient release];
    _queueClient = [[DGGopherClient clientWithHost:[DGServerPrefs host] port:[DGServerPrefs port]
        selector:[NSString stringWithFormat:@"/spot/api/1/queue/add?%@", DGPercentEscape(item.uri)]] retain];
    [_queueClient setDelegate:self];
    [_statusLabel setStringValue:[NSString stringWithFormat:@"queued  %@ — %@",
        (item.track ? item.track : @"?"), (item.artist ? item.artist : @"?")]];
    [_queueClient start];
}

#pragma mark - DGGopherClientDelegate

- (void)dgGopherClient:(DGGopherClient *)client didFinishWithData:(NSData *)data
{
    if (client == _searchClient) {
        NSString *text = [DGApiParser textFromData:data];
        NSDictionary *fields = [DGApiParser fieldsFromResponse:text];
        [_searchClient release];
        _searchClient = nil;

        NSString *errCode = [fields objectForKey:@"error"];
        if (errCode != nil) {
            [_results release];
            _results = nil;
            [_table reloadData];
            [_statusLabel setStringValue:[NSString stringWithFormat:@"error: %@", errCode]];
            return;
        }
        [_results release];
        _results = [[DGTrackItem itemsFromFields:fields] retain];
        [_table reloadData];
        NSUInteger n = [_results count];
        [_statusLabel setStringValue:(n == 0 ? @"no results"
            : [NSString stringWithFormat:@"%lu result%@", (unsigned long)n, (n == 1 ? @"" : @"s")])];
        return;
    }

    if (client == _playClient) {
        // The human /spot/play reply is a gophermap we don't render.
        [_playClient release];
        _playClient = nil;
        return;
    }

    if (client == _queueClient) {
        // queue/add returns the fresh /queue; we don't show it here (the Queue
        // window does), and the optimistic "queued …" status already stands. A
        // bad_uri would arrive as an error document — surface it.
        NSDictionary *fields = [DGApiParser fieldsFromResponse:[DGApiParser textFromData:data]];
        NSString *errCode = [fields objectForKey:@"error"];
        [_queueClient release];
        _queueClient = nil;
        if (errCode != nil) {
            [_statusLabel setStringValue:[NSString stringWithFormat:@"error: %@", errCode]];
        }
        return;
    }
}

- (void)dgGopherClient:(DGGopherClient *)client didFailWithError:(NSError *)error
{
    if (client == _searchClient) {
        [_searchClient release];
        _searchClient = nil;
        [_statusLabel setStringValue:@"search failed — offline?"];
        return;
    }
    if (client == _playClient) {
        [_playClient release];
        _playClient = nil;
        [_statusLabel setStringValue:@"could not start playback"];
        return;
    }
    if (client == _queueClient) {
        [_queueClient release];
        _queueClient = nil;
        [_statusLabel setStringValue:@"could not queue the track"];
        return;
    }
}

#pragma mark - NSTableView data source (informal on 10.5)

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)[_results count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    if (row < 0 || (NSUInteger)row >= [_results count]) {
        return @"";
    }
    DGTrackItem *item = [_results objectAtIndex:(NSUInteger)row];
    NSString *ident = [column identifier];
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
