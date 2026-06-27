<p align="center">
  <img src="docs/logo.png" width="120" alt="Shine logo"/>
</p>

# Shine

macOS menu-bar utility that temporarily disables your keyboard and trackpad so you can wipe your laptop clean. Auto-restores on a timer. Hold Esc for 2 seconds to cancel early.

No Dock icon. Lives in the menu bar.

---

## Install

### Homebrew (recommended)

```bash
brew install --cask --no-quarantine AkshayGuleria/tap/shine
```

`--no-quarantine` skips the Gatekeeper "unidentified developer" prompt — required because Shine is ad-hoc signed, not notarized.

### Manual

1. Go to [Releases](https://github.com/AkshayGuleria/Shine/releases) and download `Shine-vX.X.X.zip`
2. Unzip, then drag `Shine.app` to `/Applications`
3. **First launch only:** right-click `Shine.app` → **Open** → click **Open** in the dialog
   - If macOS says **"app is damaged"**: run `xattr -dr com.apple.quarantine /Applications/Shine.app` in Terminal, then open normally
4. The diamond icon appears in your menu bar

### Grant Accessibility Permission

On first use, macOS will prompt for Accessibility access:

1. Click the diamond icon → **Start cleaning**
2. macOS shows an Accessibility prompt — click **Open System Settings**
3. In **Privacy & Security → Accessibility**, toggle **Shine** on
4. Return to the menu bar — Shine detects the grant automatically and starts the session

### Uninstall

```bash
brew uninstall --cask shine
```

Or manually: quit Shine, delete `/Applications/Shine.app`, and remove the Accessibility entry in **System Settings → Privacy & Security → Accessibility**.

---

## Build from source

### Requirements

- macOS 13.0 Ventura or later
- Xcode 15+

```bash
git clone https://github.com/AkshayGuleria/Shine.git
open Shine.xcodeproj
```

Build and run in Xcode (`⌘R`). The app appears in your menu bar.

## Usage

1. Click the diamond icon in the menu bar
2. Choose a duration (15 / 30 / 60 / 90 / 120s) — default is 60s
3. Click **Start cleaning** — a 3-second countdown appears, then input locks
4. Wipe your keyboard, trackpad and screen
5. Input restores automatically when the timer expires

**Cancel early:** hold <kbd>Esc</kbd> for 2 seconds.  
**Emergency exit:** force-quit Shine via Activity Monitor — input restores within ~1 second.

## How it works

Shine installs a `CGEventTap` at `kCGHIDEventTap` level, which intercepts hardware input events before any other consumer. During the lock period all events are dropped except Esc (used for abort detection). A watchdog timer fires at `duration + 5s` and tears down the tap unconditionally — even if the main thread is hung. The tap is also auto-removed on process death.

For architecture details — state machine, component breakdown, input blocking internals — see [`docs/technical-overview.md`](docs/technical-overview.md).

**Distribution note:** Shine is ad-hoc signed and distributed via a [Homebrew tap](https://github.com/AkshayGuleria/homebrew-tap). Mac App Store distribution is not possible — the sandbox blocks system-wide HID event taps. Install via `brew install --cask --no-quarantine AkshayGuleria/tap/shine`; the `--no-quarantine` flag skips the Gatekeeper prompt for ad-hoc signed apps.

## Build phases

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | CGEventTap proof of concept (`docs/poc/lock_poc.swift`) | ✅ Done |
| 2 | Xcode project scaffold + state machine | ✅ Done |
| 3 | Wire tap into app, watchdog, sleep observer | ✅ Done |
| 4 | Overlay window + countdown UI | ✅ Done |
| 5 | Abort gesture (Esc-hold) | ✅ Done |
| 6 | Permission UX (first-run flow, auto-detect grant) | ✅ Done |
| 7 | Polish (sound, launch at login, About window) | ✅ Done |
| 8 | GitHub Actions release workflow (unsigned zip) | ✅ Done |

## Project structure

```
Shine/
├── App.swift
├── AppCoordinator.swift        # state machine
├── State/LockState.swift
├── Input/
│   ├── InputBlocker.swift      # CGEventTap wrapper
│   └── AbortGuard.swift        # Esc-hold detection
├── Timing/TimerService.swift   # countdown + watchdog
├── UI/
│   ├── MenuBarView.swift
│   ├── OverlayWindow.swift
│   ├── OverlayView.swift
│   └── SettingsView.swift
└── Permissions/PermissionCoordinator.swift
```

## License

MIT
