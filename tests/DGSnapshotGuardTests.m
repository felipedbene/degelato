//
//  DGSnapshotGuardTests.m
//  DeGelato — fio 9. Monotonic-ts guard for /now snapshots. Offline.
//

#import <SenTestingKit/SenTestingKit.h>
#import "DGSnapshotGuard.h"

@interface DGSnapshotGuardTests : SenTestCase
@end

@implementation DGSnapshotGuardTests

- (void)testInOrderAdoption
{
    DGSnapshotGuard *g = [[[DGSnapshotGuard alloc] init] autorelease];
    STAssertTrue([g acceptTs:100], @"first ts always accepted");
    STAssertTrue([g acceptTs:200], @"advancing ts accepted");
    STAssertTrue([g acceptTs:201], @"one ms later accepted");
}

- (void)testOutOfOrderRejection
{
    DGSnapshotGuard *g = [[[DGSnapshotGuard alloc] init] autorelease];
    STAssertTrue([g acceptTs:200], @"establish high-water mark");
    STAssertFalse([g acceptTs:150], @"staler replica rejected");
    STAssertFalse([g acceptTs:199], @"just-behind rejected");
    STAssertTrue([g acceptTs:200], @"equal ts accepted (idempotent micro-cache)");
    STAssertTrue([g acceptTs:201], @"forward again accepted");
}

- (void)testEqualTsDoesNotAdvancePastItself
{
    DGSnapshotGuard *g = [[[DGSnapshotGuard alloc] init] autorelease];
    STAssertTrue([g acceptTs:500], @"establish mark");
    STAssertTrue([g acceptTs:500], @"equal accepted");
    STAssertFalse([g acceptTs:499], @"still rejects below the mark after equal");
}

- (void)testUnknownTsNeverBlocksAndNeverMovesMark
{
    DGSnapshotGuard *g = [[[DGSnapshotGuard alloc] init] autorelease];
    STAssertTrue([g acceptTs:0], @"absent ts accepted");
    STAssertTrue([g acceptTs:100], @"real ts accepted, sets mark");
    STAssertTrue([g acceptTs:0], @"absent ts still accepted");
    STAssertTrue([g acceptTs:-5], @"negative ts accepted");
    STAssertFalse([g acceptTs:50], @"mark unchanged by the ts<=0 calls: 50 < 100 rejected");
}

- (void)testResetPath
{
    DGSnapshotGuard *g = [[[DGSnapshotGuard alloc] init] autorelease];
    STAssertTrue([g acceptTs:500], @"establish high-water mark");
    STAssertFalse([g acceptTs:400], @"400 rejected before reset");
    [g reset];
    STAssertTrue([g acceptTs:400], @"after reset, a lower ts is accepted (backend clock reset)");
    STAssertFalse([g acceptTs:399], @"new mark is 400");
}

@end
