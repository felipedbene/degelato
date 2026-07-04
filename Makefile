# Makefile — DeGelato
#
# Source of truth for building on the target: Sorbet Leopard 10.5.9, Xcode 3.1.4,
# GCC 4.2, Power Mac G5 (ppc, 32-bit). Programmatic UI, no XIB/NIB, no Xcode
# project. 10.5 has no ARC, no blocks, no GCD — so nothing here uses -fblocks.
#
#   make            build DeGelato.app
#   make run        build and launch DeGelato.app
#   make test       build and run the OCUnit (SenTestingKit) tests
#   make clean      remove build products
#
# Override on the command line if needed, e.g.:
#   make SDK=/Developer/SDKs/MacOSX10.5.sdk ARCH=ppc

SDK      ?= /Developer/SDKs/MacOSX10.5.sdk
ARCH     ?= ppc
CC       ?= gcc
MINVER    = -mmacosx-version-min=10.5

# SenTestingKit lives under /Developer on the Xcode 3 toolchain (not /System).
DEVFRAMEWORKS = /Developer/Library/Frameworks

# No -fblocks: blocks do not exist on 10.5 / GCC 4.2. Fragile-ABI safety comes
# from explicit ivars + @synthesize in the sources, not from a flag.
COMMON = -arch $(ARCH) -isysroot $(SDK) $(MINVER) -Wall -Isrc

APP        = DeGelato.app
APP_BINARY = $(APP)/Contents/MacOS/DeGelato
FONT       = Resources/Fonts/CascadiaCode-Regular.ttf
LICENSE    = Resources/OFL.txt
CREDITS    = Resources/Credits.rtf
ICON       = Resources/DeGelato.icns
DMG        = DeGelato-1.0.dmg

# --- Source groups -----------------------------------------------------------

# Pure Foundation, no AppKit and no gopher. Unit-tested.
MODEL_SRC = \
	src/DGNowSnapshot.m \
	src/DGApiParser.m \
	src/DGPLSParser.m \
	src/DGTrackItem.m \
	src/DGSnapshotGuard.m \
	src/DGDebouncer.m \
	src/DGServerPrefs.m \
	src/DGCoverCache.m \
	src/DGPlaylistItem.m \
	src/DGMediaKeyRouter.m

# Networking: run-loop-scheduled NSStream (Foundation + CoreFoundation). Tested
# against a localhost loopback server.
NET_SRC = \
	src/DGGopherClient.m

# Audio: live Icecast MP3 via AudioFileStream + AudioQueue (AudioToolbox). fio 2.
AUDIO_SRC = \
	src/DGAudioStreamer.m

# AppKit UI. Programmatic window + menu bar.
UI_SRC = \
	src/DGFontManager.m \
	src/DGNowPlayingWindowController.m \
	src/DGTrackCell.m \
	src/DGLibraryWindowController.m \
	src/DGMediaKeyTap.m \
	src/DGPreferencesController.m \
	src/AppDelegate.m \
	src/main.m

APP_SRC  = $(MODEL_SRC) $(NET_SRC) $(AUDIO_SRC) $(UI_SRC)
APP_LIBS = -framework Cocoa -framework CoreFoundation -framework AudioToolbox -framework ApplicationServices

# --- Default target ----------------------------------------------------------

all: $(APP)

# --- Application bundle -------------------------------------------------------

$(APP): $(APP_SRC) Info.plist $(FONT) $(ICON) $(CREDITS)
	@echo "  Assembling $(APP)"
	@mkdir -p $(APP)/Contents/MacOS
	@mkdir -p $(APP)/Contents/Resources/Fonts
	$(CC) $(COMMON) $(APP_SRC) $(APP_LIBS) -o $(APP_BINARY)
	@cp Info.plist $(APP)/Contents/Info.plist
	@printf 'APPLGelo' > $(APP)/Contents/PkgInfo
	@cp $(FONT) $(APP)/Contents/Resources/Fonts/
	@cp $(ICON) $(APP)/Contents/Resources/
	@cp $(CREDITS) $(APP)/Contents/Resources/
	@if [ -f $(LICENSE) ]; then cp $(LICENSE) $(APP)/Contents/Resources/; fi
	@touch $(APP)                       # nudge Finder's icon cache
	@echo "  Built $(APP)"

run: $(APP)
	open $(APP)

# --- Distributable disk image -----------------------------------------------

dmg: $(APP)
	@echo "  Packaging $(DMG)"
	@rm -rf dmg-stage "$(DMG)"
	@mkdir -p dmg-stage
	@cp -R $(APP) dmg-stage/
	@ln -s /Applications dmg-stage/Applications
	@cp README.md dmg-stage/README.txt
	hdiutil create -volname "DeGelato" -srcfolder dmg-stage \
		-ov -format UDZO "$(DMG)"
	@rm -rf dmg-stage
	@echo "  Built $(DMG)"

# --- OCUnit tests ------------------------------------------------------------

TEST_BUNDLE = Tests.octest
TEST_SRC = $(MODEL_SRC) $(NET_SRC) \
           tests/DGApiParserTests.m \
           tests/DGGopherClientTests.m \
           tests/DGPLSParserTests.m \
           tests/DGTrackItemTests.m \
           tests/DGSnapshotGuardTests.m \
           tests/DGDebouncerTests.m \
           tests/DGTimelineTests.m \
           tests/DGServerPrefsTests.m \
           tests/DGCoverCacheTests.m \
           tests/DGPlaylistItemTests.m \
           tests/DGMediaKeyRouterTests.m

test: $(TEST_SRC) tests/Tests-Info.plist
	@echo "  Building $(TEST_BUNDLE)"
	@mkdir -p $(TEST_BUNDLE)/Contents/MacOS
	$(CC) $(COMMON) -bundle \
		-F$(DEVFRAMEWORKS) \
		-framework Foundation -framework CoreFoundation -framework SenTestingKit \
		$(TEST_SRC) -o $(TEST_BUNDLE)/Contents/MacOS/Tests
	@cp tests/Tests-Info.plist $(TEST_BUNDLE)/Contents/Info.plist
	@echo "  Running otest ($(ARCH))"
	OBJC_DISABLE_GC=YES DYLD_FRAMEWORK_PATH=$(DEVFRAMEWORKS) \
		DG_FIXTURES=$(CURDIR)/Tests/Fixtures \
		arch -arch $(ARCH) /Developer/Tools/otest $(TEST_BUNDLE)

# --- Housekeeping ------------------------------------------------------------

clean:
	rm -rf $(APP) $(TEST_BUNDLE) dmg-stage $(DMG)

.PHONY: all run test dmg clean
