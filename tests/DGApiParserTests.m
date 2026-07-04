//
//  DGApiParserTests.m
//  DeGelato — fio 1. OCUnit tests for the pure model+parser layer.
//  Fully offline: no gopher, no AppKit, no network. Logic cases are inline and
//  deterministic; the on-disk fixtures captured under Tests/Fixtures are also
//  round-tripped (path via the DG_FIXTURES env set by `make test`).
//

#import <SenTestingKit/SenTestingKit.h>

#import "DGApiParser.h"
#import "DGNowSnapshot.h"

// Absolute path to a fixture under DG_FIXTURES (set by `make test`), or nil.
static NSString *DGFixture(NSString *name);

@interface DGApiParserTests : SenTestCase
@end

@implementation DGApiParserTests

#pragma mark - fieldsFromResponse

- (void)testFieldsBasic
{
    NSDictionary *f = [DGApiParser fieldsFromResponse:@"api\t1\r\nstate\tplaying\r\n"];
    STAssertEqualObjects([f objectForKey:@"api"], @"1", @"api parsed");
    STAssertEqualObjects([f objectForKey:@"state"], @"playing", @"state parsed");
}

- (void)testFieldsBareLF
{
    // Tolerate bare LF (no CR) as well as CRLF.
    NSDictionary *f = [DGApiParser fieldsFromResponse:@"api\t1\nstate\tpaused\n"];
    STAssertEqualObjects([f objectForKey:@"state"], @"paused", @"bare-LF line parsed");
}

- (void)testFieldsStripTrailingCROnly
{
    NSDictionary *f = [DGApiParser fieldsFromResponse:@"track\tName With Spaces\r\n"];
    STAssertEqualObjects([f objectForKey:@"track"], @"Name With Spaces", @"inner chars intact");
}

- (void)testFieldsSkipNoTabLines
{
    NSDictionary *f = [DGApiParser fieldsFromResponse:@"garbage line\r\n.\r\nkey\tval\r\n"];
    STAssertNil([f objectForKey:@"garbage line"], @"non key<TAB>value line skipped");
    STAssertNil([f objectForKey:@"."], @"lone gopher terminator skipped");
    STAssertEqualObjects([f objectForKey:@"key"], @"val", @"real line kept");
}

- (void)testFieldsLastWins
{
    NSDictionary *f = [DGApiParser fieldsFromResponse:@"k\ta\r\nk\tb\r\n"];
    STAssertEqualObjects([f objectForKey:@"k"], @"b", @"repeated key keeps last");
}

- (void)testFieldsValueMayContainTab
{
    // Only the first TAB splits key/value; later tabs stay in the value.
    NSDictionary *f = [DGApiParser fieldsFromResponse:@"k\ta\tb\r\n"];
    STAssertEqualObjects([f objectForKey:@"k"], @"a\tb", @"split on first TAB only");
}

- (void)testFieldsEmptyAndNil
{
    STAssertEquals([[DGApiParser fieldsFromResponse:@""] count], (NSUInteger)0, @"empty -> empty");
    STAssertEquals([[DGApiParser fieldsFromResponse:nil] count], (NSUInteger)0, @"nil -> empty");
}

#pragma mark - snapshotFromResponse

- (void)testSnapshotPlaying
{
    NSString *body =
        @"api\t1\r\nstate\tplaying\r\ntrack\tConstrução\r\n"
        @"artist\tChico Buarque\r\nalbum\tConstrução\r\n"
        @"album_id\tAID\r\ntrack_id\t3FIuBxOxuQ6kYy8JO0gq2a\r\nposition_ms\t26221\r\n"
        @"duration_ms\t383626\r\ndevice\tactive\r\nvolume\t100\r\nqueue_len\t7\r\nts\t1783105644431\r\n";
    DGNowSnapshot *s = [DGApiParser snapshotFromResponse:body];

    STAssertEquals(s.apiVersion, (NSInteger)1, @"api");
    STAssertEquals(s.state, DGPlaybackPlaying, @"state playing");
    STAssertEqualObjects(s.track, @"Construção", @"UTF-8 track name intact");
    STAssertEqualObjects(s.artist, @"Chico Buarque", @"artist");
    STAssertEqualObjects(s.album, @"Construção", @"album");
    STAssertEqualObjects(s.albumId, @"AID", @"album id");
    STAssertEqualObjects(s.trackId, @"3FIuBxOxuQ6kYy8JO0gq2a", @"track id");
    STAssertEquals(s.positionMs, (long long)26221, @"position");
    STAssertEquals(s.durationMs, (long long)383626, @"duration");
    STAssertEquals(s.volume, (NSInteger)100, @"volume");
    STAssertEquals(s.queueLen, (NSInteger)7, @"queue len");
    STAssertEquals(s.ts, (long long)1783105644431LL, @"ts (64-bit epoch ms)");
    STAssertEquals(s.device, DGDeviceActive, @"device active");
    STAssertTrue([s hasTrack], @"has track");
    STAssertTrue([s hasVolume], @"has volume");
    STAssertFalse([s deviceIsIdle], @"active is not idle");
}

