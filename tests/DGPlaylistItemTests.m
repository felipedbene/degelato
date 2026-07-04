//
//  DGPlaylistItemTests.m
//  DeGelato — fio 17. Playlist list parsing + context uri. Offline.
//

#import <SenTestingKit/SenTestingKit.h>
#import "DGPlaylistItem.h"

@interface DGPlaylistItemTests : SenTestCase
@end

@implementation DGPlaylistItemTests

- (void)testParsesPlaylists
{
    NSString *body =
        @"total\t3\n"
        @"item.0.id\tabc\nitem.0.name\tRock\nitem.0.tracks_len\t42\n"
        @"item.1.id\tdef\nitem.1.name\tJazz\nitem.1.tracks_len\t10\n.\r\n";
    NSArray *items = [DGPlaylistItem itemsFromResponse:body];
    STAssertEquals([items count], (NSUInteger)2, @"two playlists");

    DGPlaylistItem *p0 = [items objectAtIndex:0];
    STAssertEqualObjects(p0.playlistId, @"abc", @"id");
    STAssertEqualObjects(p0.name, @"Rock", @"name");
    STAssertEquals(p0.tracksLen, (NSInteger)42, @"tracks_len");
    STAssertEqualObjects([p0 contextURI], @"spotify:playlist:abc", @"context uri");
}

- (void)testEmpty
{
    STAssertEquals([[DGPlaylistItem itemsFromResponse:@"total\t0\n.\r\n"] count],
                   (NSUInteger)0, @"empty list -> no items, never nil");
}

- (void)testStopsAtGap
{
    NSString *body = @"item.0.id\ta\nitem.0.name\tA\n"
                     @"item.2.id\tc\nitem.2.name\tC\n";   // no item.1.*
    NSArray *items = [DGPlaylistItem itemsFromResponse:body];
    STAssertEquals([items count], (NSUInteger)1, @"stops at the first index gap");
}

- (void)testContextURINilWhenNoId
{
    DGPlaylistItem *p = [[[DGPlaylistItem alloc] init] autorelease];
    STAssertNil([p contextURI], @"no id -> nil context uri");
}

@end
