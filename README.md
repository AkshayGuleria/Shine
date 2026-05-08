<p align="center">
  <img src="docs/logo.png" width="120" alt="Shine logo"/>
</p>

# Shine

macOS menu-bar utility that temporarily disables your keyboard and trackpad so you can wipe your laptop clean. Auto-restores on a timer. Hold Esc for 2 seconds to cancel early.

No Dock icon. Lives in the menu bar.

---

## Requirements

- macOS 13.0 Ventura or later
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```bash
git clone https://github.com/akshayguleria/Shine.git
cd Shine
xcodegen generate
open Shine.xcodeproj
```

Build and run in Xcode (`⌘R`). The app appears in your menu bar.

## First run

On first use, macOS will ask for **Accessibility** permission. This is required for `CGEventTap` to intercept keyboard and trackpad events system-wide — the same permission that apps like Karabiner-Elements and Rectangle use.

Grant it in **System Settings → Privacy & Security → Accessibility**, then click "Start cleaning" again.

## Usage

1. Click the ✦ icon in the menu bar
2. Choose a duration (15 / 30 / 60 / 90 / 120s) — default is 60s
3. Click **Start cleaning** — a 3-second countdown appears, then input locks
4. Wipe your screen
5. Input restores automatically when the timer expires

**Cancel early:** hold <kbd>Esc</kbd> for 2 seconds.  
**Emergency exit:** force-quit Shine via Activity Monitor — input restores within ~1 second.

## How it works

Shine installs a `CGEventTap` at `kCGHIDEventTap` level, which intercepts hardware input events before any other consumer. During the lock period all events are dropped except Esc (used for abort detection). A watchdog timer fires at `duration + 5s` and tears down the tap unconditionally — even if the main thread is hung. The tap is also auto-removed on process death.

**Distribution note:** Shine is distributed as a Developer ID–signed and notarized app. Mac App Store distribution is not possible — the sandbox blocks system-wide HID event taps.

## Build phases

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | CGEventTap proof of concept (`docs/poc/lock_poc.swift`) | ✅ Done |
| 2 | Xcode project scaffold + state machine | ✅ Done |
| 3 | Wire tap into app, watchdog, sleep observer | 🔲 Next |
| 4 | Overlay window + countdown UI | 🔲 Pending |
| 5 | Abort gesture (Esc-hold) | 🔲 Pending |
| 6 | Permission UX (first-run flow) | 🔲 Pending |
| 7 | Polish (sound, launch at login, icon) | 🔲 Pending |
| 8 | Sign + notarize | 🔲 Pending |

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
