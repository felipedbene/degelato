//
//  DGLibraryWindowController.m
//  DeGelato — fio 17
//

#import "DGLibraryWindowController.h"
#import "DGApiParser.h"
#import "DGTrackItem.h"
#import "DGPlaylistItem.h"
#import "DGTrackCell.h"
#import "DGFontManager.h"
#import "DGServerPrefs.h"
#import "DGCoverCache.h"

#define DG_THUMB_SIZE 64

// Percent-escape a string for a gopher selector query value (delimiters + all
// high bytes), so a query or a spotify: uri can't break the selector.
static NSString *DGPercentEscape(NSString *s)
{
    if (s == nil) {
        return @"";
    }
    CFStringRef esc = CFURLCreateStringByAddingPercentEscapes(
        NULL, (CFStringRef)s, NULL, CFSTR("?=&+ :#%\t\r\n"), kCFStringEncodingUTF8);
    return [(NSString *)esc autorelease];
}

@interface DGLibraryWindowController ()
- (void)onMode:(id)sender;
- (void)doSearch:(id)sender;
- (void)playSelected:(id)sender;
- (void)addSelected:(id)sender;
- (void)refresh:(id)sender;
- (void)fetchQueue;
- (void)fetchPlaylists;
- (void)updateChrome;
- (NSUInteger)currentCount;
- (void)ensureThumbForAlbum:(NSString *)albumId;
- (NSString *)albumIdForCoverClient:(DGGopherClient *)c;
- (NSString *)clockFromMs:(long long)ms;
@end

@implementation DGLibraryWindowController

- (id)init
{
    NSRect frame = NSMakeRect(0, 0, 560, 470);
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask |
                       NSMiniaturizableWindowMask | NSResizableWindowMask;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"DeGelato — Library"];
    [window setReleasedWhenClosed:NO];
    [window center];

    self = [super initWithWindow:window];
    if (self != nil) {
        NSView *c = [window contentView];
        NSFont *font = [DGFontManager documentFontOfSize:12];

        _modeControl = [[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(16, 434, 300, 24)] autorelease];
        [_modeControl setSegmentCount:3];
        [_modeControl setLabel:@"Busca"     forSegment:0];
        [_modeControl setLabel:@"Fila"      forSegment:1];
        [_modeControl setLabel:@"Playlists" forSegment:2];
        [_modeControl setSelectedSegment:0];
        [_modeControl setTarget:self];
        [_modeControl setAction:@selector(onMode:)];
        [_modeControl setAutoresizingMask:NSViewMinYMargin];
        [c addSubview:_modeControl];

        _queryField = [[[NSSearchField alloc] initWithFrame:NSMakeRect(16, 400, 452, 26)] autorelease];
        [_queryField setTarget:self];
        [_queryField setAction:@selector(doSearch:)];
        [_queryField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
        [c addSubview:_queryField];

        _searchButton = [[[NSButton alloc] initWithFrame:NSMakeRect(476, 399, 68, 28)] autorelease];
        [_searchButton setBezelStyle:NSRoundedBezelStyle];
        [_searchButton setTitle:@"Search"];
        [_searchButton setTarget:self];
        [_searchButton setAction:@selector(doSearch:)];
        [_searchButton setAutoresizingMask:(NSViewMinXMargin | NSViewMinYMargin)];
        [c addSubview:_searchButton];

        NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(16, 44, 528, 348)] autorelease];
        [scroll setHasVerticalScroller:YES];
        [scroll setBorderType:NSBezelBorder];
        [scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

        _table = [[[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]] autorelease];
        [_table setAllowsMultipleSelection:NO];
        [_table setRowHeight:DG_TRACK_ROW_HEIGHT];
        [_table setHeaderView:nil];   // single-column cell list, no header
        [_table setUsesAlternatingRowBackgroundColors:YES];

        NSTableColumn *col = [[[NSTableColumn alloc] initWithIdentifier:@"row"] autorelease];
        [col setDataCell:[[[DGTrackCell alloc] init] autorelease]];
        [col setWidth:510];
        [col setResizingMask:NSTableColumnAutoresizingMask];
        [_table addTableColumn:col];
        [_table setDataSource:self];
        [_table setDelegate:self];
        [_table setTarget:self];
        [_table setDoubleAction:@selector(playSelected:)];
        [scroll setDocumentView:_table];
        [c addSubview:scroll];

        _addButton = [[[NSButton alloc] initWithFrame:NSMakeRect(16, 8, 120, 28)] autorelease];
        [_addButton setBezelStyle:NSRoundedBezelStyle];
        [_addButton setTitle:@"Add to Queue"];
        [_addButton setTarget:self];
        [_addButton setAction:@selector(addSelected:)];
        [_addButton setAutoresizingMask:NSViewMaxYMargin];
        [c addSubview:_addButton];

        _refreshButton = [[[NSButton alloc] initWithFrame:NSMakeRect(456, 8, 88, 28)] autorelease];
        [_refreshButton setBezelStyle:NSRoundedBezelStyle];
        [_refreshButton setTitle:@"Refresh"];
        [_refreshButton setTarget:self];
        [_refreshButton setAction:@selector(refresh:)];
        [_refreshButton setAutoresizingMask:(NSViewMinXMargin | NSViewMaxYMargin)];
        [c addSubview:_refreshButton];

        _statusLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect(146, 12, 300, 20)] autorelease];
        [_statusLabel setEditable:NO];
        [_statusLabel setSelectable:YES];
        [_statusLabel setBordered:NO];
        [_statusLabel setBezeled:NO];
        [_statusLabel setDrawsBackground:NO];
        [_statusLabel setFont:font];
        [_statusLabel setStringValue:@"search · double-click to play"];
        [_statusLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
        [c addSubview:_statusLabel];

        _coverClients = [[NSMutableDictionary alloc] init];
        _mode = DGLibraryModeBusca;
        [self updateChrome];
    }
    [window release];
    return self;
}

