# NOTES — DeGelato

Scratchpad for unfinished ideas. Nothing here ships in Fio 1.

## Done
- **Audio (Fio 2):** `DGAudioStreamer` = AudioFileStream → AudioQueue against the
  Icecast MP3, URL discovered from `/spot/stream.pls` (`DGPLSParser`). `wake?play=1`
  was pulled forward into Play (device-idle handling) rather than waiting for a
  later fio. NSURLConnection on a dedicated NSThread; no GCD/blocks.

- **Transport (Fio 3):** commands (`play`/`pause`/`next`/`prev`/`seek?`/`volume?`)
  go over the same DGGopherClient path (one `_cmdClient`); each returns a fresh
  `/now` which we adopt (checking for an `error` key first). Seek slider scrubs
  live, issues `seek?` on mouse-up; a 1 Hz tick advances it between polls without
  fighting the drag (`_userSeeking`). Volume slider drives the API device volume.

## Deferred to later fios
- **Eventual consistency:** a command's returned `/now` can lag Spotify by
  ~1–2 s (verified: firing pause→play back-to-back, each reply showed the
  previous state). The UI adopts the reply optimistically; the 2 s poll
  reconciles. A monotonic-ts guard (like DeToca's DTSnapshotGuard) would stop a
  staler replica from rewinding the UI — worth adding if two pods ever disagree.
- **Cover art (Fio 4):** `/cover/<album_id>/<size>` — `album_id` already parsed.
- **Audio pause:** transport pause stops Spotify; the local stream keeps buffering
  silence. Could `AudioQueuePause` the streamer in sympathy, but the pipe is live
  radio — simplest to leave it and let Listen/Stop own the local side.
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
