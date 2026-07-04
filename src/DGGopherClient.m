//
//  DGGopherClient.m
//  DeGelato — fio 1
//

#import "DGGopherClient.h"

NSString * const DGGopherErrorDomain = @"DGGopherErrorDomain";

#define DG_TIMEOUT_SECONDS 10.0
#define DG_READ_CHUNK      8192

static NSError *DGMakeError(NSInteger code, NSString *message)
{
    NSDictionary *info = [NSDictionary dictionaryWithObject:message
                                                    forKey:NSLocalizedDescriptionKey];
    return [NSError errorWithDomain:DGGopherErrorDomain code:code userInfo:info];
}

@interface DGGopherClient ()
- (void)finishWithData:(NSData *)data;
- (void)failWithError:(NSError *)error;
- (void)teardown;
- (void)writeRequestIfPossible;
- (void)closeOutput;
- (void)drainInput;
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
    // If a caller drops us mid-flight we must not leave streams scheduled.
    [self teardown];
    [_host release];
    [_selector release];
    [super dealloc];
}

#pragma mark - Lifecycle

- (void)start
{
    if (_running) {
        return;   // one request at a time
    }
    _running = YES;
    _done = NO;
    _wroteRequest = NO;
    _reqOffset = 0;

    NSString *line = [(_selector ? _selector : @"") stringByAppendingString:@"\r\n"];
    _request = [[line dataUsingEncoding:NSUTF8StringEncoding] retain];
    _buffer = [[NSMutableData alloc] init];

    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocketToHost(NULL, (CFStringRef)_host,
                                       (UInt32)_port, &readStream, &writeStream);
    if (readStream == NULL || writeStream == NULL) {
        if (readStream)  CFRelease(readStream);
        if (writeStream) CFRelease(writeStream);
        [self failWithError:DGMakeError(DGGopherErrorConnect,
            [NSString stringWithFormat:@"Could not open a connection to %@:%ld.",
                _host, (long)_port])];
        return;
    }
    // Toll-free bridge; take ownership of the +1 refs (released in -teardown).
    _input = (NSInputStream *)readStream;
    _output = (NSOutputStream *)writeStream;

    // Retain ourselves for the duration; balanced in -teardown. Lets the caller
    // release its reference immediately after -start.
    [self retain];

    [_input setDelegate:self];
    [_output setDelegate:self];
    // Schedule in the common modes, not just the default mode: while the user is
    // dragging a slider, holding a button, or tracking a menu, the run loop runs
    // in NSEventTrackingRunLoopMode and a default-mode-only stream would stall
    // until the interaction ends — a stalled poll then times out as "offline".
    NSRunLoop *rl = [NSRunLoop currentRunLoop];
    [_input scheduleInRunLoop:rl forMode:NSRunLoopCommonModes];
    [_output scheduleInRunLoop:rl forMode:NSRunLoopCommonModes];
    [_input open];
    [_output open];

    _timeout = [[NSTimer timerWithTimeInterval:DG_TIMEOUT_SECONDS
                                        target:self
                                      selector:@selector(timeoutFired:)
                                      userInfo:nil
                                       repeats:NO] retain];
    [rl addTimer:_timeout forMode:NSRunLoopCommonModes];
}

- (void)cancel
{
    if (!_running) {
        return;
    }
    _delegate = nil;   // suppress any pending callback
    [self teardown];
}

- (void)timeoutFired:(NSTimer *)timer
{
    [self failWithError:DGMakeError(DGGopherErrorTimeout,
        [NSString stringWithFormat:@"Timed out talking to %@:%ld.",
            _host, (long)_port])];
}

#pragma mark - Stream events

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event
{
    switch (event) {
        case NSStreamEventHasSpaceAvailable:
            if (stream == _output) {
                [self writeRequestIfPossible];
            }
            break;

        case NSStreamEventHasBytesAvailable:
            if (stream == _input) {
                [self drainInput];
            }
            break;

        case NSStreamEventEndEncountered:
            if (stream == _input) {
                // Clean EOF: the server has sent the whole response.
                [self drainInput];   // grab anything buffered before EOF
                [self finishWithData:[[_buffer retain] autorelease]];
            }
            break;

        case NSStreamEventErrorOccurred: {
            // Only the input stream is authoritative for completion. Once the
            // selector is written we drop the output stream, but a real connect
            // failure surfaces on the input stream too — so ignore output-side
            // errors (the peer closing its read end after responding is normal).
            if (stream != _input) {
                break;
            }
            NSError *err = [stream streamError];
            if (err == nil) {
                err = DGMakeError(DGGopherErrorStream, @"The connection failed.");
            }
            [self failWithError:err];
            break;
        }

        default:
            break;   // OpenCompleted, None
    }
}

- (void)writeRequestIfPossible
{
    if (_wroteRequest || _request == nil) {
        return;
    }
    const uint8_t *bytes = (const uint8_t *)[_request bytes];
    NSUInteger len = [_request length];
    while (_reqOffset < len && [_output hasSpaceAvailable]) {
        NSInteger n = [_output write:bytes + _reqOffset
                           maxLength:len - _reqOffset];
        if (n <= 0) {
            // Error will arrive as NSStreamEventErrorOccurred; stop here.
            return;
        }
        _reqOffset += (NSUInteger)n;
    }
    if (_reqOffset >= len) {
        _wroteRequest = YES;   // selector sent; now just read to EOF
        [self closeOutput];    // done writing — drop the output stream so its
                               // later close/error events can't fail the request
    }
}

- (void)closeOutput
{
    if (_output == nil) {
        return;
    }
    [_output setDelegate:nil];
    [_output removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [_output close];
    [_output release];
    _output = nil;
}

- (void)drainInput
{
    uint8_t buf[DG_READ_CHUNK];
    while ([_input hasBytesAvailable]) {
        NSInteger n = [_input read:buf maxLength:sizeof(buf)];
        if (n > 0) {
            [_buffer appendBytes:buf length:(NSUInteger)n];
        } else {
            break;   // 0 == EOF (handled via EndEncountered), <0 == error event
        }
    }
}

#pragma mark - Completion

- (void)finishWithData:(NSData *)data
{
    if (_done) {
        return;
    }
    _done = YES;
    // Keep ourselves alive across the callback + teardown in case the delegate
    // releases its last reference to us from within the callback.
    [[self retain] autorelease];
    id <DGGopherClientDelegate> d = _delegate;
    [self teardown];
    [d dgGopherClient:self didFinishWithData:data];
}

- (void)failWithError:(NSError *)error
{
    if (_done) {
        return;
    }
    _done = YES;
    [[self retain] autorelease];
    id <DGGopherClientDelegate> d = _delegate;
    [self teardown];
    [d dgGopherClient:self didFailWithError:error];
}

- (void)teardown
{
    [_timeout invalidate];
    [_timeout release];
    _timeout = nil;

    NSRunLoop *rl = [NSRunLoop currentRunLoop];
    if (_input != nil) {
        [_input setDelegate:nil];
        [_input removeFromRunLoop:rl forMode:NSRunLoopCommonModes];
        [_input close];
        [_input release];
        _input = nil;
    }
    if (_output != nil) {
        [_output setDelegate:nil];
        [_output removeFromRunLoop:rl forMode:NSRunLoopCommonModes];
        [_output close];
        [_output release];
        _output = nil;
    }
    [_buffer release];
    _buffer = nil;
    [_request release];
    _request = nil;

    BOOL wasRunning = _running;
    _running = NO;
    if (wasRunning) {
        [self release];   // balances the -retain in -start
    }
}

@end
