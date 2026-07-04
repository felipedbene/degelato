# Parity Audit — DeToca × DeGelato (fio 14)

**Goal:** bring DeGelato (Sorbet Leopard 10.5.9 / ppc32, the radinho-only port,
fios 1–13) to **full feature parity** with DeToca (Snow Leopard 10.6 / i386, a
general RFC 1436 Gopher client *and* the Spotify-over-gopher radinho). Per
Felipe: the gopher-browser side is **in scope** — this is total parity, not just
the radinho.

Sources: `~/Projects/detoca/src` (6,773 lines, ~92 OCUnit tests) vs
`~/Projects/degelato/src` (radinho-only). Both are Makefile-only, programmatic
UI, non-ARC/MRR. DeGelato's differentiators from a naïve port already landed in
fios 8–13 (BSD-socket client, ts-guard, debouncer, unified hold) — those are at
or ahead of DeToca and are **not** re-done here.

---

## 1. Already at parity — do NOT redo

These exist in DeGelato and match (or exceed) DeToca:

| Capability | DeGelato | Notes |
|---|---|---|
| Gopher transaction client | `DGGopherClient` (BSD socket, worker thread) | DeToca `GopherRequest` is also BSD sockets; DeGelato's is arguably ahead (R7 fix) |
| `/now` model + parser | `DGNowSnapshot` / `DGApiParser` | mirrors `DTNowSnapshot` |
| Snapshot ts-guard | `DGSnapshotGuard` | ported fio 9; matches `DTSnapshotGuard` |
| PLS parsing | `DGPLSParser` | matches `PLSParser` |
| List-item parser (search/queue) | `DGTrackItem` | matches `DTTrackItem` |
| Live Icecast audio | `DGAudioStreamer` | faithful port of `DTAudioStreamer` |
| Transport + seek/volume reconciliation | debouncer + unified hold + scrubbing-equivalent | fios 10–12; ahead of DeToca's `_scrubbing` |
| Device wake (bare + `wake?play=1`) | Controls ▸ Wake + Listen flow | matches `DTSpotAPI wake:`/`wakeAndPlay:` |
| Now-playing poll + interpolation + optimistic play/pause | `DGNowPlayingWindowController` | matches |
| Cover **fetch** (single album, 300px) | `updateCoverForSnapshot:` | fetch parity; **cache** is not (see gap C) |

---

## 2. Parity gaps — the matrix

Ranked into clusters. `size` = DeToca implementation lines (a proxy for effort);
`trap` = the 10.5 retrocoding hazard to watch (see §3).

### A. Preferences & persistence — **foundational, do first**
| Gap | DeToca | DeGelato today | trap |
|---|---|---|---|
| Configurable host/port (no hardcode) | `DTServerPrefs` (NSUserDefaults `DTSpotHost/Port`, validation, defaults) | `DG_HOST`/`DG_PORT` **`#define`d, duplicated in 4 files** | — |
| Preferences window (⌘,) + Test Connection | `PreferencesController` (live validation, latency test, reconnect on change) | none | — |
| Document-font preference | `DTFontManager` defaults | fixed Cascadia→Monaco fallback | — |
**Size:** ~476 lines. **Why first:** every window's hardcoded host collapses into one prefs model; the gopher browser needs an editable location anyway.

### B. Unified list window: playlists + search + queue with thumbnails
| Gap | DeToca | DeGelato today | trap |
|---|---|---|---|
| **Playlist browse + context play** | `DTPlaylistWindowController` Playlists mode, `DTPlaylistItem`, `playContextURI:offset:` | **absent** (no playlist window; play is single-track uri only) | — |
| 64px thumbnail rows | `DTTrackCell` (thumb + 2-line) | text-only tables | needs cache C |
| Live "up next" queue | Fila mode, refreshed off the `/now` poll via notification | manual Refresh only, separate window | — |
| 3-mode single window | `NSSegmentedControl` Busca/Fila/Playlists | 2 separate windows (Search, Queue) | — |
**Size:** ~ (playlist window + cell) within the 977-line UI/model cluster. **Decision:** unify into one 3-mode window (DeToca model) vs. keep DeGelato's separate windows and just add Playlists + thumbnails. Recommend unifying — it's the DeToca reference and less surface area long-term.

