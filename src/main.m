//
//  main.m
//  DeGelato — fio 1
//
//  No NIB: the application object, its delegate, and the menu bar are all wired
//  up in code. On 10.5 we drive NSApplication directly.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    // A bundled app (no LSUIElement) is already a regular, Dock-visible app on
    // 10.5; -setActivationPolicy: is 10.6+, so we don't call it here.
    NSApplication *app = [NSApplication sharedApplication];

    AppDelegate *delegate = [[AppDelegate alloc] init];
    [app setDelegate:delegate];
    [app run];

    [delegate release];
    [pool release];
    return 0;
}
