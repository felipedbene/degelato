//
//  DGGopherClient.h
//  DeGelato — fio 1; gopher client rewritten in fio 8 (see .m)
//
//  One RFC 1436 gopher transaction: connect to host:port, write "selector\r\n",
//  read the response to EOF, hand the raw bytes to the delegate on the MAIN
//  thread. The implementation runs the transaction on a dedicated BSD-socket
//  worker thread (getaddrinfo + connect, the path nc uses) rather than CFStream
//  — CFStream/CFHost stalled intermittently on 10.5 (R7; see the .m and
//  design/INVESTIGATION-command-spam.md). It is DeGelato's counterpart to
//  DeToca's GopherRequest.
//
//  One request at a time per instance. The receiver retains itself for the
//  duration of a request (like NSURLConnection), so callers may release their
//  reference right after -start. A main-thread watchdog bounds the whole
//  transaction; the worker also self-bounds connect + read. -cancel is safe at
//  any point, including mid-flight from -dealloc (it can't un-send a command).
//

#import <Foundation/Foundation.h>

@class DGGopherClient;

@protocol DGGopherClientDelegate <NSObject>
- (void)dgGopherClient:(DGGopherClient *)client didFinishWithData:(NSData *)data;
- (void)dgGopherClient:(DGGopherClient *)client didFailWithError:(NSError *)error;
@end

extern NSString * const DGGopherErrorDomain;

enum {
    DGGopherErrorConnect = 1,   // socket could not be created / connected
    DGGopherErrorTimeout = 2,   // whole transaction exceeded the deadline
    DGGopherErrorStream  = 3    // read/write error while in flight
};

@interface DGGopherClient : NSObject {
    NSString *_host;
    NSInteger _port;
    NSString *_selector;
    id <DGGopherClientDelegate> _delegate;   // not retained

    NSTimer *_timeout;           // main-thread transaction watchdog

    BOOL _running;
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