- (void)testSnapshotStopped
{
    DGNowSnapshot *s = [DGApiParser snapshotFromResponse:
                        @"api\t1\r\nstate\tstopped\r\nqueue_len\t0\r\nts\t123\r\n"];
    STAssertEquals(s.state, DGPlaybackStopped, @"stopped");
    STAssertFalse([s hasTrack], @"no track when stopped");
    STAssertFalse([s hasVolume], @"no volume reported -> hasVolume NO");
    STAssertEquals(s.volume, (NSInteger)-1, @"absent volume is -1");
}

- (void)testSnapshotPaused
{
    DGNowSnapshot *s = [DGApiParser snapshotFromResponse:@"state\tpaused\r\n"];
    STAssertEquals(s.state, DGPlaybackPaused, @"paused");
}

- (void)testSnapshotDeviceIdle
{
    DGNowSnapshot *s = [DGApiParser snapshotFromResponse:@"state\tplaying\r\ndevice\tidle\r\n"];
    STAssertEquals(s.device, DGDeviceIdle, @"device idle");
    STAssertTrue([s deviceIsIdle], @"deviceIsIdle YES");
}

- (void)testSnapshotDeviceUnknownWhenAbsent
{
    DGNowSnapshot *s = [DGApiParser snapshotFromResponse:@"state\tplaying\r\n"];
    STAssertEquals(s.device, DGDeviceUnknown, @"absent device -> unknown");
    STAssertFalse([s deviceIsIdle], @"unknown is not idle");
}

- (void)testSnapshotIgnoresUnknownKeys
{
    DGNowSnapshot *s = [DGApiParser snapshotFromResponse:
        @"api\t1\r\nstate\tplaying\r\ntrack\tX\r\ncover_url\thttp://x/y.png\r\nfuture\t42\r\n"];
    STAssertEquals(s.state, DGPlaybackPlaying, @"still parses known keys");
    STAssertEqualObjects(s.track, @"X", @"track parsed despite unknown keys");
}

- (void)testSnapshotTruncatedBeforeTabDropsFragment
{
    // A response cut before the key's TAB: the trailing tab-less fragment must
    // be dropped, never mistaken for a bare key. Earlier fields survive.
    DGNowSnapshot *s = [DGApiParser snapshotFromResponse:
                        @"api\t1\r\nstate\tplaying\r\ntrack"];
    STAssertEquals(s.state, DGPlaybackPlaying, @"prefix parsed");
    STAssertNil(s.track, @"tab-less trailing fragment dropped");
}

- (void)testSnapshotTruncatedInValueKeepsPartial
{
    // A response cut inside a value (key + TAB present): the partial value is
    // whatever arrived — reasonable, and it must not crash.
    DGNowSnapshot *s = [DGApiParser snapshotFromResponse:
                        @"api\t1\r\nstate\tplaying\r\ntrack\tHalf A Titl"];
    STAssertEquals(s.state, DGPlaybackPlaying, @"prefix parsed");
    STAssertEqualObjects(s.track, @"Half A Titl", @"partial value preserved");
}

#pragma mark - interpolation

- (void)testInterpolationWhilePlaying
{
    DGNowSnapshot *s = [DGApiParser snapshotFromResponse:
        @"state\tplaying\r\nposition_ms\t1000\r\nduration_ms\t200000\r\nts\t5000\r\n"];
    STAssertEquals([s interpolatedPositionMsAtEpochMs:6500], (long long)2500,
                   @"advances by elapsed while playing");
}

- (void)testInterpolationClampedToDuration
{
    DGNowSnapshot *s = [DGApiParser snapshotFromResponse:
        @"state\tplaying\r\nposition_ms\t1000\r\nduration_ms\t1200\r\nts\t5000\r\n"];
    STAssertEquals([s interpolatedPositionMsAtEpochMs:99999], (long long)1200,
                   @"clamped to duration");
}

- (void)testInterpolationFrozenWhenPaused
{
    DGNowSnapshot *s = [DGApiParser snapshotFromResponse:
        @"state\tpaused\r\nposition_ms\t1000\r\nduration_ms\t200000\r\nts\t5000\r\n"];
    STAssertEquals([s interpolatedPositionMsAtEpochMs:99999], (long long)1000,
                   @"paused -> position does not advance");
}

#pragma mark - textFromData

