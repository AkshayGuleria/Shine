# Shine — Technical Overview

Shine is a macOS menu-bar utility that temporarily blocks keyboard and trackpad input so you can clean your screen without accidental keystrokes. It runs as a background-only app (no Dock icon) and requires Accessibility permission to intercept hardware-level input events.

---

## Architecture

Shine is a SwiftUI + AppKit hybrid with a single central coordinator that owns the state machine.

```
ShineApp (@main)
└── AppCoordinator                  ← owns state machine, drives everything
    ├── PermissionCoordinator       ← AX permission check / prompt
    ├── InputBlocker                ← CGEventTap (hardware event interception)
    │   └── AbortGuard              ← 2-second Esc-hold detector
    ├── TimerService                ← main ticker + watchdog timer
    └── OverlayWindowController     ← multi-screen fullscreen overlay
```

**`AppCoordinator`** (`AppCoordinator.swift`) is an `@Observable` class. All state transitions go through it. UI components observe it reactively.

---

## State Machine

Five states defined in `State/LockState.swift`:

```swift
enum LockState {
    case idle                              // ready, menu bar visible
    case awaitingPermission                // polling every 1s for AX grant
    case arming(remaining: Int)            // 3-second countdown before lock
    case locked(remaining: TimeInterval)   // input blocked
    case unlocking                         // cleanup, tap being torn down
}
```

**Normal flow:**

```
idle → awaitingPermission? → arming(3) → arming(2) → arming(1) → locked → unlocking → idle
```

**Abort paths:**
- Esc held 2 seconds while `locked` → `unlocking` → `idle`
- System sleep notification → immediate `unlocking` → `idle`

---

## Input Blocking — `InputBlocker`

**File:** `Input/InputBlocker.swift`

Core mechanism is a `CGEventTap` placed at `kCGHIDEventTap` (below the app layer, above the hardware driver). This intercepts all HID input before any app sees it.

### Setup

```swift
CGEvent.tapCreate(
    tap: .kCGHIDEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,   // keyboard + mouse + scroll + tablet
    callback: eventTapCallback,
    userInfo: retainedSelf
)
```

The callback receives a raw `UnsafeMutableRawPointer` for `userInfo` (unsafe retain on self, released in `uninstall()`). It returns:

- `nil` → event blocked
- `Unmanaged.passUnretained(event)` → event passes through

The tap source is added to the main `CFRunLoop`. Cleanup is registered via `atexit_b` to disable the tap if the process exits abnormally.

### Errors

| Error | Cause |
|---|---|
| `BlockerError.notAuthorized` | `AXIsProcessTrusted()` returned false |
| `BlockerError.tapCreateFailed` | Secure input active, tap limit hit, or TCC lag |

### Teardown order (main thread only)

1. `CGEvent.tapEnable(tap:, enable: false)`
2. `CFRunLoopRemoveSource`
3. Release retained self pointer
4. Invalidate tap

---

## Abort Guard — `AbortGuard`

**File:** `Input/AbortGuard.swift`

Monitors keyCode `53` (Esc) while locked. Called from inside the CGEventTap callback for every event.

- **keyDown** → schedule `DispatchWorkItem` to fire after 2 seconds
- **keyUp** → cancel pending work item
- If 2 seconds elapse without keyUp → call `abortHandler` → `AppCoordinator.enterUnlocking()`

Esc events always pass through (never blocked) so the user can always abort.

---

## Timer Service — `TimerService`

**File:** `Timing/TimerService.swift`

Two independent timers run simultaneously during `locked` state:

### Main Ticker (main thread)

- `DispatchSourceTimer` on `.main`, fires every 50ms (10ms leeway)
- Calls `onTick(remaining)` → updates overlay countdown UI
- Calls `onExpiry()` when `remaining <= 0` → normal unlock

### Watchdog (background thread)

- `DispatchSourceTimer` on `.global(qos: .userInteractive)`, fires at `duration + 5s`
- Runs on background thread — fires even if main thread is hung
- Calls `onWatchdogFire()` → calls `InputBlocker.disableTap()` directly
- Last-resort guarantee: input is never blocked permanently

All callbacks are captured at `start()` and nilled in `cancel()` to prevent stale invocations.

---

## Arming Sequence

`AppCoordinator` runs a 1-second repeating timer for 3 ticks before engaging the tap:

```
arming(3) → arming(2) → arming(1) → install InputBlocker → transition to locked
```

The overlay shows a fullscreen countdown. If the user aborts mid-arming, the work item is cancelled and the timer is invalidated before `InputBlocker.install()` is ever called.

---

## Permissions — `PermissionCoordinator`

**File:** `Permissions/PermissionCoordinator.swift`

CGEventTap at `kCGHIDEventTap` requires Accessibility. No other entitlements needed. The app is **not sandboxed** — sandbox blocks system-wide HID taps.

### Flow on "Start" tap

