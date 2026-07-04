//
//  DGGopherClient.m
//  DeGelato — fio 1; gopher client rewritten in fio 8 (see below)
//
//  One RFC 1436 gopher transaction on a dedicated worker thread, results
//  marshalled back to the main thread. This deliberately bypasses CFStream:
//  the CFStream/CFHost path stalled intermittently on 10.5 — a numeric-literal
//  host still routed through CFHost/mDNSResponder and, when mDNS was degraded,
//  the connect opened no socket at all and hung the whole 10 s timeout (R7,
//  see design/INVESTIGATION-command-spam.md; fio 8 A/B/C isolation: the BSD
//  path went from ~2% to ~100% success). The connect is the exact path `nc`
//  uses: getaddrinfo(AI_NUMERICHOST) + connect(), proven 20/20 on the G5.
//
//  Threading contract (10.5, no GCD/blocks): ONE worker thread per request.
//  The worker touches only immutable config (_host/_port/_selector, set before
//  -start spawns it) plus local variables, and hands its single result across
//  via -performSelectorOnMainThread:. ALL completion state (_done, _delegate,
//  the timer) lives on the main thread — pure message-passing, no shared
//  mutable state, so the PPC 970's weak memory model never becomes relevant.
//

#import "DGGopherClient.h"

#import <sys/socket.h>
#import <sys/time.h>
#import <netdb.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

NSString * const DGGopherErrorDomain = @"DGGopherErrorDomain";

// LAN deadline: the worker bounds its own connect (select) and read (SO_RCVTIMEO)
// with this. 2 s is generous for a LAN gopher round-trip (~tens of ms) while
// turning a black-holed connect into a fast blip instead of a 10 s outage (R7).
#define DG_TIMEOUT_SECONDS 2.0
// Main-thread watchdog: a last-resort net a few seconds past the worker's own
// deadline, so it only fires if a worker truly wedges in a syscall.
#define DG_WATCHDOG_SECONDS (DG_TIMEOUT_SECONDS + 3.0)
#define DG_READ_CHUNK      8192

static NSError *DGMakeError(NSInteger code, NSString *message)
{
    NSDictionary *info = [NSDictionary dictionaryWithObject:message
                                                    forKey:NSLocalizedDescriptionKey];
    return [NSError errorWithDomain:DGGopherErrorDomain code:code userInfo:info];
}

@interface DGGopherClient ()
- (void)workerConnectAndRead;                 // background thread
- (void)deliverFail:(NSString *)msg code:(NSInteger)code;  // background thread
- (void)workerDidFinish:(NSData *)data;       // main thread
- (void)workerDidFail:(NSError *)error;       // main thread
- (void)teardown;                             // main thread
@end

@implementation DGGopherClient

@synthesize host = _host;
@synthesize port = _port;
@synthesize selector = _selector;
@synthesize delegate = _delegate;

+ (id)clientWithHost:(NSString *)host
                port:(NSInteger)port
            selector:(NSString *)selector
{
    DGGopherClient *c = [[[self alloc] init] autorelease];
    c.host = host;
    c.port = port;
    c.selector = selector;
    return c;
}

- (void)dealloc
{
    [self teardown];
    [_host release];
    [_selector release];
    [super dealloc];
}

#pragma mark - Lifecycle (main thread)

- (void)start
{
    if (_running) {
        return;   // one request at a time
    }
    _running = YES;
    _done = NO;

    // Belt-and-suspenders deadline on the main thread: even if a worker wedges
    // in a syscall, the transaction still fails and polling continues. The
    // worker also self-bounds (select on connect, SO_RCVTIMEO on read), so this
    // rarely fires.
    _timeout = [[NSTimer timerWithTimeInterval:DG_WATCHDOG_SECONDS
                                        target:self
                                      selector:@selector(timeoutFired:)
                                      userInfo:nil
                                       repeats:NO] retain];
    [[NSRunLoop currentRunLoop] addTimer:_timeout forMode:NSRunLoopCommonModes];

    // Retain across the worker's lifetime; released exactly once, in the
    // worker's main-thread delivery (workerDidFinish:/workerDidFail:).
    [self retain];
    [NSThread detachNewThreadSelector:@selector(workerConnectAndRead)
                             toTarget:self
                           withObject:nil];
}

- (void)cancel
{
    if (!_running || _done) {
        return;
    }
    _delegate = nil;   // suppress the callback
    _done = YES;       // the worker's eventual delivery will drop + release
    [self teardown];
}

- (void)timeoutFired:(NSTimer *)timer
{
    if (_done) {
        return;
    }
    _done = YES;
    id <DGGopherClientDelegate> d = _delegate;
    [self teardown];
    // Do NOT release here: the worker still holds the -start retain and will
    // release it when its (now-dropped) delivery lands.
    [d dgGopherClient:self didFailWithError:DGMakeError(DGGopherErrorTimeout,
        [NSString stringWithFormat:@"Timed out talking to %@:%ld.", _host, (long)_port])];
}

- (void)teardown
{
    [_timeout invalidate];
    [_timeout release];
    _timeout = nil;
    _running = NO;
}

