//
//  DGAudioStreamer.m
//  DeGelato — fio 2
//
//  Minimal streaming MP3 player built on AudioFileStream + AudioQueue, in the
//  well-established "parse HTTP bytes into packets, fan them into a ring of
//  AudioQueue buffers" pattern. Runs its network + parsing on a dedicated
//  thread; the AudioQueue calls its output callback on its own thread. A
//  pthread mutex/cond gates the buffer ring so the parser blocks (on its own
//  thread, never the main thread) when every buffer is still playing.
//
//  Faithful port of DeToca's DTAudioStreamer — the pipeline is identical; only
//  the class prefix changes. AudioToolbox behaves the same on ppc/10.5.
//

#import "DGAudioStreamer.h"
#import <AudioToolbox/AudioToolbox.h>
#import <pthread.h>

#define DG_NUM_BUFFERS      16
#define DG_BUFFER_SIZE      8192
#define DG_MAX_PACKET_DESCS 512
#define DG_START_THRESHOLD  6      // buffers to prime before starting the queue

typedef struct {
    AudioFileStreamID  audioStream;
    AudioQueueRef      queue;
    AudioStreamBasicDescription asbd;

    AudioQueueBufferRef buffers[DG_NUM_BUFFERS];
    BOOL               inuse[DG_NUM_BUFFERS];
    unsigned int       fillIndex;
    size_t             bytesFilled;
    int                packetsFilled;
    AudioStreamPacketDescription packetDescs[DG_MAX_PACKET_DESCS];

    unsigned int       enqueuedCount;
    BOOL               queueStarted;

    pthread_mutex_t    mutex;
    pthread_cond_t     cond;
} DGStreamState;

@interface DGAudioStreamer ()
- (void)threadMain;
- (void)setupQueueFromStream;
- (void)handlePackets:(UInt32)numBytes count:(UInt32)numPackets
                 data:(const void *)data descs:(AudioStreamPacketDescription *)descs;
- (void)enqueueCurrentBuffer;
- (void)bufferDoneWithRef:(AudioQueueBufferRef)ref;
- (void)failWithMessage:(NSString *)msg;
- (void)notifyStarted;
- (void)dg_reportFailure:(NSString *)msg;
@end

static DGStreamState *DGStateOf(DGAudioStreamer *s);

#pragma mark - CoreAudio C callbacks

static void DGPropertyListener(void *inClientData,
                               AudioFileStreamID inAudioFileStream,
                               AudioFileStreamPropertyID inPropertyID,
                               UInt32 *ioFlags)
{
    DGAudioStreamer *streamer = (DGAudioStreamer *)inClientData;
    if (inPropertyID == kAudioFileStreamProperty_ReadyToProducePackets) {
        [streamer setupQueueFromStream];
    }
}

static void DGPacketsProc(void *inClientData,
                          UInt32 inNumberBytes,
                          UInt32 inNumberPackets,
                          const void *inInputData,
                          AudioStreamPacketDescription *inPacketDescriptions)
{
    DGAudioStreamer *streamer = (DGAudioStreamer *)inClientData;
    [streamer handlePackets:inNumberBytes count:inNumberPackets
                       data:inInputData descs:inPacketDescriptions];
}

static void DGBufferCallback(void *inClientData,
                             AudioQueueRef inAQ,
                             AudioQueueBufferRef inBuffer)
{
    DGAudioStreamer *streamer = (DGAudioStreamer *)inClientData;
    [streamer bufferDoneWithRef:inBuffer];
}

@implementation DGAudioStreamer

@synthesize delegate = _delegate;

static DGStreamState *DGStateOf(DGAudioStreamer *s)
{
    return (DGStreamState *)s->_opaque;
}

- (id)initWithURLString:(NSString *)urlString
{
    self = [super init];
    if (self != nil) {
        _urlString = [urlString copy];
        _volume = 0.75f;

        DGStreamState *st = (DGStreamState *)calloc(1, sizeof(DGStreamState));
        pthread_mutex_init(&st->mutex, NULL);
        pthread_cond_init(&st->cond, NULL);
        _opaque = st;
    }
    return self;
}

- (void)dealloc
{
    [self stop];
    DGStreamState *st = DGStateOf(self);
    if (st != NULL) {
        pthread_mutex_destroy(&st->mutex);
        pthread_cond_destroy(&st->cond);
        free(st);
        _opaque = NULL;
    }
    [_urlString release];
    [_connection release];
    [_thread release];
    [super dealloc];
}

#pragma mark - Public control

- (void)start
{
    if (_thread != nil) {
        return;
    }
    _thread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain) object:nil];
    [_thread start];
}

- (void)stop
{
    _stopped = YES;
    DGStreamState *st = DGStateOf(self);
    if (st != NULL && st->queue != NULL) {
        AudioQueueStop(st->queue, true);
    }
    // Wake the parser if it is blocked waiting for a free buffer.
    if (st != NULL) {
        pthread_mutex_lock(&st->mutex);
        pthread_cond_broadcast(&st->cond);
        pthread_mutex_unlock(&st->mutex);
    }
}

