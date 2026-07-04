//
//  DGAudioStreamer.h
//  DeGelato — fio 2
//
//  Plays an endless HTTP MP3 stream (Icecast/SHOUTcast) with CoreAudio:
//  AudioFileStream parses the incoming bytes into packets and an AudioQueue
//  renders them. This is what QTKit cannot do — QTMovie only handles finite /
//  progressive files, not live radio. The gopher-spot audio stream is Icecast
//  2.4.4 serving 128 kbps CBR MP3.
//
//  Networking + parsing run on a dedicated NSThread; delegate callbacks are
//  delivered on the main thread. AudioToolbox is available on 10.5, so this is
//  ppc/G5-friendly. No GCD, no blocks — a pthread mutex/cond gates the buffer
//  ring so the parser blocks (on its own thread, never the main thread) when
//  every AudioQueue buffer is still playing.
//

#import <Foundation/Foundation.h>

@class DGAudioStreamer;

@protocol DGAudioStreamerDelegate <NSObject>
@optional
- (void)audioStreamerDidStartPlaying:(DGAudioStreamer *)streamer;
- (void)audioStreamer:(DGAudioStreamer *)streamer didFailWithMessage:(NSString *)message;
- (void)audioStreamerDidFinish:(DGAudioStreamer *)streamer;
@end

@interface DGAudioStreamer : NSObject {
    NSString *_urlString;
    id <DGAudioStreamerDelegate> _delegate;   // not retained

    NSThread        *_thread;
    NSURLConnection *_connection;

    void            *_opaque;   // holds the CoreAudio state (see .m)

    float            _volume;
    BOOL             _paused;
    BOOL             _stopped;
    BOOL             _started;
    NSTimeInterval   _startWallClock;
}

@property (nonatomic, assign) id <DGAudioStreamerDelegate> delegate;

- (id)initWithURLString:(NSString *)urlString;

- (void)start;
- (void)stop;               // stops playback and releases everything
- (void)setPaused:(BOOL)paused;
- (BOOL)isPaused;
- (void)setVolume:(float)volume;   // 0.0 .. 1.0

// Seconds since playback actually began (live streams don't have a position).
- (NSTimeInterval)elapsed;

@end