### C. Cover cache (multi-entry + disk) → enables thumbnails
| Gap | DeToca | DeGelato today | trap |
|---|---|---|---|
| Two-level immutable cover cache | `DTCoverCache` (`NSCache` + disk `~/Library/Caches/…/covers/`) | **single in-memory entry** keyed by current album | **NSCache is 10.6+; injected fetcher is a block** |
**Size:** part of the 977 cluster. **Port:** `NSMutableDictionary` + on-disk store (NOTES already plans this); replace the block fetcher with a delegate/target-action.

### D. Media keys + global transport shortcuts
| Gap | DeToca | DeGelato today | trap |
|---|---|---|---|
| Hardware ⏮⏯⏭ capture | `DTMediaKeyTap` (CGEventTap on a dedicated thread, consumes event) + `DTMediaKeyRouter` (pure decode/policy, ignores auto-repeat) | none | **CGEventTap on 10.5 needs "Enable access for assistive devices"** (already ON on the G5); `NX_SYSDEFINED` decode is the same |
| Playback menu global shortcuts | ⌘⌥P / ⌘⌥← / ⌘⌥→, Space-when-key | in-window buttons only | — |
**Size:** ~234 lines. Router is pure → fully testable (DeToca has 8 router tests).

### E. General gopher browser — **the "small" cluster (944 lines)**
| Gap | DeToca | DeGelato today | trap |
|---|---|---|---|
| Menu browsing (table view) | `GopherWindowController` (302), `GopherMenuView` (199), `GopherTableView` (25) | absent | informal table data source (already DeGelato's idiom) |
| Menu parse + item types 0/1/7/i/h/s/3 | `GopherMenuParser` (93), `GopherItem` (88) | absent | pure — trivially testable |
| Resource / `gopher://` URL parsing | `GopherResource` (133) | absent | pure |
| Cascaded nav, Open Location (⌘L), Home (⌘⇧H), launch-arg | `GopherWindowController` + `AppDelegate` | absent | — |
| Bookmarks | `BookmarkStore` (104, gophermap file under App Support) + Add ⌘D / Show | absent | — |
**Size:** 944 lines, ~60% pure parsers/models (testable). This is the bulk of "make DeGelato a real gopher client."

### F. ANSI / type-0 text rendering (401 lines)
| Gap | DeToca | DeGelato today | trap |
|---|---|---|---|
| Type-0 doc viewer (non-wrapping) | `GopherWindowController` text mode | absent | — |
| ANSI SGR → attributed string | `ANSIParser` (226), `ANSIPalette` (67, xterm-256 + truecolor), `ANSISpan` (23), `AttributedStringRenderer` (85) | absent | RGB-triple model avoids NSColor; braille alignment needs the bundled Cascadia (already bundled); keep the fbterm "case 38" fix |
**Size:** 401 lines, almost all pure (DeToca has a large ANSI test block incl. `testCase38DoesNotSwallowFollowingParams`).

### G. Gopher extras
| Gap | DeToca | DeGelato today | trap |
|---|---|---|---|
| Type-7 search prompt | `DTInputSheet` (NSAlert + field) | absent | **completion is a block → use delegate/target-action** |
| Type-s `[SND]` → open radinho | `GopherItem` + player | absent (radinho is standalone) | — |
| Type-h / `URL:` handling, MP3-file queue | `StreamRouting` + `PlayQueue` + old `StreamPlayerController` | absent | QTKit finite-file path is 10.6 QTKit; **skip/defer** — DeGelato's radinho is live-stream only |
| Export Menu as Playlist (M3U) | `AppDelegate` File menu | absent | — |
**Size:** input sheet + routing/queue models are small; the QTKit MP3-file player is the one piece worth **explicitly deferring** (live radio only).

### H. Theme (cosmetic, optional)
| Gap | DeToca | DeGelato today | trap |
|---|---|---|---|
| Dark/amber CRT skin | `DTTheme` (palette + control factories) | default AppKit look | — |
**Recommendation:** defer or make it the last polish fio. DeGelato's plain look is fine functionally.

### I. Test breadth & docs
DeToca ~92 tests vs DeGelato 53. New pure code (prefs, media-key router, gopher/ANSI parsers, resource) should ship with tests to match DeToca's coverage.

---

## 3. 10.5 retrocoding traps (the CFStream/mDNS genre)

Every one of these has a proven DeGelato escape hatch already in the tree:

| DeToca uses (10.6) | 10.5 replacement | Precedent in DeGelato |
|---|---|---|
| **blocks** (cover-cache fetcher, `DTInputSheet` completion) | delegate / target-action | all of DeGelato is block-free |
| **GCD / `DTDispatch`** | `NSThread` + run-loop / `performSelectorOnMainThread:` | `DGGopherClient`, `DGAudioStreamer` |
| **`NSCache`** (cover cache) | `NSMutableDictionary` + manual disk store | — (new, but trivial) |
| **`CTFontManagerRegisterFontsForURL`** | `ATSApplicationFontsPath` in Info.plist | `DGFontManager` already does this |
| **CGEventTap media keys** | same API, but requires *assistive devices* enabled | already ON on the G5 |
| **formal table-view protocols** | informal (unlisted) methods | `DGSearch`/`DGQueue` already do this |

None is a blocker; all are the same class of surprise as R7, and all are already solved somewhere in DeGelato.

---

## 4. Housekeeping (fold into the first parity fio)

- **`DGGopherClient.h` carries dead ivars** — `_input/_output/_buffer/_request/_reqOffset` and the old NSStream/CFStream header comment survive from before the fio-8 BSD rewrite; the `.m` no longer uses them. Prune.
- **`NOTES.md` "Deferred" section predates fios 9–13** — it lists the ts-guard, unified hold, and BSD client as *future* work that has since shipped. Reconcile.

---

## 5. Proposed fio sequence (continues DeGelato's numbering; fio 14 = this audit)

Ordered so each fio unblocks the next; every fio is one commit, plan-before-code,
tests where the code is pure, built+run on the G5.

| fio | Deliverable | Cluster | Rough size |
|---|---|---|---|
| **14** | **This parity audit** | — | done |
| **15** | Preferences + persistence: `DGServerPrefs` (NSUserDefaults), Preferences window (⌘,), Test Connection, kill the 4× hardcoded host; + housekeeping (§4) | A | ~M |
| **16** | Cover cache: `DGCoverCache` (dict + disk, no NSCache/blocks) | C | ~S–M |
| **17** | Playlists + unified list window (Busca/Fila/Playlists) with 64px `DGTrackCell` thumbnails; context play | B | ~L |
| **18** | Queue live "up next" (refresh off the `/now` poll via notification) | B | ~S |
| **19** | Media keys (`DGMediaKeyTap` + `DGMediaKeyRouter`, assistive-access) + Playback menu global shortcuts | D | ~M |
| **20** | Gopher browser core: resource/menu parse + item types, menu table window, Open Location / Home / cascaded nav / launch-arg | E | ~L |
| **21** | Gopher text + ANSI rendering (parser/palette/span/renderer, non-wrapping type-0 viewer, braille) | F | ~M |
| **22** | Gopher extras: bookmarks (Add ⌘D / Show), type-7 search (input sheet, no blocks), type-s → radinho, Export as Playlist | E/G | ~M |
| **23** | Test + docs parity: close the OCUnit gap on the new pure code; refresh NOTES/README | I | ~M |
| **24** | *(optional)* `DGTheme` dark/amber CRT skin | H | ~S |
| **25** | **Release: build the DMG on the G5, `gh release create` with the `.dmg`** so people download & run; version bump | — | ~S |

**Explicitly deferred / out:** the QTKit finite-MP3-file queue player (§G) — DeGelato's radinho is live-stream only; the old `StreamPlayerController`/QTKit path isn't worth porting. Flag if you disagree.

**Capstone (fio 25) = the downloadable binary** you asked for: `make dmg` already
produces `DeGelato-1.0.dmg`; the fio wires it to a GitHub Release on
`felipedbene/degelato` (built on the real G5, ppc, so it actually runs on the
target hardware).

---

## 6. Open decisions for Felipe

1. **List window shape (fio 17):** unify search+queue+playlists into one 3-mode
   window (DeToca model) — or keep the two existing windows and bolt Playlists +
   thumbnails on? (Recommend: unify.)
2. **Theme (fio 24):** port `DTTheme`, or leave DeGelato's native look?
3. **QTKit MP3-file player:** confirm we skip it (live radio only)?
4. **Scope trims:** ~11 fios is a big campaign. Any cluster you want to drop or
   reorder before I start fio 15?