- (void)setPaused:(BOOL)paused
{
    DGStreamState *st = DGStateOf(self);
    if (st == NULL || st->queue == NULL) {
        _paused = paused;
        return;
    }
    if (paused) {
        AudioQueuePause(st->queue);
    } else {
        AudioQueueStart(st->queue, NULL);
    }
    _paused = paused;
}

- (BOOL)isPaused
{
    return _paused;
}

- (void)setVolume:(float)volume
{
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    _volume = volume;
    DGStreamState *st = DGStateOf(self);
    if (st != NULL && st->queue != NULL) {
        AudioQueueSetParameter(st->queue, kAudioQueueParam_Volume, volume);
    }
}

- (NSTimeInterval)elapsed
{
    if (!_started) {
        return 0.0;
    }
    return [NSDate timeIntervalSinceReferenceDate] - _startWallClock;
}

#pragma mark - Network thread

- (void)threadMain
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSURL *url = [NSURL URLWithString:_urlString];
    if (url == nil) {
        [self failWithMessage:@"Invalid stream URL."];
        [pool drain];
        return;
    }

    NSURLRequest *req = [NSURLRequest requestWithURL:url
                                        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                    timeoutInterval:20.0];
    _connection = [[NSURLConnection alloc] initWithRequest:req delegate:self startImmediately:NO];
    [_connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_connection start];

    while (!_stopped) {
        NSAutoreleasePool *loopPool = [[NSAutoreleasePool alloc] init];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
        [loopPool drain];
    }

    // Teardown on this thread.
    [_connection cancel];
    DGStreamState *st = DGStateOf(self);
    if (st->queue != NULL) {
        AudioQueueStop(st->queue, true);
        AudioQueueDispose(st->queue, true);   // also frees its buffers
        st->queue = NULL;
    }
    if (st->audioStream != NULL) {
        AudioFileStreamClose(st->audioStream);
        st->audioStream = NULL;
    }

    [pool drain];
}

#pragma mark - NSURLConnection delegate (network thread)

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    // Icecast responds 200 for a good stream; treat 4xx/5xx as failure.
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger code = [(NSHTTPURLResponse *)response statusCode];
        if (code >= 400) {
            [self failWithMessage:[NSString stringWithFormat:@"Stream returned HTTP %ld.", (long)code]];
        }
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if (_stopped) {
        return;
    }
    DGStreamState *st = DGStateOf(self);
    if (st->audioStream == NULL) {
        OSStatus err = AudioFileStreamOpen(self, DGPropertyListener, DGPacketsProc,
                                           kAudioFileMP3Type,
                                           &st->audioStream);
        if (err != noErr) {
            [self failWithMessage:@"Could not open the audio stream parser."];
            return;
        }
    }
    OSStatus err = AudioFileStreamParseBytes(st->audioStream,
                                             (UInt32)[data length], [data bytes], 0);
    if (err != noErr) {
        [self failWithMessage:@"Could not decode the audio stream."];
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self failWithMessage:[error localizedDescription]];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    // A live stream normally never finishes; if it does, report done.
    if (_delegate != nil && [_delegate respondsToSelector:@selector(audioStreamerDidFinish:)]) {
        [(NSObject *)_delegate performSelectorOnMainThread:@selector(audioStreamerDidFinish:)
                                                withObject:self waitUntilDone:NO];
    }
    _stopped = YES;
}

#pragma mark - Audio setup + packet handling

- (void)setupQueueFromStream
{
    DGStreamState *st = DGStateOf(self);
    if (st->queue != NULL) {
        return;
    }

    UInt32 size = sizeof(st->asbd);
    OSStatus err = AudioFileStreamGetProperty(st->audioStream,
                                              kAudioFileStreamProperty_DataFormat,
                                              &size, &st->asbd);
    if (err != noErr) {
        [self failWithMessage:@"Could not read the stream format."];
        return;
    }

    err = AudioQueueNewOutput(&st->asbd, DGBufferCallback, self,
                              NULL, NULL, 0, &st->queue);
    if (err != noErr) {
        [self failWithMessage:@"Could not create the audio queue."];
        return;
    }

    unsigned int i;
    for (i = 0; i < DG_NUM_BUFFERS; i++) {
        err = AudioQueueAllocateBuffer(st->queue, DG_BUFFER_SIZE, &st->buffers[i]);
        if (err != noErr) {
            [self failWithMessage:@"Could not allocate audio buffers."];
            return;
        }
        st->inuse[i] = NO;
    }

    AudioQueueSetParameter(st->queue, kAudioQueueParam_Volume, _volume);
}