1. `AXIsProcessTrusted()` → if `true`, proceed directly to arming
2. If `false`, call `AXIsProcessTrusted(options: [kAXTrustedCheckOptionPrompt: true])` to show system dialog
3. If still false → enter `awaitingPermission`, poll every 1s
4. On grant detected → enter arming

### 30-second timeout

If permission is not granted within 30 seconds, `AppCoordinator` shows a dialog offering to relaunch:

```swift
// spawns: sleep 1; open "<bundle path>"
// then: NSApp.terminate(nil)
```

Relaunch is required because `AXIsProcessTrusted()` caches the old `false` result for the current process lifetime.

---

## Overlay — `OverlayWindowController` + `OverlayView`

**Files:** `UI/OverlayWindow.swift`, `UI/OverlayView.swift`

### Window properties

| Property | Value |
|---|---|
| Style | `.borderless` |
| Level | `.screenSaver` (above everything except cursor) |
| Opacity | Transparent window, 85% black SwiftUI background |
| Spaces | `.canJoinAllSpaces` — visible on all desktops |
| Mouse | `ignoresMouseEvents = false` — clicks absorbed |

One window per connected display. Created in `show(state:)`, updated in-place via `update(state:)`, torn down with a 0.3s fade in `dismiss(completion:)` (deferred one run loop to avoid SwiftUI autorelease crashes).

### OverlayView states

**Arming:**
```
"Get ready…"
[large animated countdown: 3 → 2 → 1]
```

**Locked:**
```
✦  (sparkles symbol)
[timer: M:SS or Ss format, 96pt monospaced]
Hold Esc key for 2 seconds to cancel
```

Numeric transitions animate with `.numericText` content transition.

---

## Menu Bar UI — `MenuBarView`

**File:** `UI/MenuBarView.swift`

SwiftUI `MenuBarExtra` (diamond icon). Menu items change based on `LockState`:

| State | Shown |
|---|---|
| `idle` | Start button (with duration), duration picker, settings, about, quit |
| `awaitingPermission` | "Waiting…" message, "I've Approved It — Restart Shine" button, Cancel |
| `arming`, `locked`, `unlocking` | Start button disabled |

Duration options: 15, 30, 60, 90, 120 seconds. Stored in `UserDefaults` as `defaultDuration`.

---

## Settings — `SettingsView`

**File:** `UI/SettingsView.swift`

360×260 pt preferences window with two sections:

- **Lock:** default duration slider (15–120s, 15s steps), "Play sound on completion" toggle
- **System:** "Launch at login" toggle (`SMAppService.mainApp`), button to open Accessibility Settings

---

## System Integration

### Sleep handling

`AppCoordinator.init()` registers for `NSWorkspace.willSleepNotification`. On sleep, any active lock is immediately torn down — the CGEventTap cannot survive a sleep/wake cycle safely.

### Launch at login

`SMAppService.mainApp.register()` / `.unregister()` — uses the modern service management API (macOS 13+).

### No Dock icon

`Info.plist` sets `LSUIElement = YES`. The app is menu-bar-only.

---

## Project Structure

```
Shine/
├── App.swift                       # @main, AppDelegate, scene definitions
├── AppCoordinator.swift            # State machine, timer orchestration
├── Input/
│   ├── InputBlocker.swift          # CGEventTap
│   └── AbortGuard.swift            # Esc-hold detection
├── Permissions/
│   └── PermissionCoordinator.swift
├── State/
│   └── LockState.swift
├── Timing/
│   └── TimerService.swift          # Ticker + watchdog
└── UI/
    ├── MenuBarView.swift
    ├── OverlayWindow.swift
    ├── OverlayView.swift
    ├── SettingsView.swift
    └── AboutView.swift
```

---

## Distribution

### Current (ad-hoc / unsigned)

GitHub Actions builds and releases an ad-hoc-signed zip. Users must right-click → **Open** once to bypass Gatekeeper. No Apple Developer account needed for this path.

### Future (Developer ID + notarization)

To ship a fully notarized build that passes Gatekeeper silently:

1. Obtain Apple Developer Program membership ($99/yr)
2. Install a Developer ID Application certificate in Keychain
3. Set build settings: `ENABLE_HARDENED_RUNTIME = YES`, code sign with Developer ID
4. Archive and export via Xcode (Product → Archive → Distribute)
5. Run `scripts/notarize.sh Shine.app` — zips, submits to Apple, staples the ticket
6. Verify: `spctl --assess --verbose Shine.app`
7. Distribute as `.zip` or `.dmg`

See `scripts/notarize.sh` for full prerequisites and usage.

---

## Requirements

| | |
|---|---|
| macOS | 13.0 Ventura+ |
| Swift | 5.9 |
| Xcode | 15+ |
| Permissions | Accessibility (mandatory) |
| Sandbox | None (incompatible with HID event taps) |
| Distribution | Developer ID or ad-hoc; Mac App Store incompatible |
