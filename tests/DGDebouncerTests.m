//
//  DGDebouncerTests.m
//  DeGelato — fio 10. Last-value-wins coalescing for the transport debounce.
//

#import <SenTestingKit/SenTestingKit.h>
#import "DGDebouncer.h"

@interface DGDebouncerTests : SenTestCase
@end

@implementation DGDebouncerTests

- (void)testEmptyHasNothing
{
    DGDebouncer *d = [[[DGDebouncer alloc] init] autorelease];
    STAssertFalse([d hasPending], @"nothing pending initially");
    STAssertNil([d takePending], @"take on empty is nil");
}

- (void)testLastTapWins
{
    // Prev then Next then Prev within the window: only the last (Prev) survives.
    DGDebouncer *d = [[[DGDebouncer alloc] init] autorelease];
    [d setPending:@"/spot/api/1/prev"];
    [d setPending:@"/spot/api/1/next"];
    [d setPending:@"/spot/api/1/prev"];
    STAssertTrue([d hasPending], @"a value is pending");
    STAssertEqualObjects([d takePending], @"/spot/api/1/prev", @"last tap wins");
}

- (void)testTakeClears
{
    DGDebouncer *d = [[[DGDebouncer alloc] init] autorelease];
    [d setPending:@"/spot/api/1/next"];
    STAssertEqualObjects([d takePending], @"/spot/api/1/next", @"first take returns it");
    STAssertFalse([d hasPending], @"cleared after take");
    STAssertNil([d takePending], @"second take is nil (no double-send)");
}

- (void)testReArmAfterTake
{
    // A second burst after the first has fired behaves independently.
    DGDebouncer *d = [[[DGDebouncer alloc] init] autorelease];
    [d setPending:@"/spot/api/1/next"];
    STAssertEqualObjects([d takePending], @"/spot/api/1/next", @"first burst");
    [d setPending:@"/spot/api/1/prev"];
    STAssertEqualObjects([d takePending], @"/spot/api/1/prev", @"second burst independent");
}

@end
