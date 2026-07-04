//
//  DGTrackCell.m
//  DeGelato — fio 17
//

#import "DGTrackCell.h"
#import "DGFontManager.h"

#define DG_THUMB 64.0

@implementation DGTrackCell

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)controlView
{
    id value = [self objectValue];
    if (![value isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSDictionary *m = (NSDictionary *)value;

    // Thumbnail on the left, vertically centered.
    NSRect thumb = NSMakeRect(frame.origin.x + 4,
                              frame.origin.y + (frame.size.height - DG_THUMB) / 2.0,
                              DG_THUMB, DG_THUMB);
    NSImage *img = [m objectForKey:@"image"];
    if (img != nil) {
        [img drawInRect:thumb
               fromRect:NSZeroRect
              operation:NSCompositeSourceOver
               fraction:1.0];
    } else {
        // A faint placeholder box keeps the layout stable while the thumb loads.
        [[NSColor colorWithCalibratedWhite:0.85 alpha:1.0] set];
        NSRectFill(thumb);
    }

    // Text to the right of the thumbnail.
    CGFloat tx = NSMaxX(thumb) + 8.0;
    CGFloat tw = NSMaxX(frame) - tx - 6.0;
    if (tw < 10.0) {
        return;
    }

    NSMutableParagraphStyle *ps = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [ps setLineBreakMode:NSLineBreakByTruncatingTail];

    BOOL sel = [self isHighlighted];
    NSColor *titleColor = sel ? [NSColor selectedTextColor] : [NSColor controlTextColor];
    NSColor *subColor   = sel ? [NSColor selectedTextColor] : [NSColor grayColor];

    NSDictionary *titleAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
        [DGFontManager documentFontOfSize:13.0], NSFontAttributeName,
        titleColor,                              NSForegroundColorAttributeName,
        ps,                                      NSParagraphStyleAttributeName, nil];
    NSDictionary *subAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
        [DGFontManager documentFontOfSize:11.0], NSFontAttributeName,
        subColor,                                NSForegroundColorAttributeName,
        ps,                                      NSParagraphStyleAttributeName, nil];

    // The table content is drawn flipped (origin top-left), so a larger y is
    // lower on screen: title sits above subtitle.
    NSString *title = [m objectForKey:@"title"];
    NSString *sub   = [m objectForKey:@"subtitle"];
    NSRect titleRect = NSMakeRect(tx, frame.origin.y + 16.0, tw, 18.0);
    NSRect subRect   = NSMakeRect(tx, frame.origin.y + 38.0, tw, 16.0);
    [(title ? title : @"") drawInRect:titleRect withAttributes:titleAttrs];
    [(sub   ? sub   : @"") drawInRect:subRect   withAttributes:subAttrs];
}

@end
