//
//  DGTimelineTests.m
//  DeGelato — fio 13. Regression coverage for the "scrub 3 s → tap Next twice
//  within 1 s" timeline from design/INVESTIGATION-command-spam.md. Asserts the
//  two invariants this fix campaign guarantees, at the level of the two
//  components that enforce them:
//    (1) the UI never adopts a stale /now snapshot — the ts-guard drops
//        out-of-order replicas (R3);
//    (2) a burst of taps emits no more than the intended commands — the
//        transport debouncer coalesces to the last tap (R1 / decision #1).
//

#import <SenTestingKit/SenTestingKit.h>
#import "DGSnapshotGuard.h"
#import "DGDebouncer.h"

@interface DGTimelineTests : SenTestCase
@end

@implementation DGTimelineTests

// (2) Never emits more than the intended commands. The scenario's two fast Next
// taps (within the ~300 ms window) coalesce to exactly one /next — three taps
// would still be one. A command cannot be un-sent (R1), so the intermediate taps
// must never reach the wire; the debounce holds them back and only the last
// survives.
- (void)testNextBurstEmitsExactlyOneCommand
{
    DGDebouncer *tx = [[[DGDebouncer alloc] init] autorelease];
    [tx setPending:@"/spot/api/1/next"];   // tap 1
    [tx setPending:@"/spot/api/1/next"];   // tap 2, still inside the window
    STAssertEqualObjects([tx takePending], @"/spot/api/1/next",
                         @"two Next taps in the window -> one /next");
    STAssertNil([tx takePending], @"no second command escapes the window");
}

// A tap that changes direction mid-burst still yields a single command — the
// last one (Prev), never both.
- (void)testDirectionChangeInBurstYieldsLastOnly
{
    DGDebouncer *tx = [[[DGDebouncer alloc] init] autorelease];
    [tx setPending:@"/spot/api/1/next"];
    [tx setPending:@"/spot/api/1/prev"];
    STAssertEqualObjects([tx takePending], @"/spot/api/1/prev", @"last tap wins");
    STAssertNil([tx takePending], @"exactly one command");
}

// (1) Never adopts a stale snapshot. Walking the scenario's timeline of /now
// timestamps: the scrub-era snapshot, then the settled post-Next snapshot from
// a fresh replica, then a STALER replica answering a catch-up poll (the two
// pods each micro-cache /now ~1 s, so out-of-order is expected infra behavior),
// then the regular poll catching up. The guard adopts the forward ones and
// drops the regression, so the track/seek bar never rewinds at the user.
- (void)testCatchUpNeverAdoptsStaleReplica
{
    DGSnapshotGuard *g = [[[DGSnapshotGuard alloc] init] autorelease];
    STAssertTrue([g acceptTs:1000],  @"scrub-era snapshot adopted");
    STAssertTrue([g acceptTs:2000],  @"settled post-Next snapshot adopted");
    STAssertFalse([g acceptTs:1600], @"staler replica on a catch-up poll -> DROPPED (no rewind)");
    STAssertTrue([g acceptTs:2100],  @"regular poll, caught up, adopted");
}

// After an outage the guard resets, so a backend that came back with a lower
// clock is not locked out forever (the scenario's reconnect path).
- (void)testReconnectAcceptsLowerClockAfterReset
{
    DGSnapshotGuard *g = [[[DGSnapshotGuard alloc] init] autorelease];
    STAssertTrue([g acceptTs:5000], @"pre-outage high-water mark");
    [g reset];                       // controller resets on reconnect after offline
    STAssertTrue([g acceptTs:1200], @"post-restart lower clock adopted after reset");
}

@end