- (void)dealloc
{
    [_searchClient cancel];    [_searchClient release];
    [_queueClient cancel];     [_queueClient release];
    [_playlistsClient cancel]; [_playlistsClient release];
    [_playClient cancel];      [_playClient release];
    [_addClient cancel];       [_addClient release];
    {
        NSArray *keys = [_coverClients allKeys];
        NSUInteger i;
        for (i = 0; i < [keys count]; i++) {
            [[_coverClients objectForKey:[keys objectAtIndex:i]] cancel];
        }
    }
    [_coverClients release];
    [_results release];
    [_queue release];
    [_playlists release];
    [super dealloc];
}

- (void)showInMode:(NSInteger)mode
{
    _mode = mode;
    [_modeControl setSelectedSegment:mode];
    [self updateChrome];
    [_table reloadData];
    if (mode == DGLibraryModeFila) {
        [self fetchQueue];
    } else if (mode == DGLibraryModePlaylists && _playlists == nil) {
        [self fetchPlaylists];
    }
    [self showWindow:self];
    [[self window] makeKeyAndOrderFront:self];
    if (mode == DGLibraryModeBusca) {
        [[self window] makeFirstResponder:_queryField];
    }
}

#pragma mark - Mode / chrome

- (void)onMode:(id)sender
{
    _mode = [_modeControl selectedSegment];
    [self updateChrome];
    [_table reloadData];
    if (_mode == DGLibraryModeFila) {
        [self fetchQueue];
    } else if (_mode == DGLibraryModePlaylists && _playlists == nil) {
        [self fetchPlaylists];
    }
}