- (void)testTextFromDataUTF8
{
    NSData *d = [@"track\tConstrução\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    STAssertEqualObjects([DGApiParser textFromData:d], @"track\tConstrução\r\n", @"UTF-8 decoded");
}

- (void)testTextFromDataEmpty
{
    STAssertEqualObjects([DGApiParser textFromData:[NSData data]], @"", @"empty data -> empty string");
    STAssertEqualObjects([DGApiParser textFromData:nil], @"", @"nil data -> empty string");
}

#pragma mark - dataIsJPEG

- (void)testDataIsJPEG
{
    unsigned char jpeg[] = { 0xFF, 0xD8, 0xFF, 0xE0, 0x00 };
    STAssertTrue([DGApiParser dataIsJPEG:[NSData dataWithBytes:jpeg length:sizeof(jpeg)]],
                 @"FF D8 recognised as JPEG");
    STAssertFalse([DGApiParser dataIsJPEG:[@"api\t1\r\nerror\tbad_range\r\n"
                                           dataUsingEncoding:NSUTF8StringEncoding]],
                  @"an error text document is not a JPEG");
    STAssertFalse([DGApiParser dataIsJPEG:[NSData data]], @"empty is not a JPEG");
    STAssertFalse([DGApiParser dataIsJPEG:nil], @"nil is not a JPEG");
}

- (void)testFixtureCoverIsJPEGErrorIsNot
{
    NSString *jpath = DGFixture(@"cover_sample.jpg");
    NSString *epath = DGFixture(@"cover_error.txt");
    if (jpath == nil) { return; }
    STAssertTrue([DGApiParser dataIsJPEG:[NSData dataWithContentsOfFile:jpath]],
                 @"real captured cover is a JPEG");
    STAssertFalse([DGApiParser dataIsJPEG:[NSData dataWithContentsOfFile:epath]],
                  @"real cover error body is text, not a JPEG");
    // The error body parses as fields with an error key.
    NSString *etext = [DGApiParser textFromData:[NSData dataWithContentsOfFile:epath]];
    STAssertEqualObjects([[DGApiParser fieldsFromResponse:etext] objectForKey:@"error"],
                         @"bad_range", @"cover error surfaces as error=bad_range");
}

- (void)testTextFromGarbageDoesNotCrash
{
    // Invalid UTF-8 must degrade, not return nil / throw.
    unsigned char bytes[] = { 0xff, 0xfe, 0x00, 0x82, 'x', '\n' };
    NSData *d = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    NSString *text = [DGApiParser textFromData:d];
    STAssertNotNil(text, @"garbage decodes to some (non-nil) string");
    DGNowSnapshot *s = [DGApiParser snapshotFromResponse:text];
    STAssertFalse([s hasTrack], @"garbage yields no usable fields");
}

#pragma mark - on-disk fixtures

static NSString *DGFixture(NSString *name)
{
    const char *dir = getenv("DG_FIXTURES");
    if (dir == NULL) {
        return nil;   // not run via `make test`; skip fixture-backed assertions
    }
    NSString *base = [NSString stringWithUTF8String:dir];
    return [base stringByAppendingPathComponent:name];
}

- (void)testFixtureLiveParses
{
    NSString *path = DGFixture(@"now_live.txt");
    if (path == nil) { return; }
    NSData *d = [NSData dataWithContentsOfFile:path];
    STAssertNotNil(d, @"now_live.txt present");
    DGNowSnapshot *s = [DGApiParser snapshotFromResponse:[DGApiParser textFromData:d]];
    STAssertEquals(s.apiVersion, (NSInteger)1, @"live api == 1");
    STAssertTrue(s.state == DGPlaybackPlaying || s.state == DGPlaybackPaused
                 || s.state == DGPlaybackStopped, @"live state is a known value");
}

- (void)testFixtureAccents
{
    NSString *path = DGFixture(@"now_accents.txt");
    if (path == nil) { return; }
    NSData *d = [NSData dataWithContentsOfFile:path];
    DGNowSnapshot *s = [DGApiParser snapshotFromResponse:[DGApiParser textFromData:d]];
    STAssertEqualObjects(s.track, @"Construção", @"UTF-8 accents survive a real file round-trip");
    STAssertEqualObjects(s.artist, @"Chico Buarque", @"artist");
}

- (void)testFixtureEmptyGarbageTruncatedUnknown
{
    NSString *names[] = { @"now_empty.txt", @"now_garbage.txt",
                          @"now_truncated.txt", @"now_unknown_keys.txt" };
    NSUInteger i;
    for (i = 0; i < 4; i++) {
        NSString *path = DGFixture(names[i]);
        if (path == nil) { return; }
        NSData *d = [NSData dataWithContentsOfFile:path];
        // The point is that none of these throw or return nil.
        DGNowSnapshot *s = [DGApiParser snapshotFromResponse:[DGApiParser textFromData:d]];
        STAssertNotNil(s, @"%@ parsed to a snapshot without crashing", names[i]);
    }
    // The unknown-keys fixture still recovers the known fields.
    NSString *uk = DGFixture(@"now_unknown_keys.txt");
    if (uk != nil) {
        DGNowSnapshot *s = [DGApiParser snapshotFromResponse:
            [DGApiParser textFromData:[NSData dataWithContentsOfFile:uk]]];
        STAssertEqualObjects(s.track, @"X", @"known key parsed past unknown ones");
        STAssertEquals(s.volume, (NSInteger)80, @"volume parsed past unknown ones");
    }
}

@end
