//
//  DGPreferencesController.m
//  DeGelato — fio 15
//

#import "DGPreferencesController.h"
#import "DGServerPrefs.h"
#import "DGApiParser.h"
#import "DGFontManager.h"

#define DG_PREFS_PROBE_SELECTOR @"/spot/api/1/now"

@interface DGPreferencesController ()
- (NSTextField *)addLabelAtX:(CGFloat)x y:(CGFloat)y width:(CGFloat)w
                        align:(NSTextAlignment)align color:(NSColor *)color;
- (NSTextField *)addFieldAtX:(CGFloat)x y:(CGFloat)y width:(CGFloat)w;
- (void)populateFromPrefs;
- (void)revalidate;
- (void)onTest:(id)sender;
- (void)onSave:(id)sender;
- (void)cancelTest;
- (long long)nowEpochMs;
@end

@implementation DGPreferencesController

- (id)init
{
    NSRect frame = NSMakeRect(0, 0, 420, 190);
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"DeGelato — Preferences"];
    [window setReleasedWhenClosed:NO];
    [window center];

    self = [super initWithWindow:window];
    if (self != nil) {
        NSTextField *serverLabel = [self addLabelAtX:16 y:152 width:388
            align:NSLeftTextAlignment color:[NSColor controlTextColor]];
        [serverLabel setStringValue:@"gopher-spot server"];

        NSTextField *hostLabel = [self addLabelAtX:16 y:120 width:60
            align:NSRightTextAlignment color:[NSColor controlTextColor]];
        [hostLabel setStringValue:@"Host:"];
        _hostField = [self addFieldAtX:84 y:118 width:320];

        NSTextField *portLabel = [self addLabelAtX:16 y:88 width:60
            align:NSRightTextAlignment color:[NSColor controlTextColor]];
        [portLabel setStringValue:@"Port:"];
        _portField = [self addFieldAtX:84 y:86 width:80];

        _testButton = [[[NSButton alloc] initWithFrame:NSMakeRect(174, 84, 130, 26)] autorelease];
        [_testButton setBezelStyle:NSRoundedBezelStyle];
        [_testButton setTitle:@"Test Connection"];
        [_testButton setTarget:self];
        [_testButton setAction:@selector(onTest:)];
        [[window contentView] addSubview:_testButton];

        _resultLabel = [self addLabelAtX:16 y:52 width:388 align:NSLeftTextAlignment
                                   color:[NSColor grayColor]];

        _saveButton = [[[NSButton alloc] initWithFrame:NSMakeRect(316, 12, 88, 30)] autorelease];
        [_saveButton setBezelStyle:NSRoundedBezelStyle];
        [_saveButton setTitle:@"Save"];
        [_saveButton setKeyEquivalent:@"\r"];   // Enter saves
        [_saveButton setTarget:self];
        [_saveButton setAction:@selector(onSave:)];
        [[window contentView] addSubview:_saveButton];

        NSButton *cancel = [[[NSButton alloc] initWithFrame:NSMakeRect(220, 12, 88, 30)] autorelease];
        [cancel setBezelStyle:NSRoundedBezelStyle];
        [cancel setTitle:@"Cancel"];
        [cancel setKeyEquivalent:@"\033"];      // Esc cancels
        [cancel setTarget:self];
        [cancel setAction:@selector(close)];
        [[window contentView] addSubview:cancel];

        [self populateFromPrefs];
    }
    [window release];
    return self;
}

- (void)dealloc
{
    [self cancelTest];
    [super dealloc];
}

- (NSTextField *)addLabelAtX:(CGFloat)x y:(CGFloat)y width:(CGFloat)w
                        align:(NSTextAlignment)align color:(NSColor *)color
{
    NSTextField *label = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(x, y, w, 18)] autorelease];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBordered:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setAlignment:align];
    [label setFont:[DGFontManager documentFontOfSize:12]];
    [label setTextColor:color];
    [label setStringValue:@""];
    [[[self window] contentView] addSubview:label];
    return label;
}

