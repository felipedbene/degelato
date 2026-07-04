//
//  AppDelegate.m
//  DeGelato — fio 1
//

#import "AppDelegate.h"
#import "DGNowPlayingWindowController.h"
#import "DGLibraryWindowController.h"
#import "DGPreferencesController.h"

@interface AppDelegate ()
- (void)buildMenuBar;
- (DGLibraryWindowController *)library;
- (void)openSearch:(id)sender;
- (void)openQueue:(id)sender;
- (void)openPlaylists:(id)sender;
- (void)showPreferences:(id)sender;
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

    // Global media keys (⏮ ⏯ ⏭). Fails gracefully if assistive access is off.
    _mediaKeyTap = [[DGMediaKeyTap alloc] initWithDelegate:self];
    [_mediaKeyTap start];
}

- (void)mediaKeyTap:(DGMediaKeyTap *)tap
        receivedKey:(DGMediaKeyKind)kind
            pressed:(BOOL)pressed
           isRepeat:(BOOL)isRepeat
{
    switch ([DGMediaKeyRouter actionForKind:kind pressed:pressed isRepeat:isRepeat]) {
        case DGMediaKeyActionTogglePlayPause: [_nowPlaying onPlayPause:nil]; break;
        case DGMediaKeyActionNext:            [_nowPlaying onNext:nil];      break;
        case DGMediaKeyActionPrevious:        [_nowPlaying onPrev:nil];      break;
        default: break;
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (DGLibraryWindowController *)library
{
    if (_library == nil) {
        _library = [[DGLibraryWindowController alloc] init];
    }
    return _library;
}

- (void)openSearch:(id)sender    { [[self library] showInMode:DGLibraryModeBusca]; }
- (void)openQueue:(id)sender     { [[self library] showInMode:DGLibraryModeFila]; }
- (void)openPlaylists:(id)sender { [[self library] showInMode:DGLibraryModePlaylists]; }

- (void)showPreferences:(id)sender
{
    if (_prefs == nil) {
        _prefs = [[DGPreferencesController alloc] init];
    }
    [_prefs showWindow:self];
    [[_prefs window] makeKeyAndOrderFront:self];
}

// Wake without changing play/pause state; forwarded to the now-playing window,
// which owns the gopher command path and adopts the returned /now.
- (void)wakeDevice:(id)sender
{
    [_nowPlaying wakeDevice:sender];
}

- (void)dealloc
{
    [_mediaKeyTap stop];
    [_mediaKeyTap release];
    [_nowPlaying release];
    [_library release];
    [_prefs release];
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
    [[appMenu addItemWithTitle:@"Preferences…"
                        action:@selector(showPreferences:)
                 keyEquivalent:@","] setTarget:self];
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
    [[ctlMenu addItemWithTitle:@"Playlists"
                        action:@selector(openPlaylists:)
                 keyEquivalent:@"y"] setTarget:self];
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
