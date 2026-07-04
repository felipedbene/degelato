# Investigation — command spam + state confusion

**Scope:** read-only. No `src/` edits. Deliverable = findings + fix plan (proposals only).
**Date:** 2026-07-04
**Subjects:** `src/DGNowPlayingWindowController.{h,m}`, `src/DGGopherClient.m` (working tree),
compared against `~/Projects/detoca` (Snow Leopard sibling) and gopher-spot server logs
(`kubectl -n gopher-spot`, two `gopher-server` replicas).

> **Note on the working tree.** The three files under investigation carry an
> uncommitted diff (`git diff`). Several of the mechanisms implicated below —
> catch-up polling, optimistic state, and *scheduling every stream and timer in
> `NSRunLoopCommonModes`* — were introduced by that diff, on top of the
> committed fio-3 baseline. In other words, the spam/confusion is largely a
> **regression from the uncommitted changes**, not the fio-3 code. The
> committed baseline scheduled timers in `NSDefaultRunLoopMode` and adopted the
> command's own reply. This matters for the fix plan.

---

## TL;DR — confirmed root causes, ranked

| # | Root cause | Status | Primary symptom |
|---|-----------|--------|-----------------|
| **R1** | "Last-press-wins" cancel cannot un-send: on LAN the selector is on the wire within ~1 run-loop turn, so every tap/commit **executes server-side** regardless of client cancel. | **Confirmed** (code + server logs) | command spam; double-skip |
| **R2** | Seek debounce timer runs in `NSRunLoopCommonModes` → **fires mid-drag** whenever the knob dwells ≥0.35 s. Each dwell emits a `/seek`, each of which (via R1) executes. | **Confirmed** (code; regression from working diff) | seek command spam |
| **R3** | **No snapshot-ts guard.** DeGelato has `snap.ts` but adopts every `/now` unconditionally. The catch-up poll storm fans rapid `/now` requests across **two replicas** (each ~1 s micro-cache) → a staler reply **rewinds** `_lastSnapshot`. DeToca guards this with `DTSnapshotGuard`; the port dropped it. | **Confirmed** (code + 2-pod deploy) | flip-flopping state; wrong track briefly |
| **R4** | **Three independent hold windows** (`_stateHoldUntilMs`, `_seekHoldUntilMs`, `_volumeHoldUntilMs`) expire at different times, so sub-regions of the UI adopt server truth at different instants. A `Next` after a scrub leaves the knob/time frozen on the *old* track while the track label changes. | **Confirmed** (code + timeline) | knob jumping; label/knob disagree |
| **R5** | Catch-up polls **cancel the in-flight `/now` and refetch** (bypassing the `_client != nil` guard), and every command **resets** the 2-poll bracket. Rapid commands ⇒ sustained elevated `/now` rate. | **Confirmed** (code) | `/now` request storm; amplifies R3 |
| **R6** | Volume slider is `continuous:NO`, so **no hold is set during a volume drag**; a poll `render` in common modes calls `setDoubleValue:` on the volume thumb **under the user's mouse** (10.5 event-tracking re-entrancy). Seek is protected (it sets its hold every move); volume is not. | **Confirmed** (code) | volume thumb jumps mid-drag |
| **R7** | **App-side CFStream connects silently fail to open.** After the first few transactions, each poll's `DGGopherClient` calls `CFStreamCreatePairWithSocketToHost`+`open` but the stream **never opens** (no socket is ever created), so the selector is never written and the client hangs the full **10 s** timeout. The `if (_client != nil) return;` guard blocks every 2 s poll for that whole 10 s, and stalls recur back-to-back → app sits at `offline — retrying` on a stale snapshot. Raw `nc` from the same box is 20/20 instant, so it's the app's CFStream usage, not the network. | **Confirmed live on the G5, instrumented** (see below) | "not even connecting" / app appears dead |

R1+R2 are the "fires commands like crazy." R3+R4+R5+R6 are the "UI gets confused."
R7 is a **separate, more severe** failure surfaced during live testing — the app stops
talking to the server entirely — but it is the same run-loop/lifecycle family and is
implicated by the same working-diff changes (catch-up polling, common-modes streams).

