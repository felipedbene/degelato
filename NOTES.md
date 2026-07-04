# NOTES — DeGelato

Scratchpad for unfinished ideas. Nothing here ships in Fio 1.

## Done
- **Audio (Fio 2):** `DGAudioStreamer` = AudioFileStream → AudioQueue against the
  Icecast MP3, URL discovered from `/spot/stream.pls` (`DGPLSParser`). `wake?play=1`
  was pulled forward into Play (device-idle handling) rather than waiting for a
  later fio. NSURLConnection on a dedicated NSThread; no GCD/blocks.

## Deferred to later fios
- **Transport (Fio 3):** wire the frozen commands (`play`/`pause`/`next`/`prev`/
  `volume?`/`seek?`) — each returns a fresh `/now` snapshot, so the client can
  reuse the same parse path. API `volume?` + a local volume slider live here too.
- **Pause vs stop:** Play currently starts/stops the stream outright. A true
  pause (`AudioQueuePause`, already in DGAudioStreamer) can wire to the transport
  pause in Fio 3.
- **Cover art (Fio 4):** `/cover/<album_id>/<size>` — `album_id` is already
  parsed into the snapshot, unused for now.
- **Wake (Fio 5):** when `device == idle`, offer a wake action; the window
  already renders "idle (playing elsewhere)".

## Fio 1 design notes
- **Progress interpolation** is implemented in the model
  (`interpolatedPositionMsAtEpochMs:`) and used for the time readout, but there
  is no sub-poll 1 Hz UI tick yet — the position only advances on each 2 s poll.
  A cheap `NSTimer` re-render could smooth it later without a network hit.
- **DGGopherClient vs DeToca's GopherRequest:** DeToca uses a blocking BSD
  socket on a libdispatch queue. That is impossible on 10.5, so DeGelato uses a
  run-loop `NSStream` pair (`CFStreamCreatePairWithSocketToHost`) instead. Same
  contract, different machinery.
- **Font:** registered by the OS via `ATSApplicationFontsPath` (Info.plist),
  not by code — `CTFontManagerRegisterFontsForURL` is 10.6+.
