//
//  DGMediaKeyRouter.m
//  DeGelato — fio 19
//

#import "DGMediaKeyRouter.h"

@implementation DGMediaKeyRouter

+ (DGMediaKeyKind)kindForKeyCode:(int)keyCode
{
    switch (keyCode) {
        case DGNXKeyTypePlay: return DGMediaKeyPlayPause;
        case DGNXKeyTypeNext: return DGMediaKeyNext;
        case DGNXKeyTypePrev: return DGMediaKeyPrevious;
        default:              return DGMediaKeyNone;
    }
}

+ (DGMediaKeyAction)actionForKind:(DGMediaKeyKind)kind
                          pressed:(BOOL)pressed
                         isRepeat:(BOOL)isRepeat
{
    // Key-down only, one action per physical press.
    if (!pressed || isRepeat) {
        return DGMediaKeyActionNone;
    }
    switch (kind) {
        case DGMediaKeyPlayPause: return DGMediaKeyActionTogglePlayPause;
        case DGMediaKeyNext:      return DGMediaKeyActionNext;
        case DGMediaKeyPrevious:  return DGMediaKeyActionPrevious;
        case DGMediaKeyNone:
        default:                  return DGMediaKeyActionNone;
    }
}

@end
