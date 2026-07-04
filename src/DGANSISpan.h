//
//  DGANSISpan.h
//  DeGelato — fio 21
//
//  A run of text sharing one set of SGR attributes. Colors are resolved RGB byte
//  triples so this type (and the parser producing it) stay AppKit-free. Ported
//  from DeToca's ANSISpan.
//

#import <Foundation/Foundation.h>
#import "DGANSIPalette.h"

@interface DGANSISpan : NSObject {
    NSString  *_text;
    BOOL       _bold;
    BOOL       _hasForeground;
    DGANSIRGB  _foreground;
    BOOL       _hasBackground;
    DGANSIRGB  _background;
}

@property (nonatomic, copy)   NSString  *text;
@property (nonatomic, assign) BOOL       bold;
@property (nonatomic, assign) BOOL       hasForeground;
@property (nonatomic, assign) DGANSIRGB  foreground;
@property (nonatomic, assign) BOOL       hasBackground;
@property (nonatomic, assign) DGANSIRGB  background;

@end
