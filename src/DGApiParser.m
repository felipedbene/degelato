//
//  DGApiParser.m
//  DeGelato — fio 1
//

#import "DGApiParser.h"
#import "DGNowSnapshot.h"

@implementation DGApiParser

+ (NSDictionary *)fieldsFromResponse:(NSString *)body
{
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    if ([body length] == 0) {
        return fields;
    }
    // Split on LF; a trailing CR (from CRLF) is stripped per line below, so both
    // CRLF and bare-LF documents parse identically.
    NSArray *lines = [body componentsSeparatedByString:@"\n"];
    NSUInteger i, n = [lines count];
    for (i = 0; i < n; i++) {
        NSString *line = [lines objectAtIndex:i];
        if ([line hasSuffix:@"\r"]) {
            line = [line substringToIndex:[line length] - 1];
        }
        NSRange tab = [line rangeOfString:@"\t"];
        if (tab.location == NSNotFound) {
            continue;   // not a key<TAB>value line (blank line, lone "." terminator, garbage)
        }
        NSString *key = [line substringToIndex:tab.location];
        NSString *value = [line substringFromIndex:tab.location + 1];
        if ([key length] > 0) {
            [fields setObject:value forKey:key];   // last value wins
        }
    }
    return fields;
}

+ (DGNowSnapshot *)snapshotFromFields:(NSDictionary *)fields
{
    return [[[DGNowSnapshot alloc] initWithFields:fields] autorelease];
}

+ (DGNowSnapshot *)snapshotFromResponse:(NSString *)body
{
    return [self snapshotFromFields:[self fieldsFromResponse:body]];
}

+ (NSString *)textFromData:(NSData *)data
{
    if ([data length] == 0) {
        return @"";
    }
    NSString *text = [[[NSString alloc] initWithData:data
                                            encoding:NSUTF8StringEncoding] autorelease];
    if (text == nil) {
        // Garbage / invalid UTF-8: fall back to Latin-1, which maps every byte
        // and never fails. The tokenizer then skips any line lacking a TAB, so
        // non-text noise degrades to an empty field set rather than a crash.
        text = [[[NSString alloc] initWithData:data
                                      encoding:NSISOLatin1StringEncoding] autorelease];
    }
    return (text != nil) ? text : @"";
}

+ (BOOL)dataIsJPEG:(NSData *)data
{
    if ([data length] < 2) {
        return NO;
    }
    const unsigned char *b = (const unsigned char *)[data bytes];
    return (b[0] == 0xFF && b[1] == 0xD8);
}

@end
