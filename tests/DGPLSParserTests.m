//
//  DGPLSParserTests.m
//  DeGelato — fio 2. Pure tests for stream-URL extraction. Offline.
//

#import <SenTestingKit/SenTestingKit.h>
#import "DGPLSParser.h"

@interface DGPLSParserTests : SenTestCase
@end

@implementation DGPLSParserTests

- (void)testPLSBasic
{
    NSString *pls = @"[playlist]\r\nNumberOfEntries=1\r\n"
                    @"File1=http://192.0.2.11:8000/spotify.mp3\r\nVersion=2\r\n";
    STAssertEqualObjects([DGPLSParser firstURLFromPlaylistText:pls],
                         @"http://192.0.2.11:8000/spotify.mp3", @"File1 URL extracted");
}

- (void)testPLSLowestIndexWins
{
    // Regardless of line order, the lowest File index is chosen.
    NSString *pls = @"File2=http://b/2.mp3\r\nFile1=http://a/1.mp3\r\n";
    STAssertEqualObjects([DGPLSParser firstURLFromPlaylistText:pls],
                         @"http://a/1.mp3", @"File1 beats File2");
}

- (void)testM3UBareURL
{
    NSString *m3u = @"#EXTM3U\r\n#EXTINF:-1,gopher-spot\r\nhttp://host:8000/spotify.mp3\r\n";
    STAssertEqualObjects([DGPLSParser firstURLFromPlaylistText:m3u],
                         @"http://host:8000/spotify.mp3", @"bare M3U URL extracted");
}

- (void)testNoURL
{
    STAssertNil([DGPLSParser firstURLFromPlaylistText:@"[playlist]\r\nNumberOfEntries=0\r\n"],
                @"no URL -> nil");
    STAssertNil([DGPLSParser firstURLFromPlaylistText:@""], @"empty -> nil");
    STAssertNil([DGPLSParser firstURLFromPlaylistText:nil], @"nil -> nil");
}

- (void)testPLSPrefersFileOverBare
{
    NSString *mixed = @"http://bare/x.mp3\r\nFile1=http://pls/1.mp3\r\n";
    STAssertEqualObjects([DGPLSParser firstURLFromPlaylistText:mixed],
                         @"http://pls/1.mp3", @"a File<n> entry wins over a bare line");
}

- (void)testFixtureRealStreamPLS
{
    const char *dir = getenv("DG_FIXTURES");
    if (dir == NULL) { return; }
    NSString *path = [[NSString stringWithUTF8String:dir]
                      stringByAppendingPathComponent:@"stream.pls"];
    NSString *pls = [NSString stringWithContentsOfFile:path
                                              encoding:NSUTF8StringEncoding error:NULL];
    if (pls == nil) { return; }
    NSString *url = [DGPLSParser firstURLFromPlaylistText:pls];
    STAssertTrue([url hasPrefix:@"http://"], @"real stream.pls yields an http URL");
    STAssertTrue([url hasSuffix:@"/spotify.mp3"], @"points at the Icecast MP3");
}

@end
