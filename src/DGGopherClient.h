//
//  DGGopherClient.h
//  DeGelato — fio 1
//
//  One RFC 1436 gopher transaction over a run-loop-scheduled NSStream pair:
//  connect to host:port, write "selector\r\n", accumulate the response to EOF,
//  then hand the raw bytes to the delegate. 10.5 has no GCD/blocks, so this is
//  deliberately delegate-driven on the current run loop (NSDefaultRunLoopMode) —
//  it is the DeGelato counterpart to DeToca's blocking-socket GopherRequest.
//
//  One request at a time per instance. The receiver retains itself for the
//  duration of a request (like NSURLConnection), so callers may release their
//  reference right after -start. A 10s NSTimer bounds the whole transaction.
//  -cancel is safe at any point, including mid-flight from -dealloc.
//

#import <Foundation/Foundation.h>

@class DGGopherClient;

@protocol DGGopherClientDelegate <NSObject>
- (void)dgGopherClient:(DGGopherClient *)client didFinishWithData:(NSData *)data;
- (void)dgGopherClient:(DGGopherClient *)client didFailWithError:(NSError *)error;
@end

extern NSString * const DGGopherErrorDomain;

enum {
    DGGopherErrorConnect = 1,   // stream could not be created / opened
    DGGopherErrorTimeout = 2,   // whole transaction exceeded the deadline
    DGGopherErrorStream  = 3    // NSStreamEventErrorOccurred while in flight
};

@interface DGGopherClient : NSObject {
    NSString *_host;
    NSInteger _port;
    NSString *_selector;
    id <DGGopherClientDelegate> _delegate;   // not retained

    NSInputStream  *_input;
    NSOutputStream *_output;
    NSMutableData  *_buffer;     // accumulated response bytes
    NSData         *_request;    // "selector\r\n" as UTF-8, for partial writes
    NSUInteger      _reqOffset;  // bytes of _request already written
    NSTimer        *_timeout;

    BOOL _running;
    BOOL _wroteRequest;
    BOOL _done;                  // guards single didFinish/didFail delivery
}

@property (nonatomic, copy)   NSString *host;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, copy)   NSString *selector;
@property (nonatomic, assign) id <DGGopherClientDelegate> delegate;

+ (id)clientWithHost:(NSString *)host
                port:(NSInteger)port
            selector:(NSString *)selector;

// Begin the transaction on the current run loop. The receiver retains itself
// until it finishes, fails, or is cancelled.
- (void)start;

// Stop everything and suppress any further delegate callbacks. Idempotent.
- (void)cancel;

@end
