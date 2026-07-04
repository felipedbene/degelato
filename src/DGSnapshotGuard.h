//
//  DGSnapshotGuard.h
//  DeGelato — fio 9
//
//  Monotonic-ts guard for /now snapshots. gopher-spot runs two replicas, each
//  with a ~1 s micro-cache of /now, behind a load balancer: consecutive polls
//  can land on different pods and return a `ts` slightly out of order. Adopting
//  a staler one rewinds the UI (track flip-flops, seek knob jumps). This guard
//  drops any snapshot whose `ts` regressed relative to one already applied.
//
//  Ported from DeToca's DTSnapshotGuard — the port had dropped it (see
//  design/INVESTIGATION-command-spam.md, R3). Pure Foundation — unit-testable.
//

#import <Foundation/Foundation.h>

@interface DGSnapshotGuard : NSObject {
    long long _lastTs;   // highest ts accepted so far (high-water mark)
}

// YES if `ts` may be applied (>= the highest ts seen), advancing the high-water
// mark; NO if it regressed (older than one already shown). A non-positive ts
// (unknown / absent) is always accepted and never moves the mark. An equal ts
// (the micro-cache returning the same document) is accepted — it is idempotent.
- (BOOL)acceptTs:(long long)ts;

// Forget the high-water mark. Called on reconnect after an outage: the backend
// may have restarted with a reset clock, and a stale mark would otherwise reject
// every fresh snapshot forever.
- (void)reset;

@end
