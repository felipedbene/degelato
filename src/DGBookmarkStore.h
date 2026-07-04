//
//  DGBookmarkStore.h
//  DeGelato — fio 22
//
//  Gopher bookmarks as a hand-editable gophermap at
//  ~/Library/Application Support/DeGelato/bookmarks.gophermap. Seeded on first
//  use; "Add Bookmark" appends a line; "Show Bookmarks" renders the file as a
//  local menu. Ported from DeToca's BookmarkStore.
//

#import <Foundation/Foundation.h>

@class DGGopherResource;

@interface DGBookmarkStore : NSObject

+ (NSString *)bookmarksPath;
+ (void)ensureExists;
+ (NSString *)bookmarksText;                                 // the gophermap text
+ (BOOL)addBookmarkForResource:(DGGopherResource *)resource; // append one line

@end