- (void)updateChrome
{
    BOOL busca = (_mode == DGLibraryModeBusca);
    [_queryField setHidden:!busca];
    [_searchButton setHidden:!busca];
    [_addButton setEnabled:busca];
    [_refreshButton setEnabled:(_mode != DGLibraryModeBusca)];
    if (busca) {
        [_statusLabel setStringValue:@"search · double-click to play"];
    } else if (_mode == DGLibraryModeFila) {
        [_statusLabel setStringValue:@"up next"];
    } else {
        [_statusLabel setStringValue:@"double-click a playlist to play it"];
    }
}

- (NSUInteger)currentCount
{
    if (_mode == DGLibraryModeBusca)     { return [_results count]; }
    if (_mode == DGLibraryModeFila)      { return [_queue count]; }
    if (_mode == DGLibraryModePlaylists) { return [_playlists count]; }
    return 0;
}

#pragma mark - Fetch

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

- (void)fetchQueue
{
    [_queueClient cancel];
    [_queueClient release];
    _queueClient = [[DGGopherClient clientWithHost:[DGServerPrefs host] port:[DGServerPrefs port]
        selector:@"/spot/api/1/queue"] retain];
    [_queueClient setDelegate:self];
    [_queueClient start];
}

- (void)fetchPlaylists
{
    [_playlistsClient cancel];
    [_playlistsClient release];
    _playlistsClient = [[DGGopherClient clientWithHost:[DGServerPrefs host] port:[DGServerPrefs port]
        selector:@"/spot/api/1/playlists"] retain];
    [_playlistsClient setDelegate:self];
    [_statusLabel setStringValue:@"loading playlists…"];
    [_playlistsClient start];
}

- (void)refresh:(id)sender
{
    if (_mode == DGLibraryModeFila)           { [self fetchQueue]; }
    else if (_mode == DGLibraryModePlaylists) { [self fetchPlaylists]; }
}

#pragma mark - Play / queue actions

- (void)playSelected:(id)sender
{
    NSInteger row = [_table selectedRow];
    if (row < 0) {
        return;
    }
    NSString *selector = nil;
    NSString *status = nil;

    if (_mode == DGLibraryModeBusca) {
        if ((NSUInteger)row >= [_results count]) { return; }
        DGTrackItem *it = [_results objectAtIndex:(NSUInteger)row];
        if ([it.uri length] == 0) { return; }
        selector = [NSString stringWithFormat:@"/spot/play?uri=%@", DGPercentEscape(it.uri)];
        status = [NSString stringWithFormat:@"playing  %@", (it.track ? it.track : @"?")];
    } else if (_mode == DGLibraryModePlaylists) {
        if ((NSUInteger)row >= [_playlists count]) { return; }
        DGPlaylistItem *pl = [_playlists objectAtIndex:(NSUInteger)row];
        NSString *ctx = [pl contextURI];
        if ([ctx length] == 0) { return; }
        selector = [NSString stringWithFormat:@"/spot/play?context_uri=%@&offset=0",
                    DGPercentEscape(ctx)];
        status = [NSString stringWithFormat:@"playing  %@", (pl.name ? pl.name : @"playlist")];
    } else {
        return;   // Fila is read-only
    }

    [_playClient cancel];
    [_playClient release];
    _playClient = [[DGGopherClient clientWithHost:[DGServerPrefs host] port:[DGServerPrefs port]
        selector:selector] retain];
    [_playClient setDelegate:self];
    [_statusLabel setStringValue:status];
    [_playClient start];
}

- (void)addSelected:(id)sender
{
    if (_mode != DGLibraryModeBusca) { return; }
    NSInteger row = [_table selectedRow];
    if (row < 0 || (NSUInteger)row >= [_results count]) {
        [_statusLabel setStringValue:@"select a result to queue"];
        return;
    }
    DGTrackItem *it = [_results objectAtIndex:(NSUInteger)row];
    if ([it.uri length] == 0) { return; }
    [_addClient cancel];
    [_addClient release];
    _addClient = [[DGGopherClient clientWithHost:[DGServerPrefs host] port:[DGServerPrefs port]
        selector:[NSString stringWithFormat:@"/spot/api/1/queue/add?%@", DGPercentEscape(it.uri)]] retain];
    [_addClient setDelegate:self];
    [_statusLabel setStringValue:[NSString stringWithFormat:@"queued  %@", (it.track ? it.track : @"?")]];
    [_addClient start];
}

