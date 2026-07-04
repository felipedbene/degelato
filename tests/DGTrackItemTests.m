//
//  DGTrackItemTests.m
//  DeGelato — fio 5. Pure tests for the v1 list-item parser (queue/search).
//

#import <SenTestingKit/SenTestingKit.h>
#import "DGTrackItem.h"

@interface DGTrackItemTests : SenTestCase
@end

@implementation DGTrackItemTests

- (void)testBasicList
{
    NSString *body =
        @"api\t1\r\nresult_len\t2\r\n"
        @"item.0.uri\tspotify:track:AAA\r\nitem.0.track\tConstrução\r\n"
        @"item.0.artist\tChico Buarque\r\nitem.0.album_id\tALB0\r\nitem.0.duration_ms\t383626\r\n"
        @"item.1.uri\tspotify:track:BBB\r\nitem.1.track\tA Banda\r\n"
        @"item.1.artist\tChico Buarque\r\nitem.1.duration_ms\t150000\r\n";
    NSArray *items = [DGTrackItem itemsFromResponse:body];
    STAssertEquals([items count], (NSUInteger)2, @"two items parsed");

    DGTrackItem *a = [items objectAtIndex:0];
    STAssertEqualObjects(a.uri, @"spotify:track:AAA", @"uri");
    STAssertEqualObjects(a.track, @"Construção", @"UTF-8 track");
    STAssertEqualObjects(a.artist, @"Chico Buarque", @"artist");
    STAssertEqualObjects(a.albumId, @"ALB0", @"album id");
    STAssertEquals(a.durationMs, (long long)383626, @"duration");

    DGTrackItem *b = [items objectAtIndex:1];
    STAssertEqualObjects(b.track, @"A Banda", @"second item track");
    STAssertNil(b.albumId, @"absent album_id -> nil");
}

- (void)testEmptyList
{
    NSArray *items = [DGTrackItem itemsFromResponse:@"api\t1\r\nresult_len\t0\r\n"];
    STAssertEquals([items count], (NSUInteger)0, @"no item.* -> empty array (never nil)");
    STAssertNotNil(items, @"never nil");
}

- (void)testStopsAtFirstGap
{
    // item.2 present but item.1 missing: the contiguous scan stops after item.0.
    NSString *body = @"item.0.uri\tU0\r\nitem.2.uri\tU2\r\nitem.2.track\tOrphan\r\n";
    NSArray *items = [DGTrackItem itemsFromResponse:body];
    STAssertEquals([items count], (NSUInteger)1, @"scan stops at the first index gap");
    STAssertEqualObjects([[items objectAtIndex:0] uri], @"U0", @"only item.0 kept");
}

- (void)testFixtureSearchParses
{
    const char *dir = getenv("DG_FIXTURES");
    if (dir == NULL) { return; }
    NSString *path = [[NSString stringWithUTF8String:dir]
                      stringByAppendingPathComponent:@"search_sample.txt"];
    NSString *body = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding error:NULL];
    if (body == nil) { return; }
    NSArray *items = [DGTrackItem itemsFromResponse:body];
    STAssertTrue([items count] > 0, @"real search fixture yields tracks");
    STAssertTrue([items count] <= 10, @"Spotify caps search at 10");
    DGTrackItem *first = [items objectAtIndex:0];
    STAssertTrue([first.uri hasPrefix:@"spotify:track:"], @"first result has a track uri");
    STAssertTrue([first.track length] > 0, @"first result has a name");
}

@end
