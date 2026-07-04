//
//  DGMediaKeyRouterTests.m
//  DeGelato — fio 19. Media-key decode + policy. Offline.
//

#import <SenTestingKit/SenTestingKit.h>
#import "DGMediaKeyRouter.h"

@interface DGMediaKeyRouterTests : SenTestCase
@end

@implementation DGMediaKeyRouterTests

- (void)testKindDecode
{
    STAssertEquals([DGMediaKeyRouter kindForKeyCode:16], DGMediaKeyPlayPause, @"⏯");
    STAssertEquals([DGMediaKeyRouter kindForKeyCode:19], DGMediaKeyNext, @"⏭");
    STAssertEquals([DGMediaKeyRouter kindForKeyCode:20], DGMediaKeyPrevious, @"⏮");
    STAssertEquals([DGMediaKeyRouter kindForKeyCode:7],  DGMediaKeyNone, @"volume/other -> none");
}

- (void)testPlayPauseOnKeyDown
{
    STAssertEquals([DGMediaKeyRouter actionForKind:DGMediaKeyPlayPause pressed:YES isRepeat:NO],
                   DGMediaKeyActionTogglePlayPause, @"play/pause on key-down");
}

- (void)testNextPrevOnKeyDown
{
    STAssertEquals([DGMediaKeyRouter actionForKind:DGMediaKeyNext pressed:YES isRepeat:NO],
                   DGMediaKeyActionNext, @"next");
    STAssertEquals([DGMediaKeyRouter actionForKind:DGMediaKeyPrevious pressed:YES isRepeat:NO],
                   DGMediaKeyActionPrevious, @"prev");
}

- (void)testKeyUpIgnored
{
    STAssertEquals([DGMediaKeyRouter actionForKind:DGMediaKeyPlayPause pressed:NO isRepeat:NO],
                   DGMediaKeyActionNone, @"key-up -> none");
}

- (void)testAutoRepeatIgnored
{
    STAssertEquals([DGMediaKeyRouter actionForKind:DGMediaKeyNext pressed:YES isRepeat:YES],
                   DGMediaKeyActionNone, @"auto-repeat -> none (no machine-gun skip)");
}

- (void)testNoneKind
{
    STAssertEquals([DGMediaKeyRouter actionForKind:DGMediaKeyNone pressed:YES isRepeat:NO],
                   DGMediaKeyActionNone, @"not ours -> none");
}

@end
