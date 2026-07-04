//
//  DGCoverCacheTests.m
//  DeGelato — fio 16. Two-level (memory + disk) cover byte cache. Offline.
//

#import <SenTestingKit/SenTestingKit.h>
#import "DGCoverCache.h"

@interface DGCoverCacheTests : SenTestCase {
    NSString *_dir;
}
@end

@implementation DGCoverCacheTests

- (void)setUp
{
    [super setUp];
    _dir = [[NSTemporaryDirectory() stringByAppendingPathComponent:
             [NSString stringWithFormat:@"dgcovertest-%p", self]] retain];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:_dir error:NULL];
    [_dir release];
    _dir = nil;
    [super tearDown];
}

- (NSData *)fakeJPEGWithByte:(uint8_t)b
{
    uint8_t bytes[3] = { 0xFF, 0xD8, b };   // SOI + a filler so it's non-empty
    return [NSData dataWithBytes:bytes length:3];
}

- (void)testFileNameFormat
{
    STAssertEqualObjects([DGCoverCache fileNameForAlbum:@"abc123" size:300],
                         @"abc123-300.jpg", @"<id>-<size>.jpg");
    STAssertEqualObjects([DGCoverCache fileNameForAlbum:@"a/b..c" size:64],
                         @"a_b__c-64.jpg", @"non-alphanumerics sanitized (no path escape)");
}

- (void)testMissReturnsNil
{
    DGCoverCache *c = [[[DGCoverCache alloc] initWithDirectory:_dir] autorelease];
    STAssertNil([c coverDataForAlbum:@"nope" size:300], @"unknown album -> nil");
    STAssertNil([c coverDataForAlbum:@"" size:300], @"empty id -> nil");
}

- (void)testStoreThenMemoryHit
{
    DGCoverCache *c = [[[DGCoverCache alloc] initWithDirectory:_dir] autorelease];
    NSData *jpeg = [self fakeJPEGWithByte:0x11];
    [c storeData:jpeg forAlbum:@"album1" size:300];
    STAssertEqualObjects([c coverDataForAlbum:@"album1" size:300], jpeg, @"memory hit");
}

- (void)testDiskPersistsAcrossInstances
{
    DGCoverCache *c1 = [[[DGCoverCache alloc] initWithDirectory:_dir] autorelease];
    NSData *jpeg = [self fakeJPEGWithByte:0x22];
    [c1 storeData:jpeg forAlbum:@"album2" size:64];
    // A fresh instance has empty memory -> it must read the bytes back from disk.
    DGCoverCache *c2 = [[[DGCoverCache alloc] initWithDirectory:_dir] autorelease];
    STAssertEqualObjects([c2 coverDataForAlbum:@"album2" size:64], jpeg, @"disk hit");
}

- (void)testSizeIsPartOfKey
{
    DGCoverCache *c = [[[DGCoverCache alloc] initWithDirectory:_dir] autorelease];
    [c storeData:[self fakeJPEGWithByte:0x33] forAlbum:@"album3" size:300];
    STAssertNil([c coverDataForAlbum:@"album3" size:64], @"different size -> miss");
}

- (void)testStoreNoOps
{
    DGCoverCache *c = [[[DGCoverCache alloc] initWithDirectory:_dir] autorelease];
    [c storeData:nil forAlbum:@"a" size:64];                          // nil data
    [c storeData:[self fakeJPEGWithByte:1] forAlbum:@"" size:64];     // empty id
    STAssertNil([c coverDataForAlbum:@"a" size:64], @"nil data not stored");
}

@end
