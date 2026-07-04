//
//  AppDelegate.m
//  DeGelato — fio 1
//

#import "AppDelegate.h"
#import "DGNowPlayingWindowController.h"

@interface AppDelegate ()
- (void)buildMenuBar;
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

- (void)dealloc
{
    [_nowPlaying release];
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