---

## H-by-H verdict against the ranked hypotheses

- **H1 (cancelled commands still execute) — CONFIRMED.** See R1 below and server-log evidence.
- **H2 (mid-drag seek commits) — CONFIRMED, and it is a regression** introduced by the
  working diff moving the debounce timer into `NSRunLoopCommonModes`. See R2.
- **H3 (catch-up storm × three hold windows) — CONFIRMED**, and it is *worse* than the
  hypothesis: the real amplifier is the **missing snapshot-ts guard** (R3) interacting
  with the two-replica deployment, not just the hold-window skew. See R3–R5 + the timeline.
- **H4 (10.5 event-tracking re-entrancy) — CONFIRMED but narrowed:** the seek slider is
  actually *protected* during a drag (its hold is refreshed on every `onSeek:`); the
  **volume** slider is the unguarded one. See R6.

---

## R1 — Cancel cannot un-send (step 2: client cancel semantics)

**Earliest moment the selector hits the wire.** In `DGGopherClient`:

- `-start` (`DGGopherClient.m:58`) creates the socket pair, schedules both streams in
  `NSRunLoopCommonModes`, opens them, and returns. No bytes are written yet.
- The write happens later, on the run loop, when the output stream signals
  `NSStreamEventHasSpaceAvailable` → `-writeRequestIfPossible` → `[_output write:…]`
  (`DGGopherClient.m:133` → `:174`). For a TCP socket, `HasSpaceAvailable` fires **as soon
  as the connection completes** (the send buffer is empty). To `10.0.100.112:70` on the LAN,
  connect + first writable event is **sub-millisecond to a few ms** — i.e. the *next*
  run-loop iteration. The selector line is tiny (`/spot/api/1/next\r\n`) so it flushes in
  one `write`.

**Earliest moment `-cancel` can run.** `-[DGNowPlayingWindowController sendCommand:]`
(`DGNowPlayingWindowController.m:223`) calls `[_cmdClient cancel]` on the *previous* client
before creating the new one. But `sendCommand:` only runs when a **new UI event is
serviced** — a button click or a debounce-timer fire — and each such event is its **own
run-loop turn**. Between two taps the run loop has already serviced the first client's
`HasSpaceAvailable` and written the bytes. So:

> For cancel to beat the write, two `sendCommand:` calls would have to occur **within a
> single run-loop turn with no servicing in between**. Discrete UI events never do this —
> each is a separate turn. Therefore cancel-before-write is **not realistic on LAN**.

Even in the theoretical tie: `-cancel` (`DGGopherClient.m:112`) only sets `_delegate = nil`
and tears down. Once `[_output write:]` has returned, the bytes are in the **kernel send
buffer** and will be delivered; and the working diff's `-closeOutput` (`:197`) already
drops the output stream right after writing. Closing our end (even RST) does not recall a
selector the server has already read. Gopher is a one-shot side-effecting GET completed in
~1 RTT.

**Net:** cancel stops *us listening*; it never stops the *server executing*. Every tap and
every seek commit that reaches `sendCommand:` runs on the device.

### Server-side ground truth (step 1)

The retained log buffer is short (only ~57 transport lines survive, and it happened to
contain **no `/seek`** in the window), so a purpose-built "one scrub + two Next" capture
was not available. It nonetheless contains the confirming signature — **identical commands
served in the same wall-clock second**, which is only possible if client-side cancel did
*not* prevent execution:

```
[03:35:22 …|50059…] /spot/api/1/search?q=chico
[03:35:22 …|53156…] /spot/api/1/search?q=chico     ← duplicate, same second, two connections
...
[02:40:52 …|2695 …] /spot/api/1/volume?30
[02:40:52 …|55119…] /spot/api/1/volume?100          ← two volume writes, same second
```

Each duplicate is a **distinct served connection** (different source port id in the log),
i.e. two full request/execute cycles, not one retried. This is exactly what R1 predicts:
the "cancelled" first request was already on the wire and executed. (The `search` surface
is a different window (fio-5), but it exercises the *same* `DGGopherClient` cancel path and
so is valid corroboration of the mechanism.)

