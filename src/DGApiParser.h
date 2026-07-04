//
//  DGApiParser.h
//  DeGelato — fio 1
//
//  Turns a raw /spot/api/1 text response into structured data. Pure Foundation,
//  no gopher and no AppKit — this is the unit-testable seam between the wire and
//  the model. The tokenizer tolerates CRLF or bare LF, skips lines without a
//  TAB, and keeps the last value for a repeated key (matching gopher-spot's
//  key<TAB>value document format).
//

#import <Foundation/Foundation.h>

@class DGNowSnapshot;

@interface DGApiParser : NSObject

// Split a raw API response body into a { key: value } dictionary. Each line is
// `key<TAB>value`; a trailing CR is stripped, lines without a TAB are skipped,
// and a repeated key keeps the last value. Nil/empty body -> empty dict.
+ (NSDictionary *)fieldsFromResponse:(NSString *)body;

// Build an immutable snapshot from a raw /now response body (UTF-8 text).
+ (DGNowSnapshot *)snapshotFromResponse:(NSString *)body;

// Build an immutable snapshot from an already-split fields dict (shared with a
// future command path that checks for an `error` key first).
+ (DGNowSnapshot *)snapshotFromFields:(NSDictionary *)fields;

// Decode raw response bytes as UTF-8 text, lenient about a trailing lone `.`
// terminator line (RFC 1436) and invalid byte sequences. Returns @"" on nil.
+ (NSString *)textFromData:(NSData *)data;

// Whether the bytes look like a JPEG (SOI marker FF D8). The /cover endpoint is
// the one binary response — on success it returns raw JPEG; on error it returns
// a tab-KV text document, so a client keys off this before decoding an image.
+ (BOOL)dataIsJPEG:(NSData *)data;

@end
