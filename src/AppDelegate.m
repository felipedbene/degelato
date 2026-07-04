//
//  AppDelegate.m
//  DeGelato — fio 1
//

#import "AppDelegate.h"
#import "DGNowPlayingWindowController.h"
#import "DGLibraryWindowController.h"
#import "DGPreferencesController.h"
#import "DGGopherWindowController.h"
#import "DGGopherResource.h"
#import "DGBookmarkStore.h"

#define DG_GOPHER_HOME @"gopher.debene.dev"

@interface AppDelegate ()
- (void)buildMenuBar;
- (DGLibraryWindowController *)library;
- (void)openSearch:(id)sender;
- (void)openQueue:(id)sender;
- (void)openPlaylists:(id)sender;
- (void)showPreferences:(id)sender;
- (void)openLocation:(id)sender;
- (void)goHome:(id)sender;
- (void)addBookmark:(id)sender;
- (void)showBookmarks:(id)sender;
- (DGGopherWindowController *)makeGopherWindowForResource:(DGGopherResource *)res
                                              fromWindow:(NSWindow *)parent;
- (void)openGopherResource:(DGGopherResource *)res fromWindow:(NSWindow *)parent;
- (void)gopherWindowWillClose:(NSNotification *)note;
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

#pragma mark - Gopher browser

- (DGGopherWindowController *)makeGopherWindowForResource:(DGGopherResource *)res
                                              fromWindow:(NSWindow *)parent
{
    if (res == nil) { return nil; }
    if (_gopherWindows == nil) { _gopherWindows = [[NSMutableArray alloc] init]; }
    DGGopherWindowController *wc =
        [[[DGGopherWindowController alloc] initWithResource:res parentWindow:parent] autorelease];
    [_gopherWindows addObject:wc];   // retained until the window closes
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(gopherWindowWillClose:)
            name:NSWindowWillCloseNotification object:[wc window]];
    [wc showWindow:self];
    [[wc window] makeKeyAndOrderFront:self];
    return wc;
}

- (void)openGopherResource:(DGGopherResource *)res fromWindow:(NSWindow *)parent
{
    [[self makeGopherWindowForResource:res fromWindow:parent] load];
}

- (void)addBookmark:(id)sender
{
    // Bookmark the front gopher window's resource.
    NSWindow *key = [NSApp keyWindow];
    NSUInteger i;
    for (i = 0; i < [_gopherWindows count]; i++) {
        DGGopherWindowController *wc = [_gopherWindows objectAtIndex:i];
        if ([wc window] == key) {
            [DGBookmarkStore addBookmarkForResource:[wc resource]];
            return;
        }
    }
    NSBeep();   // no gopher window is frontmost
}

- (void)showBookmarks:(id)sender
{
    DGGopherResource *res = [DGGopherResource resourceWithHost:@"bookmarks" port:70
                                                         type:'1' selector:@"" display:@"Bookmarks"];
    DGGopherWindowController *wc = [self makeGopherWindowForResource:res fromWindow:nil];
    [wc loadLocalMenuText:[DGBookmarkStore bookmarksText]];
}

- (void)gopherWindowWillClose:(NSNotification *)note
{
    NSWindow *w = [note object];
    NSUInteger i;
    for (i = 0; i < [_gopherWindows count]; i++) {
        DGGopherWindowController *wc = [_gopherWindows objectAtIndex:i];
        if ([wc window] == w) {
            [[NSNotificationCenter defaultCenter] removeObserver:self
                name:NSWindowWillCloseNotification object:w];
            [_gopherWindows removeObjectAtIndex:i];
            break;
        }
    }
}

- (void)goHome:(id)sender
{
    [self openGopherResource:[DGGopherResource resourceFromLocationString:DG_GOPHER_HOME]
                  fromWindow:nil];
}

- (void)openLocation:(id)sender
{
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Open Gopher Location"];
    [alert setInformativeText:@"A host, host:port, or gopher://host/… address."];
    [alert addButtonWithTitle:@"Open"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *input = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)] autorelease];
    [input setStringValue:DG_GOPHER_HOME];
    [alert setAccessoryView:input];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [self openGopherResource:[DGGopherResource resourceFromLocationString:[input stringValue]]
                      fromWindow:nil];
    }
}

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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_mediaKeyTap stop];
    [_mediaKeyTap release];
    [_nowPlaying release];
    [_library release];
    [_prefs release];
    [_gopherWindows release];
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

    // Gopher menu (fio 20): general RFC 1436 browsing.
    NSMenuItem *gphItem = [[[NSMenuItem alloc] initWithTitle:@"Gopher"
                                                      action:NULL
                                               keyEquivalent:@""] autorelease];
    [mainMenu addItem:gphItem];
    NSMenu *gphMenu = [[[NSMenu alloc] initWithTitle:@"Gopher"] autorelease];
    [gphItem setSubmenu:gphMenu];
    [[gphMenu addItemWithTitle:@"Home"
                        action:@selector(goHome:)
                 keyEquivalent:@"H"] setTarget:self];
    [[gphMenu addItemWithTitle:@"Open Location…"
                        action:@selector(openLocation:)
                 keyEquivalent:@"l"] setTarget:self];
    [gphMenu addItem:[NSMenuItem separatorItem]];
    [[gphMenu addItemWithTitle:@"Add Bookmark"
                        action:@selector(addBookmark:)
                 keyEquivalent:@"d"] setTarget:self];
    [[gphMenu addItemWithTitle:@"Show Bookmarks"
                        action:@selector(showBookmarks:)
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