Multi-tap `Next` in the logs (`03:23:09/19/27`, ~8–10 s apart) are deliberate spaced taps,
not spam — consistent with R1 saying the spam requires *rapid* repeats or mid-drag commits,
which the retained window didn't capture live.

---

## R2 — Seek debounce fires mid-drag (step, H2)

`_seekSlider` is `setContinuous:YES` (`DGNowPlayingWindowController.m:77`), so `onSeek:`
fires continuously during a drag. `onSeek:` (`:331`) schedules a **0.35 s non-repeating
debounce** for `commitSeek:` **in `NSRunLoopCommonModes`** (`:350–355`). `commitSeek:`
(`:358`) sends `/spot/api/1/seek?ms`.

`NSEventTrackingRunLoopMode` **is a member of** `NSRunLoopCommonModes`. During a slider
drag the run loop runs in event-tracking mode, so a common-modes timer **fires mid-drag**.
`onSeek:` invalidates+reschedules the timer on every continuous callback, so it does *not*
fire while the mouse is actively moving — but it **does** fire whenever the user **dwells
≥0.35 s** on a spot mid-scrub (hunting for a position). Each dwell ⇒ one `/seek` ⇒ (via R1)
one server execution ⇒ one fresh catch-up bracket (R5). A hesitant 3 s scrub thus emits
several seeks.

**This is a regression from the working diff.** The committed baseline used
`+scheduledTimerWithTimeInterval:` (default mode only). In default mode the debounce could
**not** fire during tracking; it fired ~0.35 s after the drag *ended* — i.e. exactly one
commit on release. The uncommitted switch to `timerWithTimeInterval:` +
`addTimer:forMode:NSRunLoopCommonModes` is what enabled mid-drag commits.

**Contrast — DeToca commits on mouse-up, never on a timer** (`DTPlayerWindowController.m:584`):

```objc
- (void)onSeek:(id)sender {
    NSEvent *e = [_panel currentEvent];
    if ([e type] == NSLeftMouseUp) { _scrubbing = NO; [_api seekTo:ms handler:…]; } // commit once
    else { _scrubbing = YES; [_elapsedLabel setStringValue:DTFormatMs(ms)]; }        // label only
}
```

DeToca has **no seek debounce timer at all**; a scrub of any length and any hesitation
produces **exactly one** `/seek`, on release.

---

## R3 — Missing snapshot-ts guard vs. two replicas (the real H3 amplifier)

`dgGopherClient:didFinishWithData:` adopts **every** poll snapshot unconditionally:

```objc
DGNowSnapshot *snap = [DGApiParser snapshotFromFields:fields];
[_lastSnapshot release]; _lastSnapshot = [snap retain];   // DGNowPlayingWindowController.m:493-494
```

There is **no ts comparison** — even though `DGNowSnapshot` carries `ts`
(`DGNowSnapshot.h:60`, parsed at `DGNowSnapshot.m:58`, and already used for position
interpolation). DeToca instead gates poll adoption through `DTSnapshotGuard`, a
monotonic-ts high-water mark:

```objc
// detoca/src/DTSnapshotGuard.m:10
- (BOOL)acceptTs:(long long)ts {
    if (ts <= 0) return YES;
    if (_lastTs > 0 && ts < _lastTs) return NO;   // regressed → drop stale replica
    _lastTs = ts; return YES;
}
```

`gopher-spot` runs **two `gopher-server` replicas** (`gopher-server-…-ll222`,
`gopher-server-…-sph9f`), each with an independent ~1 s micro-cache. Poll requests are
load-balanced across them, so replies can arrive **out of ts order**. DeToca rejects the
older one; **DeGelato adopts it and rewinds** — the track/state label snaps backward. This
is the mechanism behind "flip-flopping state" and "wrong track shown briefly," and it is
directly amplified by R5 (the catch-up storm issues extra `/now` requests, increasing the
odds and frequency of hitting the staler replica).

**The port dropped a guard it had the data to keep.** This is the single highest-leverage
divergence.

---

## R4 — Three hold windows expire independently