- (NSTextField *)addFieldAtX:(CGFloat)x y:(CGFloat)y width:(CGFloat)w
{
    NSTextField *field = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(x, y, w, 22)] autorelease];
    [field setFont:[DGFontManager documentFontOfSize:12]];
    [field setDelegate:self];   // controlTextDidChange: → revalidate
    [[[self window] contentView] addSubview:field];
    return field;
}

- (void)showWindow:(id)sender
{
    [self populateFromPrefs];   // reflect the current stored values each time
    [super showWindow:sender];
}

- (void)populateFromPrefs
{
    [_hostField setStringValue:[DGServerPrefs host]];
    [_portField setStringValue:[NSString stringWithFormat:@"%ld", (long)[DGServerPrefs port]]];
    [_resultLabel setStringValue:@""];
    [self revalidate];
}

// controlTextDidChange: (informal NSControl delegate) — gate Save on validity.
- (void)controlTextDidChange:(NSNotification *)note
{
    [self revalidate];
}

- (void)revalidate
{
    BOOL ok = [DGServerPrefs isValidHost:[_hostField stringValue]
                                    port:(NSInteger)[_portField integerValue]];
    [_saveButton setEnabled:ok];
    [_testButton setEnabled:ok];
}

#pragma mark - Test Connection

- (void)onTest:(id)sender
{
    [self cancelTest];
    NSString *host = [_hostField stringValue];
    NSInteger port = (NSInteger)[_portField integerValue];
    if (![DGServerPrefs isValidHost:host port:port]) {
        [_resultLabel setTextColor:[NSColor redColor]];
        [_resultLabel setStringValue:@"enter a valid host and port (1–65535)"];
        return;
    }
    [_resultLabel setTextColor:[NSColor grayColor]];
    [_resultLabel setStringValue:@"testing…"];
    _testStartMs = [self nowEpochMs];
    _testClient = [[DGGopherClient clientWithHost:host port:port
                                         selector:DG_PREFS_PROBE_SELECTOR] retain];
    [_testClient setDelegate:self];
    [_testClient start];
}

- (void)cancelTest
{
    [_testClient cancel];
    [_testClient release];
    _testClient = nil;
}

- (void)dgGopherClient:(DGGopherClient *)client didFinishWithData:(NSData *)data
{
    if (client != _testClient) { return; }
    long long ms = [self nowEpochMs] - _testStartMs;
    NSString *text = [DGApiParser textFromData:data];
    NSDictionary *fields = [DGApiParser fieldsFromResponse:text];
    BOOL looksLikeNow = ([fields objectForKey:@"state"] != nil ||
                         [fields objectForKey:@"api"] != nil);
    [_testClient release];
    _testClient = nil;
    if (looksLikeNow) {
        [_resultLabel setTextColor:[NSColor colorWithCalibratedRed:0.0 green:0.5 blue:0.0 alpha:1.0]];
        [_resultLabel setStringValue:[NSString stringWithFormat:@"connected — %lld ms", ms]];
    } else {
        [_resultLabel setTextColor:[NSColor redColor]];
        [_resultLabel setStringValue:@"reached the host, but it isn't gopher-spot"];
    }
}

- (void)dgGopherClient:(DGGopherClient *)client didFailWithError:(NSError *)error
{
    if (client != _testClient) { return; }
    [_testClient release];
    _testClient = nil;
    [_resultLabel setTextColor:[NSColor redColor]];
    [_resultLabel setStringValue:[NSString stringWithFormat:@"failed: %@",
        [error localizedDescription]]];
}

#pragma mark - Save

- (void)onSave:(id)sender
{
    NSString *host = [_hostField stringValue];
    NSInteger port = (NSInteger)[_portField integerValue];
    if (![DGServerPrefs isValidHost:host port:port]) {
        [_resultLabel setTextColor:[NSColor redColor]];
        [_resultLabel setStringValue:@"enter a valid host and port (1–65535)"];
        return;
    }
    BOOL changed = [DGServerPrefs saveHost:host port:port];
    [self cancelTest];
    [self close];
    if (changed) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName:DGServerPrefsDidChangeNotification object:self];
    }
}

- (long long)nowEpochMs
{
    return (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

@end
