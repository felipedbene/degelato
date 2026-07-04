//
//  DGMediaKeyRouter.h
//  DeGelato — fio 19
//
//  Pure decode + policy for the keyboard's media keys (⏮ ⏯ ⏭). Split out of the
//  CGEventTap (DGMediaKeyTap) so the "which key → which action" logic is free of
//  AppKit/Quartz and unit-testable. Ported from DeToca's DTMediaKeyRouter; the
//  radinho is always connected (it polls), so there is no reconnect state — a
//  press maps straight to a transport action. Pure Foundation.
//

#import <Foundation/Foundation.h>

// Raw NX_KEYTYPE_* keycodes (from <IOKit/hidsystem/ev_keymap.h>), redeclared so
// this layer stays IOKit-free. The tap passes the same numbers.
enum {
    DGNXKeyTypePlay = 16,   // NX_KEYTYPE_PLAY   (⏯)
    DGNXKeyTypeNext = 19,   // NX_KEYTYPE_FAST   (⏭)
    DGNXKeyTypePrev = 20    // NX_KEYTYPE_REWIND (⏮)
};

typedef enum {
    DGMediaKeyNone = 0,     // not one of ours — pass the event through
    DGMediaKeyPlayPause,
    DGMediaKeyNext,
    DGMediaKeyPrevious
} DGMediaKeyKind;

typedef enum {
    DGMediaKeyActionNone = 0,         // key-up, repeat, or not ours
    DGMediaKeyActionTogglePlayPause,
    DGMediaKeyActionNext,
    DGMediaKeyActionPrevious
} DGMediaKeyAction;

@interface DGMediaKeyRouter : NSObject

// Decode a raw NX_KEYTYPE_* keycode into a media-key kind.
+ (DGMediaKeyKind)kindForKeyCode:(int)keyCode;

// Decide the action for a decoded key. Acts on key-down only (pressed == YES);
// auto-repeat (isRepeat == YES) is ignored so play/pause never double-toggles and
// next/prev never machine-gun skip.
+ (DGMediaKeyAction)actionForKind:(DGMediaKeyKind)kind
                          pressed:(BOOL)pressed
                         isRepeat:(BOOL)isRepeat;

@end