- (void)handlePackets:(UInt32)numBytes count:(UInt32)numPackets
                 data:(const void *)data descs:(AudioStreamPacketDescription *)descs
{
    if (_stopped) {
        return;
    }
    DGStreamState *st = DGStateOf(self);
    if (st->queue == NULL) {
        return;   // not ready yet
    }

    UInt32 i;
    for (i = 0; i < numPackets; i++) {
        SInt64 packetOffset;
        UInt32 packetSize;
        if (descs != NULL) {
            packetOffset = descs[i].mStartOffset;
            packetSize = descs[i].mDataByteSize;
        } else {
            // CBR fallback: evenly sized packets.
            packetSize = numBytes / numPackets;
            packetOffset = (SInt64)i * packetSize;
        }

        if (packetSize > DG_BUFFER_SIZE) {
            continue;   // pathological packet; skip
        }

        // Flush the current buffer if this packet won't fit, or we're out of
        // packet-description slots.
        if (st->bytesFilled + packetSize > DG_BUFFER_SIZE ||
            st->packetsFilled >= DG_MAX_PACKET_DESCS) {
            [self enqueueCurrentBuffer];
            if (_stopped) {
                return;
            }
        }

        AudioQueueBufferRef buf = st->buffers[st->fillIndex];
        memcpy((char *)buf->mAudioData + st->bytesFilled,
               (const char *)data + packetOffset, packetSize);

        st->packetDescs[st->packetsFilled].mStartOffset = (SInt64)st->bytesFilled;
        st->packetDescs[st->packetsFilled].mDataByteSize = packetSize;
        st->packetDescs[st->packetsFilled].mVariableFramesInPacket =
            (descs != NULL) ? descs[i].mVariableFramesInPacket : 0;

        st->bytesFilled += packetSize;
        st->packetsFilled += 1;
    }
}

- (void)enqueueCurrentBuffer
{
    DGStreamState *st = DGStateOf(self);
    if (st->queue == NULL || st->packetsFilled == 0) {
        return;
    }

    AudioQueueBufferRef buf = st->buffers[st->fillIndex];
    buf->mAudioDataByteSize = (UInt32)st->bytesFilled;

    OSStatus err = AudioQueueEnqueueBuffer(st->queue, buf,
                                           (UInt32)st->packetsFilled, st->packetDescs);
    if (err != noErr) {
        [self failWithMessage:@"Could not enqueue audio."];
        return;
    }

    pthread_mutex_lock(&st->mutex);
    st->inuse[st->fillIndex] = YES;
    pthread_mutex_unlock(&st->mutex);

    st->enqueuedCount += 1;
    if (!st->queueStarted && st->enqueuedCount >= DG_START_THRESHOLD) {
        OSStatus serr = AudioQueueStart(st->queue, NULL);
        if (serr == noErr) {
            st->queueStarted = YES;
            [self notifyStarted];
        } else {
            [self failWithMessage:@"Could not start playback."];
            return;
        }
    }

    // Advance to the next buffer, waiting (on this network thread) if it is
    // still being played.
    st->fillIndex = (st->fillIndex + 1) % DG_NUM_BUFFERS;
    st->bytesFilled = 0;
    st->packetsFilled = 0;

    pthread_mutex_lock(&st->mutex);
    while (st->inuse[st->fillIndex] && !_stopped) {
        pthread_cond_wait(&st->cond, &st->mutex);
    }
    pthread_mutex_unlock(&st->mutex);
}

- (void)bufferDoneWithRef:(AudioQueueBufferRef)ref
{
    DGStreamState *st = DGStateOf(self);
    unsigned int i;
    pthread_mutex_lock(&st->mutex);
    for (i = 0; i < DG_NUM_BUFFERS; i++) {
        if (st->buffers[i] == ref) {
            st->inuse[i] = NO;
            break;
        }
    }
    pthread_cond_broadcast(&st->cond);
    pthread_mutex_unlock(&st->mutex);
}

#pragma mark - Delegate helpers (marshal to main thread)

- (void)notifyStarted
{
    if (_started) {
        return;
    }
    _started = YES;
    _startWallClock = [NSDate timeIntervalSinceReferenceDate];
    if (_delegate != nil && [_delegate respondsToSelector:@selector(audioStreamerDidStartPlaying:)]) {
        [(NSObject *)_delegate performSelectorOnMainThread:@selector(audioStreamerDidStartPlaying:)
                                                withObject:self waitUntilDone:NO];
    }
}

- (void)failWithMessage:(NSString *)msg
{
    if (_stopped) {
        return;
    }
    _stopped = YES;
    // Marshal to the main thread via a trampoline on self (carries the message).
    [self performSelectorOnMainThread:@selector(dg_reportFailure:)
                           withObject:msg waitUntilDone:NO];
}

// Trampoline so the message string reaches the delegate on the main thread.
- (void)dg_reportFailure:(NSString *)msg
{
    if (_delegate != nil && [_delegate respondsToSelector:@selector(audioStreamer:didFailWithMessage:)]) {
        [_delegate audioStreamer:self didFailWithMessage:msg];
    }
}

@end
