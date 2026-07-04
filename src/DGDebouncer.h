//
//  DGDebouncer.h
//  DeGelato — fio 10
//
//  A one-slot "last value wins" coalescer. The timer that decides *when* to
//  flush is UI glue and lives in the controller; this object holds the coalesced
//  value so the last-wins logic is testable in isolation. Used for the
//  Prev/Next transport debounce: within the settle window only the final tap is
//  kept, so exactly one command reaches the wire (decision #1 / R1 — a sent
//  command cannot be un-sent, so intermediate taps must never be sent at all).
//

#import <Foundation/Foundation.h>

@interface DGDebouncer : NSObject {
    id _pending;
}

// Replace any currently-pending value with this one (last wins).
- (void)setPending:(id)value;

// YES while a value is waiting to be flushed.
- (BOOL)hasPending;

// Return the pending value and clear it (nil if nothing is pending). Calling
// twice without an intervening -setPending: returns nil the second time.
- (id)takePending;

@end
