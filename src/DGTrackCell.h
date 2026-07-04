//
//  DGTrackCell.h
//  DeGelato — fio 17
//
//  A one-column NSCell that draws a 64px thumbnail on the left and two lines of
//  text (title / subtitle) on the right. The cell's objectValue is a dictionary
//  { "image": NSImage|nil, "title": NSString, "subtitle": NSString }. 10.5 has no
//  view-based table cells (10.7+), so this is a classic cell-based row.
//  Ported from DeToca's DTTrackCell (plain AppKit colors; theming is fio 24).
//

#import <Cocoa/Cocoa.h>

#define DG_TRACK_ROW_HEIGHT 72.0   // 64px thumb + 4px top/bottom padding

@interface DGTrackCell : NSCell
@end