| Window | Set by | Guards | Duration |
|---|---|---|---|
| `_stateHoldUntilMs` | `onPlayPause:` (`:321`) | `effectiveState` (play/pause glyph + state label) | 2500 ms |
| `_seekHoldUntilMs` | `onSeek:`/`commitSeek:` (`:343`,`:369`) | `renderProgress` seek knob + time | 3000 ms |
| `_volumeHoldUntilMs` | `onVolume:` (`:381`) | volume reconcile block in `render` (`:643`) | 3000 ms |

They are set only when their own control is touched and expire at unrelated times. So a
single `render` triggered by a poll updates the **track/artist/album labels immediately**
(no hold), but honors whatever seek/volume/state holds happen to still be active — the UI
adopts server truth **piecewise**. The concrete failure is in the timeline below: after a
`Next`, the seek hold from a preceding scrub is still active, so the knob/time stay frozen
on the *old* track while the labels move to the new one, then jump when the hold expires.

DeToca has **zero** time-based hold windows. It uses **one** boolean `_scrubbing` (seek
drag only) plus the ts-guard. Reconciliation is otherwise immediate and coherent.

---

## R5 — Catch-up poll storm

`sendCommand:` arms `_catchUpsLeft = 2` and a catch-up timer at 1.2 s
(`DGNowPlayingWindowController.m:241-249`). `catchUpPoll:` (`:252`) **cancels the in-flight
`_client`** and refetches, then re-arms for the second bracket:

```objc
[_client cancel]; [_client release]; _client = nil;   // force a fresh /now, bypassing…
[self refresh:nil];                                    // …refresh:'s `if (_client != nil) return` guard
```

Two problems compound:
1. **Every command resets the bracket** (`_catchUpsLeft = 2`, invalidate+re-arm). Rapid
   commands keep restarting a 2-poll chain → a sustained burst of `/now` on top of the
   regular 2 s poll.
2. Catch-up **cancels and reopens** the poll socket, so the effective `/now` rate briefly
   doubles/triples, feeding R3 more chances to hit the stale replica.
3. `_catchUpTimer`/`_catchUpsLeft` are a **single shared slot**: a `Next` mid-way through a
   seek's bracket stomps the seek's pending catch-up. Not a crash, but the bracketing is
   non-deterministic under interleaved commands.

DeToca schedules **no** catch-up polls: each command reply *is* an authoritative snapshot
(applied, `guarded:NO`), and a single fixed 2 s poll handles the rest.

---

## R6 — Volume thumb fight during tracking (the real H4)

All streams and all timers are in `NSRunLoopCommonModes` (working diff), so poll replies →
`render` can run **inside a slider's mouse-tracking loop**. Auditing every slider mutation:

- **Seek** — `renderProgress` mutates `_seekSlider` (`:665`,`:675`) but returns early while
  `now < _seekHoldUntilMs` (`:659`). Because `onSeek:` refreshes that hold on **every**
  continuous callback, the hold is always ~3 s in the future *during* an active drag ⇒ the
  seek knob is **protected**. Good.
- **Volume** — `render` mutates `_volumeSlider` (`:646`) guarded only by
  `now >= _volumeHoldUntilMs` (`:643`). But `_volumeSlider` is **`continuous:NO`** (`:95`),
  so `onVolume:` — the *only* place `_volumeHoldUntilMs` is set — **doesn't fire until
  mouse-up**. Therefore **during** a volume drag the hold is not set, the guard passes, and
  a poll reply mid-drag calls `[_volumeSlider setDoubleValue:<server volume>]` **under the
  user's mouse**, yanking the thumb back to the old value on 10.5. This is the volume-knob
  jump. (Seek escapes this only because it is continuous and self-refreshes its hold.)

