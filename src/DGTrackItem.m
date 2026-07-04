//
//  DGTrackItem.m
//  DeGelato — fio 5
//

#import "DGTrackItem.h"
#import "DGApiParser.h"   // +fieldsFromResponse:

@implementation DGTrackItem

@synthesize uri = _uri;
@synthesize track = _track;
@synthesize artist = _artist;
@synthesize albumId = _albumId;
@synthesize durationMs = _durationMs;

- (void)dealloc
{
    [_uri release];
    [_track release];
    [_artist release];
    [_albumId release];
    [super dealloc];
}

+ (NSArray *)itemsFromFields:(NSDictionary *)fields
{
    NSMutableArray *items = [NSMutableArray array];
    NSUInteger i = 0;
    for (;;) {
        NSString *uri = [fields objectForKey:
                         [NSString stringWithFormat:@"item.%lu.uri", (unsigned long)i]];
        if (uri == nil) {
            break;   // contiguous 0..n-1; first gap ends the list
        }
        DGTrackItem *it = [[[DGTrackItem alloc] init] autorelease];
        it.uri = uri;
        it.track = [fields objectForKey:
                    [NSString stringWithFormat:@"item.%lu.track", (unsigned long)i]];
        it.artist = [fields objectForKey:
                     [NSString stringWithFormat:@"item.%lu.artist", (unsigned long)i]];
        it.albumId = [fields objectForKey:
                      [NSString stringWithFormat:@"item.%lu.album_id", (unsigned long)i]];
        it.durationMs = [[fields objectForKey:
                          [NSString stringWithFormat:@"item.%lu.duration_ms", (unsigned long)i]]
                         longLongValue];
        [items addObject:it];
        i++;
    }
    return items;
}

+ (NSArray *)itemsFromResponse:(NSString *)body
{
    return [self itemsFromFields:[DGApiParser fieldsFromResponse:body]];
}

@end
