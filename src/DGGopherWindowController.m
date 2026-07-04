//
//  DGGopherWindowController.m
//  DeGelato — fio 20
//

#import "DGGopherWindowController.h"
#import "DGGopherResource.h"
#import "DGGopherItem.h"
#import "DGGopherMenuParser.h"
#import "DGApiParser.h"
#import "DGFontManager.h"
#import "DGAttributedStringRenderer.h"
#import "AppDelegate.h"

#define DG_GOPHER_STATUS_H 22.0
#define DG_GOPHER_W 640.0
#define DG_GOPHER_H 480.0

@interface DGGopherWindowController ()
- (void)buildChrome;
- (void)showSpinner:(BOOL)on;
- (void)renderMenu;
- (void)renderText:(NSString *)text;
- (void)activateRow:(id)sender;
- (NSString *)tagForItem:(DGGopherItem *)item;
@end

@implementation DGGopherWindowController

- (id)initWithResource:(DGGopherResource *)resource parentWindow:(NSWindow *)parent
{
    NSRect frame = NSMakeRect(0, 0, DG_GOPHER_W, DG_GOPHER_H);
    NSUInteger style = (NSTitledWindowMask | NSClosableWindowMask |
                        NSMiniaturizableWindowMask | NSResizableWindowMask |
                        NSTexturedBackgroundWindowMask);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    [window setReleasedWhenClosed:NO];
    [window setMinSize:NSMakeSize(360, 240)];

    self = [super initWithWindow:window];
    [window release];
    if (self == nil) {
        return nil;
    }

    _resource = [resource retain];
    _menuMode = ([resource type] != '0');

    NSString *title = [resource displayString];
    if ([title length] == 0) { title = [resource host]; }
    [window setTitle:(title ? title : @"Gopher")];
    [window setDelegate:self];

    // Cascade down-right from the parent (TurboGopher style), else center.
    if (parent != nil) {
        NSRect p = [parent frame];
        [window setFrameTopLeftPoint:NSMakePoint(NSMinX(p) + 24.0, NSMaxY(p) - 24.0)];
    } else {
        [window center];
    }

    [self buildChrome];
    return self;
}

- (void)dealloc
{
    [_client cancel];
    [_client release];
    [_resource release];
    [_items release];
    [super dealloc];
}

