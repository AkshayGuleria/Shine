<p align="center">
  <img src="docs/logo.png" width="120" alt="Shine logo"/>
</p>

# Shine

macOS menu-bar utility that temporarily disables your keyboard and trackpad so you can wipe your laptop clean. Auto-restores on a timer. Hold Esc for 2 seconds to cancel early.

No Dock icon. Lives in the menu bar.

---

## Install

1. Go to [Releases](https://github.com/AkshayGuleria/Shine/releases) and download `Shine-vX.X.X.zip`
2. Unzip, then drag `Shine.app` to `/Applications`
3. **First launch only:** right-click `Shine.app` → **Open** → click **Open** in the dialog
   - Bypasses Gatekeeper's unsigned-app warning. Required once, never again.
4. The diamond icon appears in your menu bar

### Grant Accessibility Permission

On first use, macOS will prompt for Accessibility access:

1. Click the diamond icon → **Start cleaning**
2. macOS shows an Accessibility prompt — click **Open System Settings**
3. In **Privacy & Security → Accessibility**, toggle **Shine** on
4. Return to the menu bar — Shine detects the grant automatically and starts the session

### Uninstall

1. Click the diamond icon → **Quit Shine**
2. Delete `Shine.app` from `/Applications`
3. Optional: remove the Accessibility entry in **System Settings → Privacy & Security → Accessibility**

---

## Build from source

### Requirements

- macOS 13.0 Ventura or later
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```bash
git clone https://github.com/AkshayGuleria/Shine.git
cd Shine
xcodegen generate
open Shine.xcodeproj
```

Build and run in Xcode (`⌘R`). The app appears in your menu bar.

## Usage

1. Click the diamond icon in the menu bar
2. Choose a duration (15 / 30 / 60 / 90 / 120s) — default is 60s
3. Click **Start cleaning** — a 3-second countdown appears, then input locks
4. Wipe your screen
5. Input restores automatically when the timer expires

**Cancel early:** hold <kbd>Esc</kbd> for 2 seconds.  
**Emergency exit:** force-quit Shine via Activity Monitor — input restores within ~1 second.

## How it works

Shine installs a `CGEventTap` at `kCGHIDEventTap` level, which intercepts hardware input events before any other consumer. During the lock period all events are dropped except Esc (used for abort detection). A watchdog timer fires at `duration + 5s` and tears down the tap unconditionally — even if the main thread is hung. The tap is also auto-removed on process death.

**Distribution note:** Shine is distributed unsigned via GitHub Releases. Mac App Store distribution is not possible — the sandbox blocks system-wide HID event taps. On first launch, right-click → **Open** to bypass Gatekeeper.

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
