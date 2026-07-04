//
//  AppDelegate.m
//  DeGelato — fio 1
//

#import "AppDelegate.h"
#import "DGNowPlayingWindowController.h"
#import "DGSearchWindowController.h"
#import "DGQueueWindowController.h"

@interface AppDelegate ()
- (void)buildMenuBar;
- (void)openSearch:(id)sender;
- (void)openQueue:(id)sender;
- (void)wakeDevice:(id)sender;
@end

@implementation AppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)note
{
    // Menu bar is fully programmatic (no NIB), matching the DeToca house style.
    [self buildMenuBar];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    _nowPlaying = [[DGNowPlayingWindowController alloc] init];
    [_nowPlaying showWindow:self];
    [[_nowPlaying window] makeKeyAndOrderFront:self];
    [NSApp activateIgnoringOtherApps:YES];
    [_nowPlaying startPolling];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (void)openSearch:(id)sender
{
    if (_search == nil) {
        _search = [[DGSearchWindowController alloc] init];
    }
    [_search showWindow:self];
    [[_search window] makeKeyAndOrderFront:self];
}

- (void)openQueue:(id)sender
{
    if (_queue == nil) {
        _queue = [[DGQueueWindowController alloc] init];
    }
    [_queue showWindow:self];   // -showWindow: refreshes the queue
    [[_queue window] makeKeyAndOrderFront:self];
}

// Wake without changing play/pause state; forwarded to the now-playing window,
// which owns the gopher command path and adopts the returned /now.
- (void)wakeDevice:(id)sender
{
    [_nowPlaying wakeDevice:sender];
}

- (void)dealloc
{
    [_nowPlaying release];
    [_search release];
    [_queue release];
    [super dealloc];
}

- (void)buildMenuBar
{
    NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@"MainMenu"] autorelease];

    // Application menu.
    NSMenuItem *appItem = [[[NSMenuItem alloc] initWithTitle:@"DeGelato"
                                                      action:NULL
                                               keyEquivalent:@""] autorelease];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@"DeGelato"] autorelease];
    [appItem setSubmenu:appMenu];
    [appMenu addItemWithTitle:@"About DeGelato"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide DeGelato"
                       action:@selector(hide:)
                keyEquivalent:@"h"];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit DeGelato"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];

    // Controls menu (fio 5): search + explicit wake.
    NSMenuItem *ctlItem = [[[NSMenuItem alloc] initWithTitle:@"Controls"
                                                      action:NULL
                                               keyEquivalent:@""] autorelease];
    [mainMenu addItem:ctlItem];
    NSMenu *ctlMenu = [[[NSMenu alloc] initWithTitle:@"Controls"] autorelease];
    [ctlItem setSubmenu:ctlMenu];
    [[ctlMenu addItemWithTitle:@"Search…"
                        action:@selector(openSearch:)
                 keyEquivalent:@"f"] setTarget:self];
    [[ctlMenu addItemWithTitle:@"Queue"
                        action:@selector(openQueue:)
                 keyEquivalent:@"u"] setTarget:self];
    [ctlMenu addItem:[NSMenuItem separatorItem]];
    [[ctlMenu addItemWithTitle:@"Wake Device"
                        action:@selector(wakeDevice:)
                 keyEquivalent:@""] setTarget:self];

    // Window menu.
    NSMenuItem *winItem = [[[NSMenuItem alloc] initWithTitle:@"Window"
                                                      action:NULL
                                               keyEquivalent:@""] autorelease];
    [mainMenu addItem:winItem];
    NSMenu *winMenu = [[[NSMenu alloc] initWithTitle:@"Window"] autorelease];
    [winItem setSubmenu:winMenu];
    [winMenu addItemWithTitle:@"Minimize"
                       action:@selector(performMiniaturize:)
                keyEquivalent:@"m"];
    [winMenu addItemWithTitle:@"Close"
                       action:@selector(performClose:)
                keyEquivalent:@"w"];
    [NSApp setWindowsMenu:winMenu];

    [NSApp setMainMenu:mainMenu];
}

@end
