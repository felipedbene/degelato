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

## Known trade-offs (from the fio-4 code review)
- **onPlayPause vs stale state:** the play/pause choice reads `_lastSnapshot`,
  which can be ~2 s stale (eventual consistency). If playback state changed on
  another device within the poll window, the first press may send the no-op
  command; the next poll corrects it. Optimistic toggling would need a "pending
  intent" flag — deferred; low impact.
- **Local output gain:** `DG_STREAM_VOLUME` is 1.0 on purpose — loudness is the
  API device volume (what the Icecast pipe encodes), matching DeToca. If a stream
  ever clips locally, expose the AudioQueue gain as a second, local-only slider.
- **Slider reconciliation:** seek + volume sliders use a 3 s "hold" after a user
  change so the stale command reply can't snap them back; the seek slider commits
  via a 0.35 s debounce (input-agnostic — works for keyboard, no mouse-up sniff).

## Done (fio 5)
- **Search:** `/spot/api/1/search?q=<urlencoded>` in a separate window; query
  percent-escaped via CFURLCreateStringByAddingPercentEscapes (UTF-8). Results are
  DGTrackItem rows (shared with a future /queue). Play a result on double-click
  via the **human** `/spot/play?uri=<track uri>` selector — the machine API has no
  play-by-uri; the reply is a discarded gophermap.
- **Wake:** Controls ▸ Wake Device fires bare `/spot/api/1/wake`.
- NSTableView data-source/delegate are informal on 10.5 (formal protocols 10.6+) —
  implemented, not declared, same lesson as NSStreamDelegate.

## Done (fio 6)
- **Queue:** DGQueueWindowController lists `/spot/api/1/queue` (DGTrackItem reused
  verbatim — same item.<i>.* shape). Add-to-queue from search results via
  `/spot/api/1/queue/add?<uri>` (returns /queue; there is no queue/clear in v1).
  The queue window doesn't auto-refresh after an add elsewhere — press Refresh
  (cross-window notification wasn't worth it for one action).

## Deferred to later fios
- **Queue thumbnails / live refresh:** the queue table is text-only and refreshes
  on open / Refresh. Cover thumbnails per row need the deferred multi-entry cover
  cache; a periodic poll could keep "up next" live as tracks advance.
- **Eventual consistency:** a command's returned `/now` can lag Spotify by
  ~1–2 s (verified: firing pause→play back-to-back, each reply showed the
  previous state). The UI adopts the reply optimistically; the 2 s poll
  reconciles. A monotonic-ts guard (like DeToca's DTSnapshotGuard) would stop a
  staler replica from rewinding the UI — worth adding if two pods ever disagree.
- **Cover disk cache:** Fio 4 keeps only a single in-memory entry (the current
  album's NSImage), keyed by `album_id`, refetched on album change. DeToca's
  DTCoverCache (two-level, disk-backed, block-based, NSCache) is deferred — NSCache
  is 10.6+ and we don't yet need many thumbnails. Add a plain NSMutableDictionary
  + on-disk store when the playlist window (many 64px thumbs) lands.
- **Audio pause:** transport pause stops Spotify; the local stream keeps buffering
  silence. Could `AudioQueuePause` the streamer in sympathy, but the pipe is live
  radio — simplest to leave it and let Listen/Stop own the local side.
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
