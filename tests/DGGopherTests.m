//
//  DGGopherTests.m
//  DeGelato — fio 20. Gopher item / menu-parse / resource-URL. Offline.
//

#import <SenTestingKit/SenTestingKit.h>
#import "DGGopherItem.h"
#import "DGGopherMenuParser.h"
#import "DGGopherResource.h"

@interface DGGopherTests : SenTestCase
@end

@implementation DGGopherTests

#pragma mark - Item

- (void)testItemKindAndClickable
{
    DGGopherItem *menu = [DGGopherItem itemWithType:'1' display:@"d" selector:@"/s" host:@"h" port:70];
    STAssertEquals([menu kind], DGGopherItemKindMenu, @"1 -> menu");
    STAssertTrue([menu isClickable], @"menu clickable");

    DGGopherItem *info = [DGGopherItem itemWithType:'i' display:@"note" selector:@"" host:@"" port:0];
    STAssertEquals([info kind], DGGopherItemKindInfo, @"i -> info");
    STAssertFalse([info isClickable], @"info not clickable");

    DGGopherItem *unk = [DGGopherItem itemWithType:'X' display:@"?" selector:@"" host:@"" port:0];
    STAssertEquals([unk kind], DGGopherItemKindUnknown, @"unknown type");
    STAssertFalse([unk isClickable], @"unknown not clickable");
}

- (void)testItemExternalURL
{
    DGGopherItem *html = [DGGopherItem itemWithType:'h' display:@"web"
        selector:@"URL:https://example.com" host:@"h" port:70];
    STAssertEqualObjects([html externalURLString], @"https://example.com", @"URL: extracted");
    STAssertTrue([html isClickable], @"html with url clickable");

    DGGopherItem *badHtml = [DGGopherItem itemWithType:'h' display:@"web"
        selector:@"notaurl" host:@"h" port:70];
    STAssertNil([badHtml externalURLString], @"no URL: prefix -> nil");
    STAssertFalse([badHtml isClickable], @"html without url not clickable");
}

#pragma mark - Menu parse

- (void)testMenuParseBasic
{
    NSString *menu =
        @"1Sub Directory\t/sub\thost.example\t70\r\n"
        @"0A Text File\t/file.txt\thost.example\t70\r\n"
        @"iJust info\t\t\t\r\n"
        @".\r\n"
        @"1Should Not Appear\t/x\th\t70\r\n";
    NSArray *items = [DGGopherMenuParser parseMenu:menu];
    STAssertEquals([items count], (NSUInteger)3, @"stops at the . terminator");
    DGGopherItem *r0 = [items objectAtIndex:0];
    DGGopherItem *r1 = [items objectAtIndex:1];
    DGGopherItem *r2 = [items objectAtIndex:2];
    STAssertEquals([r0 kind], DGGopherItemKindMenu, @"row 0 dir");
    STAssertEqualObjects([r0 displayString], @"Sub Directory", @"display");
    STAssertEqualObjects([r0 selector], @"/sub", @"selector");
    STAssertEquals([r1 kind], DGGopherItemKindText, @"row 1 text");
    STAssertEquals([r2 kind], DGGopherItemKindInfo, @"row 2 info");
}

- (void)testMenuParseBadPortDefaults
{
    NSArray *items = [DGGopherMenuParser parseMenu:@"1d\t/s\thost\tnotaport\n"];
    DGGopherItem *it = [items objectAtIndex:0];
    STAssertEquals([it port], (NSInteger)70, @"bad port -> 70");
}

- (void)testMenuParseBareLF
{
    NSArray *items = [DGGopherMenuParser parseMenu:@"1a\t/a\th\t70\n1b\t/b\th\t70\n"];
    STAssertEquals([items count], (NSUInteger)2, @"bare LF lines both parsed");
}

- (void)testMenuParseEmpty
{
    STAssertEquals([[DGGopherMenuParser parseMenu:@""] count], (NSUInteger)0, @"empty");
    STAssertEquals([[DGGopherMenuParser parseMenu:@".\r\n"] count], (NSUInteger)0, @"just terminator");
}

#pragma mark - Resource

- (void)testResourceFromGopherURL
{
    DGGopherResource *r = [DGGopherResource resourceFromLocationString:@"gopher://example.com:71/1/dir"];
    STAssertEqualObjects([r host], @"example.com", @"host");
    STAssertEquals([r port], (NSInteger)71, @"port");
    STAssertEquals([r type], (unichar)'1', @"type from first path char");
    STAssertEqualObjects([r selector], @"/dir", @"selector is the rest");
}

- (void)testResourceBareHost
{
    DGGopherResource *r = [DGGopherResource resourceFromLocationString:@"example.com"];
    STAssertEqualObjects([r host], @"example.com", @"host");
    STAssertEquals([r port], (NSInteger)70, @"default port");
    STAssertEquals([r type], (unichar)'1', @"default type menu");
    STAssertEqualObjects([r selector], @"", @"root selector");
}

- (void)testResourceBlankIsNil
{
    STAssertNil([DGGopherResource resourceFromLocationString:@"   "], @"blank -> nil");
    STAssertNil([DGGopherResource resourceFromLocationString:nil], @"nil -> nil");
}

- (void)testResourceURLRoundTrip
{
    DGGopherResource *r = [DGGopherResource resourceWithHost:@"h" port:70 type:'1'
                                                    selector:@"/x" display:@"h"];
    STAssertEqualObjects([r urlString], @"gopher://h:70/1/x", @"url string");
    STAssertEqualObjects([r locationSummary], @"h:70/x", @"status summary");
}

@end