#pragma mark - Worker (background thread; immutable reads + message-passing only)

- (void)workerConnectAndRead
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    const char *hostC = [(_host ? _host : @"") UTF8String];
    char portStr[16];
    snprintf(portStr, sizeof portStr, "%ld", (long)_port);
    NSString *line = [(_selector ? _selector : @"") stringByAppendingString:@"\r\n"];
    NSData *reqData = [line dataUsingEncoding:NSUTF8StringEncoding];

    // Numeric-only resolution: a literal IP resolves instantly with no DNS/mDNS
    // round-trip — the CFHost path Arm C exists to bypass.
    struct addrinfo hints;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_NUMERICHOST;
    struct addrinfo *res = NULL;
    if (getaddrinfo(hostC, portStr, &hints, &res) != 0 || res == NULL) {
        if (res) freeaddrinfo(res);
        [self deliverFail:@"Could not resolve" code:DGGopherErrorConnect];
        [pool release];
        return;
    }

    int fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0) {
        freeaddrinfo(res);
        [self deliverFail:@"Could not open a socket to" code:DGGopherErrorConnect];
        [pool release];
        return;
    }

    // Non-blocking connect bounded by select(), so a black-holed SYN fails fast
    // instead of hanging a whole thread.
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    int cr = connect(fd, res->ai_addr, res->ai_addrlen);
    if (cr < 0 && errno == EINPROGRESS) {
        fd_set wset;
        FD_ZERO(&wset);
        FD_SET(fd, &wset);
        struct timeval tv;
        tv.tv_sec = (long)DG_TIMEOUT_SECONDS;
        tv.tv_usec = 0;
        int sr = select(fd + 1, NULL, &wset, NULL, &tv);
        if (sr <= 0) {
            close(fd); freeaddrinfo(res);
            [self deliverFail:@"Timed out connecting to" code:DGGopherErrorTimeout];
            [pool release];
            return;
        }
        int soe = 0;
        socklen_t sl = sizeof soe;
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soe, &sl) < 0 || soe != 0) {
            close(fd); freeaddrinfo(res);
            [self deliverFail:@"Could not connect to" code:DGGopherErrorConnect];
            [pool release];
            return;
        }
    } else if (cr < 0) {
        close(fd); freeaddrinfo(res);
        [self deliverFail:@"Could not connect to" code:DGGopherErrorConnect];
        [pool release];
        return;
    }
    freeaddrinfo(res);

    // Back to blocking, with read/write deadlines.
    fcntl(fd, F_SETFL, flags);
    struct timeval tv;
    tv.tv_sec = (long)DG_TIMEOUT_SECONDS;
    tv.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);

    // Write "selector\r\n" fully.
    const uint8_t *rb = (const uint8_t *)[reqData bytes];
    NSUInteger rlen = [reqData length], off = 0;
    BOOL werr = NO;
    while (off < rlen) {
        ssize_t w = send(fd, rb + off, rlen - off, 0);
        if (w <= 0) { werr = YES; break; }
        off += (NSUInteger)w;
    }
    if (werr) {
        close(fd);
        [self deliverFail:@"Write failed to" code:DGGopherErrorStream];
        [pool release];
        return;
    }

    // Read to EOF.
    NSMutableData *buf = [[NSMutableData alloc] init];
    uint8_t rbuf[DG_READ_CHUNK];
    BOOL rerr = NO;
    for (;;) {
        ssize_t r = recv(fd, rbuf, sizeof rbuf, 0);
        if (r > 0) {
            [buf appendBytes:rbuf length:(NSUInteger)r];
        } else if (r == 0) {
            break;   // clean EOF
        } else {
            rerr = YES; break;   // error / SO_RCVTIMEO
        }
    }
    close(fd);
    if (rerr && [buf length] == 0) {
        [buf release];
        [self deliverFail:@"Read failed from" code:DGGopherErrorStream];
        [pool release];
        return;
    }
    [self performSelectorOnMainThread:@selector(workerDidFinish:) withObject:buf waitUntilDone:NO];
    [buf release];   // performSelector retained it for the handoff
    [pool release];
}

- (void)deliverFail:(NSString *)msg code:(NSInteger)code
{
    NSError *e = DGMakeError(code,
        [NSString stringWithFormat:@"%@ %@:%ld.", msg, _host, (long)_port]);
    [self performSelectorOnMainThread:@selector(workerDidFail:) withObject:e waitUntilDone:NO];
}

#pragma mark - Completion (main thread)

- (void)workerDidFinish:(NSData *)data
{
    if (_done) {
        [self release];   // already timed out / cancelled; balance -start retain
        return;
    }
    _done = YES;
    id <DGGopherClientDelegate> d = _delegate;
    [self teardown];
    [d dgGopherClient:self didFinishWithData:data];
    [self release];   // balance -start retain
}

- (void)workerDidFail:(NSError *)error
{
    if (_done) {
        [self release];
        return;
    }
    _done = YES;
    id <DGGopherClientDelegate> d = _delegate;
    [self teardown];
    [d dgGopherClient:self didFailWithError:error];
    [self release];   // balance -start retain
}

@end
