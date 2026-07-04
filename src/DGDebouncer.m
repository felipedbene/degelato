//
//  DGDebouncer.m
//  DeGelato — fio 10
//

#import "DGDebouncer.h"

@implementation DGDebouncer

- (void)setPending:(id)value
{
    [value retain];
    [_pending release];
    _pending = value;
}

- (BOOL)hasPending
{
    return _pending != nil;
}

- (id)takePending
{
    id v = [[_pending retain] autorelease];
    [_pending release];
    _pending = nil;
    return v;
}

- (void)dealloc
{
    [_pending release];
    [super dealloc];
}

@end