#pragma mark - Thumbnails

- (void)ensureThumbForAlbum:(NSString *)albumId
{
    if ([albumId length] == 0) { return; }
    if ([[DGCoverCache sharedCache] coverDataForAlbum:albumId size:DG_THUMB_SIZE] != nil) { return; }
    if ([_coverClients objectForKey:albumId] != nil) { return; }
    DGGopherClient *c = [DGGopherClient clientWithHost:[DGServerPrefs host] port:[DGServerPrefs port]
        selector:[NSString stringWithFormat:@"/spot/api/1/cover/%@/%d", albumId, DG_THUMB_SIZE]];
    [_coverClients setObject:c forKey:albumId];   // dict retains it across the fetch
    [c setDelegate:self];
    [c start];
}

- (NSString *)albumIdForCoverClient:(DGGopherClient *)c
{
    NSArray *keys = [_coverClients allKeys];
    NSUInteger i;
    for (i = 0; i < [keys count]; i++) {
        NSString *k = [keys objectAtIndex:i];
        if ([_coverClients objectForKey:k] == c) {
            return k;
        }
    }
    return nil;
}

#pragma mark - DGGopherClientDelegate

- (void)dgGopherClient:(DGGopherClient *)client didFinishWithData:(NSData *)data
{
    // Cover thumbnails first (there can be several in flight).
    NSString *coverAlbum = [self albumIdForCoverClient:client];
    if (coverAlbum != nil) {
        if ([DGApiParser dataIsJPEG:data]) {
            [[DGCoverCache sharedCache] storeData:data forAlbum:coverAlbum size:DG_THUMB_SIZE];
        }
        [_coverClients removeObjectForKey:coverAlbum];
        [_table reloadData];   // rows now find the cached image
        return;
    }

    NSString *text = [DGApiParser textFromData:data];
    NSDictionary *fields = [DGApiParser fieldsFromResponse:text];
    NSString *errCode = [fields objectForKey:@"error"];

    if (client == _searchClient) {
        [_searchClient release];
        _searchClient = nil;
        [_results release];
        _results = errCode ? nil : [[DGTrackItem itemsFromFields:fields] retain];
        [_table reloadData];
        if (errCode) {
            [_statusLabel setStringValue:[NSString stringWithFormat:@"error: %@", errCode]];
        } else {
            NSUInteger n = [_results count];
            [_statusLabel setStringValue:(n == 0 ? @"no results"
                : [NSString stringWithFormat:@"%lu result%@", (unsigned long)n, (n == 1 ? @"" : @"s")])];
        }
        return;
    }

    if (client == _queueClient) {
        [_queueClient release];
        _queueClient = nil;
        [_queue release];
        _queue = errCode ? nil : [[DGTrackItem itemsFromFields:fields] retain];
        if (_mode == DGLibraryModeFila) { [_table reloadData]; }
        if (errCode) {
            [_statusLabel setStringValue:[NSString stringWithFormat:@"error: %@", errCode]];
        } else if (_mode == DGLibraryModeFila) {
            NSUInteger n = [_queue count];
            [_statusLabel setStringValue:(n == 0 ? @"queue is empty (automatic radio)"
                : [NSString stringWithFormat:@"%lu up next", (unsigned long)n])];
        }
        return;
    }

    if (client == _playlistsClient) {
        [_playlistsClient release];
        _playlistsClient = nil;
        [_playlists release];
        _playlists = errCode ? nil : [[DGPlaylistItem itemsFromFields:fields] retain];
        if (_mode == DGLibraryModePlaylists) { [_table reloadData]; }
        if (errCode) {
            [_statusLabel setStringValue:[NSString stringWithFormat:@"error: %@", errCode]];
        } else if (_mode == DGLibraryModePlaylists) {
            NSUInteger n = [_playlists count];
            [_statusLabel setStringValue:[NSString stringWithFormat:@"%lu playlist%@",
                (unsigned long)n, (n == 1 ? @"" : @"s")]];
        }
        return;
    }

    if (client == _playClient) {
        [_playClient release];
        _playClient = nil;
        if (errCode) {
            [_statusLabel setStringValue:[NSString stringWithFormat:@"error: %@", errCode]];
        }
        return;
    }

    if (client == _addClient) {
        [_addClient release];
        _addClient = nil;
        if (errCode) {
            [_statusLabel setStringValue:[NSString stringWithFormat:@"error: %@", errCode]];
        }
        return;
    }
}

