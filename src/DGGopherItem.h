//
//  DGGopherItem.h
//  DeGelato — fio 20
//
//  One parsed line of a Gopher menu ("gophermap" line), per RFC 1436. Ported
//  from DeToca's GopherItem. Pure Foundation — no AppKit.
//

#import <Foundation/Foundation.h>

typedef enum {
    DGGopherItemKindText = 0,     // '0' text file
    DGGopherItemKindMenu,         // '1' directory / submenu
    DGGopherItemKindSearch,       // '7' full-text search server
    DGGopherItemKindInfo,         // 'i' informational line (non-clickable)
    DGGopherItemKindHTML,         // 'h' HTML / URL: link (opened externally)
    DGGopherItemKindSound,        // 's' sound / audio stream
    DGGopherItemKindError,        // '3' error
    DGGopherItemKindUnknown       // anything else (dimmed, non-clickable)
} DGGopherItemKind;

@interface DGGopherItem : NSObject {
    unichar    _type;           // raw RFC 1436 type character
    NSString  *_displayString;  // user-visible label
    NSString  *_selector;       // selector string sent to the server
    NSString  *_host;           // hostname
    NSInteger  _port;           // TCP port
}

@property (nonatomic, assign) unichar    type;
@property (nonatomic, copy)   NSString  *displayString;
@property (nonatomic, copy)   NSString  *selector;
@property (nonatomic, copy)   NSString  *host;
@property (nonatomic, assign) NSInteger  port;

+ (id)itemWithType:(unichar)type
            display:(NSString *)display
           selector:(NSString *)selector
               host:(NSString *)host
               port:(NSInteger)port;

- (DGGopherItemKind)kind;
- (BOOL)isClickable;
- (NSString *)externalURLString;   // for 'h' "URL:..." selectors; else nil

@end
