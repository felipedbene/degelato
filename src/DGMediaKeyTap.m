//
//  DGMediaKeyTap.m
//  DeGelato — fio 19
//

#import "DGMediaKeyTap.h"
#import <ApplicationServices/ApplicationServices.h>

// NX_SYSDEFINED (IOKit/hidsystem/IOLLEvent.h) — the CGEventType for
// system-defined events. Redeclared to keep imports light.
#ifndef NX_SYSDEFINED
#define NX_SYSDEFINED 14
#endif

// NSEvent subtype for the aux media buttons, and the key-down state nibble.
#define DG_SUBTYPE_AUX_BUTTONS 8
#define DG_KEYSTATE_DOWN       0x0A

static CGEventRef DGMediaKeyTapCallback(CGEventTapProxy proxy,
                                        CGEventType type,
                                        CGEventRef event,
                                        void *refcon);

@interface DGMediaKeyTap ()
- (void)tapThreadMain;
- (CGEventRef)handleCGEvent:(CGEventRef)event ofType:(CGEventType)type;
- (void)deliverKeyInfo:(NSDictionary *)info;   // main thread
@end

@implementation DGMediaKeyTap

- (id)initWithDelegate:(id <DGMediaKeyTapDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;   // not retained (the AppDelegate owns us)
    }
    return self;
}

- (void)dealloc
{
    [self stop];
    [super dealloc];
}

- (BOOL)start
{
    if (_tapPort != NULL) {
        return YES;   // already running
    }

    CGEventMask mask = CGEventMaskBit(NX_SYSDEFINED);
    _tapPort = CGEventTapCreate(kCGSessionEventTap,
                                kCGHeadInsertEventTap,
                                kCGEventTapOptionDefault,
                                mask,
                                DGMediaKeyTapCallback,
                                self);
    if (_tapPort == NULL) {
        NSLog(@"[mediakeys] event tap denied — media keys disabled "
              @"(enable Universal Access ▸ assistive devices)");
        return NO;
    }

    _thread = [[NSThread alloc] initWithTarget:self
                                      selector:@selector(tapThreadMain)
                                        object:nil];
    [_thread setName:@"dev.debene.degelato.mediakeytap"];
    [_thread start];
    return YES;
}

// Runs on the dedicated thread: pump a run loop that services the tap. Off the
// main run loop, so a modal sheet/panel never stalls media keys.
- (void)tapThreadMain
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    _tapRunLoop = (CFRunLoopRef)CFRetain(CFRunLoopGetCurrent());
    _runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _tapPort, 0);
    CFRunLoopAddSource(_tapRunLoop, _runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(_tapPort, true);

    [pool drain];
    CFRunLoopRun();   // blocks until -stop calls CFRunLoopStop

    pool = [[NSAutoreleasePool alloc] init];
    if (_runLoopSource != NULL) {
        CFRunLoopRemoveSource(_tapRunLoop, _runLoopSource, kCFRunLoopCommonModes);
        CFRelease(_runLoopSource);
        _runLoopSource = NULL;
    }
    if (_tapPort != NULL) {
        CFMachPortInvalidate(_tapPort);
        CFRelease(_tapPort);
        _tapPort = NULL;
    }
    if (_tapRunLoop != NULL) {
        CFRelease(_tapRunLoop);
        _tapRunLoop = NULL;
    }
    [pool drain];
}

- (void)stop
{
    if (_tapPort != NULL) {
        CGEventTapEnable(_tapPort, false);
    }
    if (_tapRunLoop != NULL) {
        CFRunLoopStop(_tapRunLoop);
    }
    [_thread release];
    _thread = nil;
}

// Called from the C callback (on the tap thread). Return the event to pass it
// through, or NULL to consume it.
- (CGEventRef)handleCGEvent:(CGEventRef)event ofType:(CGEventType)type
{
    // The system disables a slow/interrupted tap; re-enable and move on.
    if (type == kCGEventTapDisabledByTimeout ||
        type == kCGEventTapDisabledByUserInput) {
        if (_tapPort != NULL) {
            CGEventTapEnable(_tapPort, true);
        }
        return event;
    }
    if (type != NX_SYSDEFINED) {
        return event;
    }

    NSEvent *ns = nil;
    @try {
        ns = [NSEvent eventWithCGEvent:event];
    }
    @catch (NSException *e) {
        return event;
    }
    if (ns == nil || [ns subtype] != DG_SUBTYPE_AUX_BUTTONS) {
        return event;
    }

    int data1     = (int)[ns data1];
    int keyCode   = (data1 & 0xFFFF0000) >> 16;
    int keyFlags  = (data1 & 0x0000FFFF);
    BOOL pressed  = (((keyFlags & 0xFF00) >> 8) == DG_KEYSTATE_DOWN);
    BOOL isRepeat = (keyFlags & 0x1) != 0;

    DGMediaKeyKind kind = [DGMediaKeyRouter kindForKeyCode:keyCode];
    if (kind == DGMediaKeyNone) {
        return event;   // volume, brightness, etc. — not ours
    }

    // Ours: hand it to the main thread (no GCD/blocks on 10.5) and consume the
    // event so it never reaches iTunes' remote-control daemon.
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:(int)kind],  @"kind",
        [NSNumber numberWithBool:pressed],   @"pressed",
        [NSNumber numberWithBool:isRepeat],  @"repeat", nil];
    [self performSelectorOnMainThread:@selector(deliverKeyInfo:)
                           withObject:info
                        waitUntilDone:NO];
    return NULL;
}

- (void)deliverKeyInfo:(NSDictionary *)info
{
    [_delegate mediaKeyTap:self
               receivedKey:(DGMediaKeyKind)[[info objectForKey:@"kind"] intValue]
                   pressed:[[info objectForKey:@"pressed"] boolValue]
                  isRepeat:[[info objectForKey:@"repeat"] boolValue]];
}

@end

static CGEventRef DGMediaKeyTapCallback(CGEventTapProxy proxy,
                                        CGEventType type,
                                        CGEventRef event,
                                        void *refcon)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    DGMediaKeyTap *tap = (DGMediaKeyTap *)refcon;
    CGEventRef result = [tap handleCGEvent:event ofType:type];
    [pool drain];
    return result;
}
