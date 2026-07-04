//
//  DGGopherClientTests.m
//  DeGelato — fio 1. Exercises the run-loop NSStream client against a localhost
//  loopback server — no LAN, no gopher-spot. Verifies the happy path (request
//  written, response accumulated to EOF, single didFinish) and the failure path
//  (connection refused -> single didFail).
//

#import <SenTestingKit/SenTestingKit.h>
#import "DGGopherClient.h"

#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>
#import <string.h>

#pragma mark - Minimal one-shot loopback server

@interface DGLoopbackServer : NSObject {
    int    _listenFd;
    int    _port;
    NSData *_response;
}
- (id)initWithResponse:(NSData *)response;
- (int)port;
- (void)start;
@end

@implementation DGLoopbackServer

- (id)initWithResponse:(NSData *)response
{
    self = [super init];
    if (self != nil) {
        _response = [response retain];
        _listenFd = socket(AF_INET, SOCK_STREAM, 0);
        int on = 1;
        setsockopt(_listenFd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        addr.sin_port = 0;   // ask the kernel for an ephemeral port
        bind(_listenFd, (struct sockaddr *)&addr, sizeof(addr));
        listen(_listenFd, 1);

        socklen_t len = sizeof(addr);
        getsockname(_listenFd, (struct sockaddr *)&addr, &len);
        _port = ntohs(addr.sin_port);
    }
    return self;
}

- (void)dealloc
{
    [_response release];
    [super dealloc];
}

- (int)port { return _port; }

- (void)start
{
    [NSThread detachNewThreadSelector:@selector(run) toTarget:self withObject:nil];
}

- (void)run
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int conn = accept(_listenFd, NULL, NULL);
    if (conn >= 0) {
        // Consume the request line (we don't care about its content).
        char rbuf[256];
        recv(conn, rbuf, sizeof(rbuf), 0);

        const uint8_t *bytes = (const uint8_t *)[_response bytes];
        NSUInteger len = [_response length], sent = 0;
        while (sent < len) {
            ssize_t n = send(conn, bytes + sent, len - sent, 0);
            if (n <= 0) break;
            sent += (NSUInteger)n;
        }
        shutdown(conn, SHUT_RDWR);   // signal EOF to the client
        close(conn);
    }
    close(_listenFd);
    [pool release];
}

@end

// A loopback port with nothing listening: bind an ephemeral port, read it, then
// close — a connect there should be refused.
static int DGRefusedPort(void)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0;
    bind(fd, (struct sockaddr *)&addr, sizeof(addr));
    socklen_t len = sizeof(addr);
    getsockname(fd, (struct sockaddr *)&addr, &len);
    int port = ntohs(addr.sin_port);
    close(fd);
    return port;
}

#pragma mark - Tests

@interface DGGopherClientTests : SenTestCase <DGGopherClientDelegate> {
    BOOL     _finished;
    BOOL     _failed;
    NSData  *_got;
    NSError *_err;
    int      _callbacks;
}
@end

@implementation DGGopherClientTests

- (void)setUp
{
    _finished = NO;
    _failed = NO;
    _callbacks = 0;
    [_got release]; _got = nil;
    [_err release]; _err = nil;
}

- (void)tearDown
{
    [_got release]; _got = nil;
    [_err release]; _err = nil;
}

- (void)dgGopherClient:(DGGopherClient *)client didFinishWithData:(NSData *)data
{
    _callbacks++;
    _finished = YES;
    _got = [data retain];
}

- (void)dgGopherClient:(DGGopherClient *)client didFailWithError:(NSError *)error
{
    _callbacks++;
    _failed = YES;
    _err = [error retain];
}

// Pump the current run loop until a flag flips or we hit the deadline.
- (BOOL)spinUntilFinishedOrFailed:(NSTimeInterval)timeout
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!_finished && !_failed && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop]
            runMode:NSDefaultRunLoopMode
            beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return (_finished || _failed);
}

- (void)testHappyPathAccumulatesToEOF
{
    NSString *bodyStr = @"api\t1\r\nstate\tplaying\r\ntrack\tMamma Mia\r\nartist\tABBA\r\n";
    NSData *body = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];

    DGLoopbackServer *server = [[[DGLoopbackServer alloc] initWithResponse:body] autorelease];
    [server start];

    DGGopherClient *client = [DGGopherClient clientWithHost:@"127.0.0.1"
                                                       port:[server port]
                                                   selector:@"/spot/api/1/now"];
    [client setDelegate:self];
    [client start];

    STAssertTrue([self spinUntilFinishedOrFailed:5.0], @"a callback arrived");
    STAssertTrue(_finished, @"finished, not failed");
    STAssertFalse(_failed, @"did not fail");
    STAssertEquals(_callbacks, 1, @"exactly one delegate callback");
    STAssertEqualObjects(_got, body, @"received the full response, byte-for-byte");
}

- (void)testConnectionRefusedFailsOnce
{
    DGGopherClient *client = [DGGopherClient clientWithHost:@"127.0.0.1"
                                                       port:DGRefusedPort()
                                                   selector:@"/spot/api/1/now"];
    [client setDelegate:self];
    [client start];

    STAssertTrue([self spinUntilFinishedOrFailed:5.0], @"a callback arrived");
    STAssertTrue(_failed, @"connection refused -> didFail");
    STAssertFalse(_finished, @"did not finish");
    STAssertEquals(_callbacks, 1, @"exactly one delegate callback");
    STAssertNotNil(_err, @"an error was supplied");
}

- (void)testCancelSuppressesCallback
{
    NSData *body = [@"api\t1\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    DGLoopbackServer *server = [[[DGLoopbackServer alloc] initWithResponse:body] autorelease];
    [server start];

    DGGopherClient *client = [[DGGopherClient clientWithHost:@"127.0.0.1"
                                                        port:[server port]
                                                    selector:@"/spot/api/1/now"] retain];
    [client setDelegate:self];
    [client start];
    [client cancel];   // before any run-loop turn delivers a callback

    // Give the run loop a moment; no callback should ever arrive.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
    while ([deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    STAssertEquals(_callbacks, 0, @"cancel suppressed all delegate callbacks");
    [client release];
}

@end
