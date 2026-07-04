//
//  DGServerPrefs.h
//  DeGelato — fio 15
//
//  The gopher-spot backend address, as a preference — one source of truth for
//  the NSUserDefaults keys, the homelab defaults, and the host/port validation
//  that gates the Preferences "Save" button. Replaces the DG_HOST/DG_PORT
//  #defines that were duplicated across four window controllers. Read at call
//  time by every gopher request, so a saved change takes effect on the next
//  poll/command. Ported from DeToca's DTServerPrefs. Pure Foundation —
//  unit-testable.
//

#import <Foundation/Foundation.h>

extern NSString * const DGSpotHostKey;   // @"DGSpotHost"
extern NSString * const DGSpotPortKey;   // @"DGSpotPort"

// Posted (by the Preferences window) when a save actually changed the address,
// so the now-playing window can reconnect.
extern NSString * const DGServerPrefsDidChangeNotification;

@interface DGServerPrefs : NSObject

// --- Validation (Save button gating) ---
+ (BOOL)isValidHost:(NSString *)host;              // non-empty after trimming
+ (BOOL)isValidPort:(NSInteger)port;               // 1...65535
+ (BOOL)isValidHost:(NSString *)host port:(NSInteger)port;

// --- Effective values (defaults-backed; never invalid) ---
+ (NSString *)host;          // stored host, or defaultHost if unset/empty
+ (NSInteger)port;           // stored port, or defaultPort if unset
+ (NSString *)defaultHost;   // the homelab default
+ (NSInteger)defaultPort;    // 70

// Persist host+port. Trims the host. Returns YES if either effective value
// actually changed (so the caller knows whether to reconnect). Callers should
// validate first; an invalid host/port is rejected (returns NO, no write).
+ (BOOL)saveHost:(NSString *)host port:(NSInteger)port;

@end