- (void)dgGopherClient:(DGGopherClient *)client didFailWithError:(NSError *)error
{
    NSString *coverAlbum = [self albumIdForCoverClient:client];
    if (coverAlbum != nil) {
        [_coverClients removeObjectForKey:coverAlbum];   // best-effort, no retry
        return;
    }
    if (client == _searchClient)    { [_searchClient release];    _searchClient = nil;    [_statusLabel setStringValue:@"search failed — offline?"]; return; }
    if (client == _queueClient)     { [_queueClient release];     _queueClient = nil;     [_statusLabel setStringValue:@"could not load the queue"]; return; }
    if (client == _playlistsClient) { [_playlistsClient release]; _playlistsClient = nil; [_statusLabel setStringValue:@"could not load playlists"]; return; }
    if (client == _playClient)      { [_playClient release];      _playClient = nil;      [_statusLabel setStringValue:@"could not start playback"]; return; }
    if (client == _addClient)       { [_addClient release];       _addClient = nil;       [_statusLabel setStringValue:@"could not queue the track"]; return; }
}

#pragma mark - NSTableView data source (informal on 10.5)

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)[self currentCount];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    if (row < 0 || (NSUInteger)row >= [self currentCount]) {
        return nil;
    }

    NSString *title = @"";
    NSString *subtitle = @"";
    NSString *albumId = nil;

    if (_mode == DGLibraryModePlaylists) {
        DGPlaylistItem *pl = [_playlists objectAtIndex:(NSUInteger)row];
        title = (pl.name ? pl.name : @"");
        subtitle = [NSString stringWithFormat:@"%ld track%@",
                    (long)pl.tracksLen, (pl.tracksLen == 1 ? @"" : @"s")];
    } else {
        NSArray *tracks = (_mode == DGLibraryModeFila) ? _queue : _results;
        DGTrackItem *it = [tracks objectAtIndex:(NSUInteger)row];
        title = (it.track ? it.track : @"");
        subtitle = (it.artist ? it.artist : @"");
        albumId = it.albumId;
    }

    NSImage *image = nil;
    if ([albumId length] > 0) {
        NSData *jpeg = [[DGCoverCache sharedCache] coverDataForAlbum:albumId size:DG_THUMB_SIZE];
        if (jpeg != nil) {
            image = [[[NSImage alloc] initWithData:jpeg] autorelease];
        } else {
            [self ensureThumbForAlbum:albumId];   // fetch; reloads when it lands
        }
    }

    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:3];
    [d setObject:title forKey:@"title"];
    [d setObject:subtitle forKey:@"subtitle"];
    if (image != nil) { [d setObject:image forKey:@"image"]; }
    return d;
}

- (NSString *)clockFromMs:(long long)ms
{
    if (ms < 0) { ms = 0; }
    long long totalSec = ms / 1000;
    return [NSString stringWithFormat:@"%lld:%02lld", totalSec / 60, totalSec % 60];
}

@end