Keyboard auto-repeat on the seek slider is **not** a spam source: each arrow repeat calls
`onSeek:` which reschedules the same debounce, so keyboard adjustment still commits once
after the key is released (R2's debounce coalesces it correctly). The risk is mouse-dwell,
not keyboard.

**Why the modes were changed at all:** the diff moved everything to common modes so a
`/now` poll begun *before* a drag would not stall (and time out as "offline") while the
drag held the run loop in event-tracking mode. That is a real problem — but the blanket
fix reintroduced mid-drag callbacks (R2, R6). DeToca sidesteps both: gopher runs on a
background dispatch queue and delivers completions via `dispatch_async(main)`, which is
**naturally deferred past** event-tracking — no explicit mode juggling, no mid-drag
callbacks. DeGelato's `DGGopherClient` is run-loop-based, so it has to choose.

---

## R7 — The in-flight `_client` pointer wedges (live-confirmed; app stops connecting)

Surfaced while setting up the live repro on the G5 (`macg5`, 10.5.9, PPC, the running
`DeGelato.app` built Jul 3 22:37 from the current buggy source). Symptom the owner reported:
*"it's not even connecting."* Screenshots show real data (`state playing`/`stopped`,
`device idle`) under a persistent red **`offline — retrying`**.

**Live evidence gathered (all read-only):**

1. **Raw TCP works, repeatedly.** From the same G5:
   `printf '/spot/api/1/now\r\n' | nc 10.0.100.112 70` returns a valid `/now` every time
   (`state stopped, device active`, `ts …`). Network + server + both replicas are healthy.
2. **The app served exactly ONE request, then nothing.** Server logs (both pods, UTC,
   clock-aligned with the G5 — verified: a probe at `16:09:26Z` logged as `16:09:26Z`):
   one `/spot/api/1/now` at `16:11:23Z` on launch, then **zero** for 45+ minutes —
   including across an explicit **Refresh** click at `~16:56Z` (log window empty).
3. **The app holds no sockets and isn't trying.** `lsof -nP -iTCP -p <pid>` → `NONE-INET`;
   `netstat` shows no connection to `10.0.100.112`. Checked repeatedly, including right
   after Refresh — never a single SYN_SENT/ESTABLISHED to `:70`.
4. **The main thread is a healthy idle run loop, not hung.** `sample <pid>`:
   `-[NSApplication run] → nextEventMatchingMask → mach_msg_trap` (parked waiting for
   events; a few frames of normal `_handleWindowNeedsDisplay`). Accessibility queries
   answer instantly. So the run loop *is* running — timers/streams would be serviced if
   any existed.

**Instrumented root cause (definitive).** Per the owner's go-ahead ("instrument only, no
fix"), `DG-PROBE` `NSLog`s were added at every `_client` assign/clear and across the
`DGGopherClient` transaction lifecycle (`START`/`WROTE`/`EOF`/`FINISH`/`FAIL`/`TIMEOUT`/
`CANCEL`), rebuilt on the G5, and relaunched. The trace (pid 641) shows the exact mechanism:

```
pollTick _client=0x0 → refresh created 0x3e7bb30 → client START 0x3e7bb30 sel=/now
   ‹ no WROTE, no EOF — the CFStream never opens ›
pollTick _client=0x3e7bb30 → refresh GUARD-HIT (skipping)        × 5, over the next 10 s
client TIMEOUT 0x3e7bb30  wrote=0                                ← selector never written
client FAIL … "Timed out talking to 10.0.100.112:70"
didFail _client=0x3e7bb30 -> nil
pollTick _client=0x0 → refresh created 0x3e7c020 → START → ‹hangs again›
```

So it is **not** a permanent pointer wedge (my first hypothesis, from static reading, was
wrong): `_client` *does* get cleared — by the 10 s timeout — and polling resumes. The real
fault is one layer down:

1. **The CFStream connect silently fails to open.** A stalled client calls
   `CFStreamCreatePairWithSocketToHost` + `[_input open]`/`[_output open]`, but **no socket
   is ever created** — `lsof -nP -iTCP -p 641` reports `NONE-INET` *during* an active stall
   (not even a `SYN_SENT`). On 10.5 the pair is lazy: if the stream's run-loop source never
   activates, the socket is never opened, so there is no `OpenCompleted`, no
   `HasSpaceAvailable` (hence `wrote=0`), no data, nothing — just silence until the timer.
2. **The 10 s timeout + single-flight guard turn each stalled connect into 10 s of total
   offline.** `DG_TIMEOUT_SECONDS = 10` is enormous for a LAN connect, and while `_client`
   is non-nil the `if (_client != nil) return;` guard no-ops every 2 s poll (`GUARD-HIT`×5).
   Stalls recur back-to-back, so the app is offline ~continuously.

**It is app-specific, not the network.** A burst of **20 rapid `nc` connects from the same
G5 succeeded 20/20, instantly.** Raw BSD sockets are fine; only the app's CFStream path
stalls. And it degrades *after the first few transactions* (the launch poll + ~3 more wrote
and finished cleanly, then every subsequent connect stalled) — pointing at CFNetwork state
that goes bad after a handful of `DGGopherClient` transactions, **not** at the first
connect.

**Most likely code cause (for the deferred fix pass — not proven here).** The committed
fio-3..6 code polled cleanly (the `03:34–03:40Z` session ran ~6 min steady on data-carrying
polls). The working diff changed the stream machinery in two ways that are the prime
suspects for "CFStream stops opening after a few pairs":
- **`-closeOutput` closes *one half* of a shared-socket CFStream pair mid-transaction**
  (`removeFromRunLoop:` + `close` on `_output` only, right after writing, while `_input`
  keeps the same underlying socket). Partial teardown of a shared CFSocket, repeated, is a
  plausible way to corrupt CFNetwork's socket/run-loop-source state after a few rounds.
- **`NSRunLoopCommonModes` scheduling** of the streams (vs the committed `NSDefaultRunLoopMode`).
Pinning which one (or their interaction, possibly aggravated by concurrent CFNetwork
activity from the audio/PLS path the owner exercised this session) needs an A/B code
experiment — which belongs to the fix pass, not this instrument-only pass.

**This is the app's current blocking state** and must be fixed *before* the R1–R6 work —
none of the command-spam behavior is even reachable while the app can't stay connected. The
`DG-PROBE` NSLogs are still in the working tree (tagged `// DG-PROBE`, grep-removable);
they add no behavior change and can be stripped or kept for the fix pass.

---

## Fio 8 Step 1 — A/B/C isolation results (measured on the G5)

Metric = `FINISH / START` from the `DG-PROBE` log, per-pid, soaked on the G5.
Baseline stall signature: `TIMEOUT wrote=0` (connect opened no socket, selector
never written).

| Arm | Single variable changed | START | FINISH | stalls | success | soak |
|-----|-------------------------|:-----:|:------:|:------:|:-------:|------|
| **Baseline** | committed CFStream client | 176 | 4 | 161 | **2%** | 32 min |
| **Arm A** | do not `-closeOutput` mid-transaction | 23 | 10 | 12 | **45%** | 3 min |
| **Arm B** | schedule streams in `NSDefaultRunLoopMode` | 26 | 14 | 11 | **56%** | 3 min |
| **Arm C** | BSD socket, `getaddrinfo(AI_NUMERICHOST)` + `connect()`, **no CFStream/CFHost** | 88 | 87 | **0** | **~100%** | 3 min |

**Conclusion: Arm C is the cause-killer.** `FAIL=0, TIMEOUT=0`; 88 attempts in
175 s is a clean 2 s poll cadence with zero throttling. Arms A and B each only
*halved* the stalls because neither touches the connect — the fault is in
CFStream's **CFHost/mDNS resolution+connect machinery** (a numeric literal still
routes through CFHost on 10.5 and stalls when mDNSResponder is degraded), which
is exactly what Arm C bypasses. This confirms the R7 resolver-stall hypothesis
and matches the `nc` control (libc `getaddrinfo` on a numeric literal → 20/20).

