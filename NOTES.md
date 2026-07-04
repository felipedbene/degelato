# NOTES — DeGelato

Scratchpad for unfinished ideas. Nothing here ships in Fio 1.

## Deferred to later fios
- **Audio (Fio 2):** CFReadStream → AudioFileStream → AudioQueue against
  `:8000/spotify.mp3`. The risk item; kept out of Fio 1 on purpose.
- **Transport (Fio 3):** wire the frozen commands (`play`/`pause`/`next`/`prev`/
  `volume?`/`seek?`) — each returns a fresh `/now` snapshot, so the client can
  reuse the same parse path.
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
