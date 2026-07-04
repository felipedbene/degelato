//
//  DGLibraryWindowController.h
//  DeGelato — fio 17
//
//  One window, three modes via a segmented control (DeToca's DTPlaylistWindow
//  model), replacing the separate Search and Queue windows:
//    • Busca     — search tracks; double-click plays, "Add to Queue" enqueues.
//    • Fila      — the up-next queue (read-only; Refresh).
//    • Playlists — all playlists; double-click plays the playlist by CONTEXT.
//  Rows are 64px-thumbnail cells (DGTrackCell) served from DGCoverCache; a miss
//  kicks off a per-album cover fetch and reloads when it lands.
//

#import <Cocoa/Cocoa.h>
#import "DGGopherClient.h"

enum {
    DGLibraryModeBusca     = 0,
    DGLibraryModeFila      = 1,
    DGLibraryModePlaylists = 2
};

@interface DGLibraryWindowController : NSWindowController <DGGopherClientDelegate> {
    NSSegmentedControl  *_modeControl;
    NSSearchField       *_queryField;
    NSButton            *_searchButton;
    NSButton            *_addButton;
    NSButton            *_refreshButton;
    NSTableView         *_table;
    NSTextField         *_statusLabel;

    NSInteger            _mode;
    NSArray             *_results;      // DGTrackItem[]     (Busca)
    NSArray             *_queue;        // DGTrackItem[]     (Fila)
    NSArray             *_playlists;    // DGPlaylistItem[]  (Playlists)

    DGGopherClient      *_searchClient;
    DGGopherClient      *_queueClient;
    DGGopherClient      *_playlistsClient;
    DGGopherClient      *_playClient;
    DGGopherClient      *_addClient;
    NSMutableDictionary *_coverClients; // albumId -> in-flight cover DGGopherClient
}

// Open the window already switched to a given mode (⌘F → Busca, ⌘U → Fila).
- (void)showInMode:(NSInteger)mode;

@end