**Fix adopted (fio 8):** the BSD-socket client (Arm C) becomes the production
`DGGopherClient` — one dedicated worker thread per transaction, results
marshalled to the main thread via `-performSelectorOnMainThread:` (the sanctioned
step-3 fallback; pure message-passing, no shared mutable state beyond the `_done`
completion guard). Plus the Step-2 palliative: the controller's single-flight
poll guard becomes cancel-and-replace (idempotent read; a slow poll can no longer
freeze the cadence), and the transaction deadline drops from 10 s toward the LAN.

---

## Step 4 — Reconstructed timeline

**Scenario:** user scrubs the seek bar for ~3 s (with one mid-scrub dwell), releases, then
taps **Next** twice within 1 s. `t=0` = scrub start. Track on device = **K**.

| t (s) | User / timer | Client action | Server effect | UI state (what's on screen) |
|------|--------------|---------------|---------------|------------------------------|
| 0.0–3.0 | scrubbing (mouse moving) | `onSeek:` ×N: sets `_seekHoldUntilMs = t+3000`, reschedules 0.35 s debounce (common modes) | — | knob follows finger; time label live; `renderProgress` early-returns (seek held) |
| ~1.5 | dwell ≥0.35 s mid-scrub | debounce **fires mid-drag** → `commitSeek:` → `/seek?ms₁` (client S1) + arms catch-up (2) | **seek #1 executes** (R1,R2) | — |
| 2.0 | poll timer (common modes) fires **during drag** | new `/now` (S1's catch-up also cancels/refetches ~2.7 s) | — | reply adopted → `render`; seek held ⇒ knob untouched (protected, R6) |
| 3.0 | **mouse-up** | final `onSeek:` sets `_seekHoldUntilMs≈6.0 s`; reschedules debounce | — | tracking ends |
| 3.35 | debounce fires | `commitSeek:` → `/seek?ms₂` (S2), cancels S1 (already executed), arms catch-up, hold≈6.35 s | **seek #2 executes** | — |
| 3.50 | **tap Next #1** | `sendCommand(/next)` cancels S2 (already executed); client N1; **resets** catch-up bracket; **no hold set** | **/next #1 executes** → track **K→K+1** | nothing yet (eventual consistency ~1–2 s) |
| 3.90 | **tap Next #2** | `sendCommand(/next)` cancels N1 (already executed); client N2; resets bracket again | **/next #2 executes** → track **K+1→K+2** | — |
| ~4.0 | regular poll reply | adopt `/now` (server still settling ⇒ may report **K** or **K+1**) | — | **track label = K/K+1**, but knob+time **frozen at old-track-K scrub position** (seek held to 6.35) → *label/knob disagree* ⚠ |
| ~5.1 | catch-up poll (bracket) | cancels in-flight `/now`, refetch; **load-balanced to stale replica** | — | **no ts guard** ⇒ adopts older snapshot ⇒ **track label rewinds K+1→K** → *flip-flop* ⚠ |
| 4–6 | 1 Hz `clockTick:` | `renderProgress` each second | — | time readout **frozen** at scrub value while labels move → *wrong track w/ stale time* ⚠ |
| ~6.3 | catch-up poll #2 | refetch (server now settled) | — | track label → **K+2** |
| 6.35 | `_seekHoldUntilMs` expires | next `renderProgress` reconciles | — | knob **jumps** from frozen old-K scrub pos → K+2's live position ⚠ |

Four visibly self-contradicting moments (⚠): label-vs-knob disagreement, a full track-label
rewind (flip-flop), a frozen time under a changing track, and a knob jump on hold expiry.
Net server truth: **two** `/next` executed (track advanced by 2) plus **two** `/seek` — the
"last-press-wins" illusion hid none of them.

---

## Proposed fix plan (fio-8+) — proposals only, no code this pass

Commits use `fio-N`; the last is fio-7, so fixes begin at **fio-8**. Ordered by
leverage-to-risk. **fio-8 (R7) must come first — the app cannot poll at all until it lands.**

- **fio-8 — Fix the stalling CFStream connect (fixes R7; unblocks everything).**
  Root-caused live (see R7): the CFStream pair intermittently never opens (no socket ever
  created), so the client hangs the full 10 s and the single-flight guard freezes polling.
  Three-part fix, in order:
  1. **Stop the amplification immediately (cheap, high value):** cut the connect timeout way
     down (a LAN connect that hasn't produced `HasSpaceAvailable`/`OpenCompleted` in ~1–2 s
     is dead — the current `DG_TIMEOUT_SECONDS = 10` is the difference between a 1 s blip and
     a 10 s outage), and don't let one in-flight poll no-op the next (replace
     `if (_client != nil) return;` with cancel-and-replace, so a stalled connect can't block
     the 2 s cadence).
  2. **Find the CFStream root cause via A/B:** rebuild with the working-diff stream changes
     reverted one at a time — (a) drop `-closeOutput` (let `-teardown` close both halves of
     the shared-socket pair together at EOF), (b) schedule streams in `NSDefaultRunLoopMode`
     instead of `NSRunLoopCommonModes` — and watch the `DG-PROBE` `WROTE`/`TIMEOUT wrote=0`
     ratio to see which restores reliable opens. The pre-diff code polled for minutes, so
     one of these is the regression.
  3. If CFStream can't be made reliable on 10.5, **switch the gopher client to a plain BSD
     socket** (connect/write/read) on a worker thread — closer to DeToca's `GopherRequest`
     — which the 20/20 `nc` test proves works flawlessly from this box.
  *Highest priority: no other fix is observable until the app can stay connected.*

- **fio-9 — Restore snapshot-ts monotonicity (fixes R3; kills the flip-flop).**
  Port DeToca's `DTSnapshotGuard` as `DGSnapshotGuard` (or inline a `_lastAdoptedTs`
  high-water mark). Gate poll adoption in `dgGopherClient:didFinishWithData:` on
  non-regressing `snap.ts`; reset on reconnect. DeGelato already parses `ts`, so this is
  small and high-impact. *Lowest risk, highest payoff — do first.*

