//
//  DGGopherMenuParser.h
//  DeGelato — fio 20
//
//  RFC 1436 gophermap → DGGopherItem[]. CRLF/LF tolerant, "."-terminated,
//  malformed lines tolerated (bad port -> 70), UTF-8 with Latin-1 fallback.
//  Ported from DeToca's GopherMenuParser. Pure Foundation.
//

#import <Foundation/Foundation.h>

@interface DGGopherMenuParser : NSObject

+ (NSString *)stringFromData:(NSData *)data;   // UTF-8, Latin-1 fallback, never nil
+ (NSArray *)parseMenuData:(NSData *)data;     // -> DGGopherItem[]
+ (NSArray *)parseMenu:(NSString *)text;       // -> DGGopherItem[]

@end
