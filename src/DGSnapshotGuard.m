//
//  DGSnapshotGuard.m
//  DeGelato — fio 9
//

#import "DGSnapshotGuard.h"

@implementation DGSnapshotGuard

- (BOOL)acceptTs:(long long)ts
{
    if (ts <= 0) {
        return YES;             // unknown ts never blocks an update
    }
    if (_lastTs > 0 && ts < _lastTs) {
        return NO;              // regressed — a staler replica answered
    }
    _lastTs = ts;
    return YES;
}

- (void)reset
{
    _lastTs = 0;
}

@end