- **fio-10 — Commit seek on mouse-up, not on a mid-drag timer (fixes R2).**
  Adopt DeToca's model: `continuous:YES` for a live label, but branch on
  `[[self window] currentEvent].type == NSLeftMouseUp` and send `/seek` **once** on release;
  drop the 0.35 s debounce timer entirely (or, minimal variant, move only that timer back to
  `NSDefaultRunLoopMode` so it can't fire during tracking). Removes seek command spam.

- **fio-11 — Protect the volume slider during tracking (fixes R6).**
  Give volume the same protection seek has: set a `_scrubbing`/`_volumeTracking` flag (or a
  hold) at the **start** of interaction, not just on release — e.g. a `continuous:YES`
  volume slider that sets `_volumeHoldUntilMs` on every callback but only *sends* on mouse-up
  (mirrors the seek fix). Prevents the mid-drag thumb yank.

- **fio-12 — Retire the catch-up storm and collapse the hold windows (fixes R4, R5; and
  reduces spam pressure on R3, and removes the R7 failure surface).**
  Move toward DeToca's model: adopt the **command's own reply** as authoritative (it *is* a
  `/now`), remove the 2-poll catch-up bracket and the in-flight-poll cancellation, and let
  the single 2 s poll + ts-guard reconcile. Replace the three time-based holds with one
  `_scrubbing` boolean + the ts-guard. If the optimistic play/pause feel is worth keeping,
  keep only `_stateHoldUntilMs` and let the ts-guard prevent rewinds. *Largest behavioral
  change — do last, after fio-8 has removed the rewind risk.*

- **fio-13 (optional) — Transport double-fire policy.**
  Decide explicitly what rapid taps should mean now that R1 is understood: either accept
  "every tap executes" (DeToca's honest model — then delete the misleading cancel in
  `sendCommand:`), or add a genuine source-side coalesce (minimum inter-command interval /
  disable-until-reply) so a fumbled double-tap on `Next` doesn't skip two tracks. This is a
  product decision, not a bug fix; flag for the owner.

### Non-goals / watch-items for the fix pass
- Keeping `DGGopherClient` streams in common modes is *fine for the poll-stall reason* — the
  damage is timers (fio-9) and unguarded slider writes (fio-10), not the streams themselves.
  Don't blindly revert the whole modes change or the "offline during drag" bug returns.
- Preserve the working diff's genuinely-correct pieces: `-closeOutput` after write and the
  "ignore output-stream errors" guard in `DGGopherClient` are unrelated to this bug and
  should stay.
