# NOTES — DeGelato

Scratchpad for unfinished ideas. Nothing here ships in Fio 1.

## Permanent design constraints (fios 8–13 fix campaign)

These are load-bearing. Full write-up in `design/INVESTIGATION-command-spam.md`.

- **Cancel ≠ un-send (R1).** On the LAN the selector is on the wire within one
  run-loop turn, so gopher-spot executes *every* command that touches the wire;
  `-cancel` only stops us listening. No mechanism may assume a sent command can
  be revoked. Rapid transport taps are therefore debounced BEFORE the wire
  (`DGDebouncer`, Prev/Next): three fast Next taps skip one track, not three.
  Idempotent `/now` polls are exempt — cancel-and-replace on a poll is fine.

- **The ts-guard is mandatory — never remove it (R3).** gopher-spot runs two
  load-balanced replicas, each micro-caching `/now` ~1 s, so consecutive polls
  can return `ts` out of order. That is *expected* infrastructure behavior, not
  a bug. `DGSnapshotGuard` drops any snapshot whose `ts` regressed; without it
  the UI flip-flops (track rewinds, seek knob jumps). It resets on reconnect so
  a backend clock-reset can't lock adoption out forever.

- **The gopher client uses BSD sockets + the libc resolver on a worker thread,
  BY DESIGN (R7).** CFStream via `CFStreamCreatePairWithSocketToHost` routed even
  a numeric-literal host through CFHost/mDNSResponder, which hangs on this
  network (documented flaky mDNS on Apple devices) — the connect opened no socket
  at all and timed out. fio 8's A/B/C isolation proved it: BSD socket went from
  ~2 % to ~100 % success. **Do not migrate back to CFStream-by-hostname.** All
  client results are marshalled to the main thread; zero shared mutable state
  (the PPC 970's weak memory model must never become relevant).

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

## Shipped since (fios 8–15) — reconciling the deferrals below
- **Eventual-consistency / staler-replica rewind → DONE (fio 9).** The monotonic
  ts-guard shipped as `DGSnapshotGuard`; two pods *do* disagree and it is now
  mandatory (see the design-constraints section above).
- **BSD-socket client, unified hold, transport debounce, cancel-and-replace polls →
  DONE (fios 8/10/12).** The "Deferred" notes below predate this; where they
  describe those as future work, treat the design-constraints section + the
  investigation doc as authoritative.
- **Configurable server address → DONE (fio 15).** `DGServerPrefs` +
  Preferences window (⌘,) replaced the hardcoded `DG_HOST`/`DG_PORT`.

## Deferred to later fios (parity campaign, fios 16+)
- **Cover disk cache → fio 16 (next).** Today a single in-memory entry keyed by
  `album_id`. Port DeToca's `DTCoverCache` as a plain `NSMutableDictionary` +
  on-disk store (NO NSCache — 10.6+; NO block fetcher — use a delegate). Unblocks
  the 64px thumbnails.
- **Queue thumbnails / live "up next" → fios 17–18.** Text-only + manual Refresh
  today; the unified 3-mode list window and a poll-driven queue refresh land there.
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
