//
//  DGServerPrefsTests.m
//  DeGelato — fio 15. The gopher-spot address preference. Offline.
//

#import <SenTestingKit/SenTestingKit.h>
#import "DGServerPrefs.h"

@interface DGServerPrefsTests : SenTestCase
@end

@implementation DGServerPrefsTests

- (void)clearKeys
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:DGSpotHostKey];
    [d removeObjectForKey:DGSpotPortKey];
    [d synchronize];
}

- (void)setUp    { [super setUp];    [self clearKeys]; }
- (void)tearDown { [self clearKeys]; [super tearDown]; }

- (void)testHostValidation
{
    STAssertTrue([DGServerPrefs isValidHost:@"10.0.0.1"], @"plain host");
    STAssertTrue([DGServerPrefs isValidHost:@"  host  "], @"non-empty after trim");
    STAssertFalse([DGServerPrefs isValidHost:@""], @"empty rejected");
    STAssertFalse([DGServerPrefs isValidHost:@"   "], @"whitespace rejected");
    STAssertFalse([DGServerPrefs isValidHost:nil], @"nil rejected");
}

- (void)testPortValidation
{
    STAssertTrue([DGServerPrefs isValidPort:1], @"low bound");
    STAssertTrue([DGServerPrefs isValidPort:70], @"gopher");
    STAssertTrue([DGServerPrefs isValidPort:65535], @"high bound");
    STAssertFalse([DGServerPrefs isValidPort:0], @"zero rejected");
    STAssertFalse([DGServerPrefs isValidPort:65536], @"too high rejected");
    STAssertFalse([DGServerPrefs isValidPort:-1], @"negative rejected");
}

- (void)testCombinedValidation
{
    STAssertTrue([DGServerPrefs isValidHost:@"h" port:70], @"both valid");
    STAssertFalse([DGServerPrefs isValidHost:@"" port:70], @"bad host");
    STAssertFalse([DGServerPrefs isValidHost:@"h" port:0], @"bad port");
}

- (void)testDefaultsWhenUnset
{
    STAssertEqualObjects([DGServerPrefs host], [DGServerPrefs defaultHost], @"unset -> default host");
    STAssertEquals([DGServerPrefs port], [DGServerPrefs defaultPort], @"unset -> default port");
    STAssertEqualObjects([DGServerPrefs defaultHost], @"192.0.2.10", @"placeholder default");
    STAssertEquals([DGServerPrefs defaultPort], (NSInteger)70, @"gopher default");
}

- (void)testSaveAndReadBack
{
    STAssertTrue([DGServerPrefs saveHost:@"192.168.1.5" port:7070], @"changed from default");
    STAssertEqualObjects([DGServerPrefs host], @"192.168.1.5", @"host stored");
    STAssertEquals([DGServerPrefs port], (NSInteger)7070, @"port stored");
}

- (void)testSaveNoChangeReportsNo
{
    [DGServerPrefs saveHost:@"host.example" port:70];
    STAssertFalse([DGServerPrefs saveHost:@"host.example" port:70], @"same values -> not changed");
}

- (void)testSaveTrimsHost
{
    [DGServerPrefs saveHost:@"  10.0.0.9  " port:70];
    STAssertEqualObjects([DGServerPrefs host], @"10.0.0.9", @"host trimmed on save");
}

- (void)testSaveRejectsInvalid
{
    [DGServerPrefs saveHost:@"good.host" port:70];
    STAssertFalse([DGServerPrefs saveHost:@"" port:70], @"invalid host not saved");
    STAssertEqualObjects([DGServerPrefs host], @"good.host", @"prior host intact");
    STAssertFalse([DGServerPrefs saveHost:@"good.host" port:99999], @"invalid port not saved");
    STAssertEquals([DGServerPrefs port], (NSInteger)70, @"prior port intact");
}

@end
