//
//  DGGopherResource.h
//  DeGelato — fio 20
//
//  A Gopher resource: host:port + item type + selector. Parses a gopher://…
//  location (or a bare host[:port][/type selector]) and formats it back.
//  Ported from DeToca's GopherResource. Pure Foundation.
//

#import <Foundation/Foundation.h>

@class DGGopherItem;

@interface DGGopherResource : NSObject {
    NSString *_host;
    NSInteger _port;
    unichar   _type;
    NSString *_selector;
    NSString *_displayString;
}

@property (nonatomic, copy)   NSString *host;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, assign) unichar   type;
@property (nonatomic, copy)   NSString *selector;
@property (nonatomic, copy)   NSString *displayString;

+ (id)resourceWithHost:(NSString *)host
                  port:(NSInteger)port
                  type:(unichar)type
              selector:(NSString *)selector
               display:(NSString *)display;
+ (id)resourceWithItem:(DGGopherItem *)item;

// Parse "gopher://host:port/<type><selector>", or a bare "host[:port][/…]".
// Any scheme is treated as gopher. Returns nil for blank/invalid input.
+ (id)resourceFromLocationString:(NSString *)location;

- (NSString *)locationSummary;   // "host:port/selector" (status bar)
- (NSString *)urlString;         // "gopher://host:port/<type><selector>"

@end