- (void)buildChrome
{
    NSView *content = [[self window] contentView];
    NSRect b = [content bounds];

    _statusLabel = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(6, 3, b.size.width - 12, DG_GOPHER_STATUS_H - 5)] autorelease];
    [_statusLabel setBezeled:NO];
    [_statusLabel setBordered:NO];
    [_statusLabel setEditable:NO];
    [_statusLabel setSelectable:YES];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setFont:[NSFont systemFontOfSize:10.0]];
    [_statusLabel setTextColor:[NSColor darkGrayColor]];
    [_statusLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
    [_statusLabel setStringValue:[_resource locationSummary]];
    [content addSubview:_statusLabel];

    NSRect bodyRect = NSMakeRect(0, DG_GOPHER_STATUS_H,
                                 b.size.width, b.size.height - DG_GOPHER_STATUS_H);
    _bodyArea = [[[NSView alloc] initWithFrame:bodyRect] autorelease];
    [_bodyArea setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [content addSubview:_bodyArea];

    _spinner = [[[NSProgressIndicator alloc]
        initWithFrame:NSMakeRect((bodyRect.size.width - 32) / 2,
                                 (bodyRect.size.height - 32) / 2, 32, 32)] autorelease];
    [_spinner setStyle:NSProgressIndicatorSpinningStyle];
    [_spinner setDisplayedWhenStopped:NO];
    [_spinner setAutoresizingMask:(NSViewMinXMargin | NSViewMaxXMargin |
                                   NSViewMinYMargin | NSViewMaxYMargin)];
    [_bodyArea addSubview:_spinner];

    _scroll = [[[NSScrollView alloc] initWithFrame:[_bodyArea bounds]] autorelease];
    [_scroll setHasVerticalScroller:YES];
    [_scroll setHasHorizontalScroller:YES];
    [_scroll setAutohidesScrollers:YES];
    [_scroll setBorderType:NSNoBorder];
    [_scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_bodyArea addSubview:_scroll];
}

- (void)showSpinner:(BOOL)on
{
    if (on) { [_spinner startAnimation:nil]; } else { [_spinner stopAnimation:nil]; }
}

- (DGGopherResource *)resource
{
    return _resource;
}

- (void)loadLocalMenuText:(NSString *)text
{
    // No fetch: render a locally-held gophermap (the bookmarks file).
    _menuMode = YES;
    [_items release];
    _items = [[DGGopherMenuParser parseMenu:(text ? text : @"")] retain];
    [self renderMenu];
}

- (void)load
{
    [self showSpinner:YES];
    [_client cancel];
    [_client release];
    _client = [[DGGopherClient clientWithHost:[_resource host] port:[_resource port]
                                     selector:[_resource selector]] retain];
    [_client setDelegate:self];
    [_client start];
}

#pragma mark - DGGopherClientDelegate

- (void)dgGopherClient:(DGGopherClient *)client didFinishWithData:(NSData *)data
{
    if (client != _client) { return; }
    [self showSpinner:NO];
    [_client release];
    _client = nil;

    if (_menuMode) {
        [_items release];
        _items = [[DGGopherMenuParser parseMenuData:data] retain];
        [self renderMenu];
    } else {
        [self renderText:[DGGopherMenuParser stringFromData:data]];
    }
}

- (void)dgGopherClient:(DGGopherClient *)client didFailWithError:(NSError *)error
{
    if (client != _client) { return; }
    [self showSpinner:NO];
    [_client release];
    _client = nil;
    [_statusLabel setStringValue:[NSString stringWithFormat:@"failed: %@",
        [error localizedDescription]]];
}

#pragma mark - Rendering

- (void)renderMenu
{
    _textView = nil;
    _table = [[[NSTableView alloc] initWithFrame:[[_scroll contentView] bounds]] autorelease];
    [_table setAllowsMultipleSelection:NO];
    [_table setRowHeight:16.0];
    [_table setHeaderView:nil];
    [_table setIntercellSpacing:NSMakeSize(0, 0)];

    NSTableColumn *col = [[[NSTableColumn alloc] initWithIdentifier:@"row"] autorelease];
    NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
    [cell setFont:[DGFontManager documentFontOfSize:12]];
    [col setDataCell:cell];
    [col setWidth:2000.0];   // wide so preformatted ASCII/art never wraps
    [_table addTableColumn:col];
    [_table setDataSource:self];
    [_table setDelegate:self];
    [_table setTarget:self];
    [_table setDoubleAction:@selector(activateRow:)];
    [_scroll setDocumentView:_table];
    [_table reloadData];
    [_statusLabel setStringValue:[_resource locationSummary]];
}

- (void)renderText:(NSString *)text
{
    _table = nil;
    NSTextView *tv = [[[NSTextView alloc] initWithFrame:[[_scroll contentView] bounds]] autorelease];
    [tv setEditable:NO];
    [tv setRichText:YES];
    // Dark terminal-style background: ANSI-colored gophermaps assume it, and the
    // renderer's light default keeps uncolored text readable.
    [tv setBackgroundColor:[NSColor blackColor]];
    // Non-wrapping so preformatted / ASCII-art / braille maps keep their columns.
    [tv setHorizontallyResizable:YES];
    [tv setVerticallyResizable:YES];
    [[tv textContainer] setContainerSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [[tv textContainer] setWidthTracksTextView:NO];
    [tv setMinSize:NSMakeSize(0, 0)];
    [tv setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];

    NSAttributedString *attr = [DGAttributedStringRenderer
        attributedStringFromString:(text ? text : @"")
                              font:[DGFontManager documentFontOfSize:12]];
    [[tv textStorage] setAttributedString:attr];

    _textView = tv;
    [_scroll setDocumentView:tv];
    [_statusLabel setStringValue:[_resource locationSummary]];
}

- (NSString *)tagForItem:(DGGopherItem *)item
{
    switch ([item kind]) {
        case DGGopherItemKindMenu:    return @"[DIR]";
        case DGGopherItemKindText:    return @"[TXT]";
        case DGGopherItemKindSearch:  return @"[FND]";
        case DGGopherItemKindSound:   return @"[SND]";
        case DGGopherItemKindHTML:    return @"[WWW]";
        case DGGopherItemKindError:   return @"[ERR]";
        case DGGopherItemKindInfo:    return @"     ";   // info: no tag, just aligned
        case DGGopherItemKindUnknown:
        default:                      return @"[ ? ]";
    }
}

- (void)activateRow:(id)sender
{
    NSInteger row = [_table clickedRow];
    if (row < 0) { row = [_table selectedRow]; }
    if (row < 0 || (NSUInteger)row >= [_items count]) { return; }
    DGGopherItem *item = [_items objectAtIndex:(NSUInteger)row];
    if (![item isClickable]) { return; }

    if ([item kind] == DGGopherItemKindHTML) {
        NSString *url = [item externalURLString];
        if ([url length] > 0) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
        }
        return;
    }
    AppDelegate *app = (AppDelegate *)[NSApp delegate];

    if ([item kind] == DGGopherItemKindSearch) {
        // Type 7: prompt for a query, then request "selector<TAB>query" as a menu.
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Search"];
        [alert setInformativeText:([item displayString] ? [item displayString] : @"")];
        [alert addButtonWithTitle:@"Search"];
        [alert addButtonWithTitle:@"Cancel"];
        NSTextField *input = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)] autorelease];
        [alert setAccessoryView:input];
        if ([alert runModal] != NSAlertFirstButtonReturn) { return; }
        NSString *sel = [NSString stringWithFormat:@"%@\t%@",
                         ([item selector] ? [item selector] : @""), [input stringValue]];
        DGGopherResource *sres = [DGGopherResource resourceWithHost:[item host]
            port:[item port] type:'1' selector:sel display:[item displayString]];
        [app openGopherResource:sres fromWindow:[self window]];
        return;
    }

    // Text / menu / sound → open a new cascaded gopher window.
    DGGopherResource *res = [DGGopherResource resourceWithItem:item];
    if ([app respondsToSelector:@selector(openGopherResource:fromWindow:)]) {
        [app openGopherResource:res fromWindow:[self window]];
    }
}

#pragma mark - NSTableView data source (informal)

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)[_items count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    if (row < 0 || (NSUInteger)row >= [_items count]) { return @""; }
    DGGopherItem *item = [_items objectAtIndex:(NSUInteger)row];
    NSString *disp = [item displayString];
    return [NSString stringWithFormat:@"%@ %@", [self tagForItem:item], (disp ? disp : @"")];
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    if (row < 0 || (NSUInteger)row >= [_items count]) { return NO; }
    return [[_items objectAtIndex:(NSUInteger)row] isClickable];
}

@end
