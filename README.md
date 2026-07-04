# DeGelato

A native Cocoa Spotify remote — *the essential Radinho* — for **Sorbet Leopard
10.5.x on a Power Mac G5** (ppc, 32-bit). It is the PowerPC sibling of
[DeToca](https://github.com/felipedbene/detoca) (Snow Leopard 10.6.8) and speaks
the frozen **gopher-spot machine API `/spot/api/1`** over raw gopher (RFC 1436),
LAN-only.

**Fio 1** delivers the app skeleton: the gopher socket client, the `/now`
parser, and a text-only now-playing window. There is no audio yet — that is
Fio 2, deliberately isolated because it is the risk item.

## What it does (Fio 1)

- Polls `/spot/api/1/now` every 2 s over a run-loop-scheduled `NSStream`.
- Shows track / artist / album / playback state / position–duration / volume /
  device in **Cascadia Code**, in a single programmatic window (no NIB).
- On a network hiccup it shows `offline — retrying`, keeps the last snapshot on
  screen, and recovers silently when the server answers again.

## Requirements

- **Build host: the G5 itself.** Sorbet Leopard 10.5.x, Xcode 3.1.4, GCC 4.2.
- Power Mac G5 — **ppc 32-bit only** (`MACOSX_DEPLOYMENT_TARGET = 10.5`, SDK 10.5).
- No ARC, no blocks, no GCD: this is 10.5. Sockets use `NSStream` scheduled on
  `NSRunLoop`; the parser/model are pure Foundation.

## Building

```sh
make            # build DeGelato.app  (ppc, SDK 10.5, -Wall, zero warnings)
make run        # build and launch
make test       # build + run the OCUnit (SenTestingKit) suite, fully offline
make clean
```

Defaults live at the top of the `Makefile` (`SDK`, `ARCH=ppc`, `CC=gcc`);
override on the command line if your SDK is elsewhere.

### Clock workaround (Xcode 3 on modern date)

The Xcode 3 code-signing/cert path chokes on today's date, the same disease as
DeToca's 10.6 box. **CLI builds via `make` do not sign anything, so a plain
`make` usually needs no workaround.** If Xcode.app itself or a signing step
complains, set the clock back before launching it and leave NTP off:

```sh
sudo systemsetup -setusingnetworktime off
sudo date 0601000009       # mmddHHMMyy → ~June 2009; adjust to taste
```

Never re-enable NTP from a build script.

## Network contract (v1, frozen)

- Server: `10.0.100.112:70` (LAN only, plain TCP, no TLS).
- Write `selector\r\n`, read to EOF. `/now` returns UTF-8 `key<TAB>value` lines
  (CRLF, bare LF tolerated). See `gopher-spot/API.md` for the exact keys.
- **The client ignores unknown keys and tolerates missing ones** — the API is
  additive; surface growth must never hard-fail the client.
- The server micro-caches `/now` (~1 s); we poll at 2 s and never faster.

Capture a fresh fixture from the live server:

```sh
printf '/spot/api/1/now\r\n' | nc 10.0.100.112 70 > Tests/Fixtures/now_live.txt
```

## Layout

```
src/
  DGGopherClient.{h,m}            run-loop NSStream gopher transaction
  DGNowSnapshot.{h,m}            immutable parsed /now snapshot (model)
  DGApiParser.{h,m}             raw text -> fields -> snapshot (pure)
  DGFontManager.{h,m}           resolve Cascadia Code (registered via Info.plist)
  DGNowPlayingWindowController.{h,m}   the window + 2 s poll loop
  AppDelegate.{h,m}, main.m     programmatic app + menu bar
tests/
  DGApiParserTests.m            parser/model edge cases + on-disk fixtures
  DGGopherClientTests.m         client state machine vs a localhost loopback
Tests/Fixtures/                 now_live + empty/garbage/truncated/unknown/accents
Resources/
  Fonts/CascadiaCode-Regular.ttf   bundled font (ATSApplicationFontsPath = Fonts)
  DeGelato.icns, OFL.txt
```

## Acceptance (Fio 1)

- `make` builds ppc/Release-equivalent with **zero warnings** on the G5.
- `make test` is green — parser edge cases and the client state machine.
- Launches on Sorbet 10.5 and shows live now-playing within ~3 s.

## Not in Fio 1

Audio (Fio 2), transport controls (Fio 3), cover art (Fio 4), search + wake
(Fio 5), queue (Fio 6), polish/DMG (Fio 7). No prefs, no TLS, nothing off-LAN.
