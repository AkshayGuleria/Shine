# Shine — Project Guide

A macOS menu-bar utility that briefly disables the keyboard and trackpad so the user can wipe the laptop clean. Auto-restores on a timer with multiple safety nets.

---

## 1. Status & decisions locked

| Decision | Choice | Notes |
|---|---|---|
| Product name | **Shine** | App bundle: `Shine.app`. Bundle ID suggestion: `com.akshayguleria.shine` |
| Mechanism | `CGEventTap` at `kCGHIDEventTap`, drop all events except allowlisted abort | Validated: this is the only path that covers keyboard + trackpad + external HID without root |
| App shape | SwiftUI app, `LSUIElement = true` (menu-bar only, no Dock icon) | `MenuBarExtra` for the status item, `Settings` scene for prefs |
| Default lock duration | 60 seconds | Hard cap **120 seconds** — enforced in code, not just UI |
| Abort gesture | **Hold Esc for 2 seconds** | Allowlisted through the tap; everything else is dropped |
| Watchdog | Independent `DispatchSourceTimer`, fires at `duration + 5s` and tears down the tap unconditionally | Survives main-thread hangs |
| Crash safety | `atexit` handler removes tap; macOS auto-cleans event taps on process death | Force-quit always restores input |
| Sleep safety | Auto-unlock on `NSWorkspace.willSleepNotification` | Don't get stuck post-lid-close |
| Permission | Accessibility (via `AXIsProcessTrustedWithOptions`) | Deep-link to System Settings if missing |
| Min macOS | **13.0 Ventura** | Lets us use `MenuBarExtra` and `Settings` scene |
| Distribution | **Developer ID signed + notarized** | Mac App Store is incompatible — sandbox blocks system-wide HID taps |
| Language / toolchain | Swift 5.9, SwiftUI + minimal AppKit bridge for the overlay window, Xcode 15+ | |

---

## 2. Why CGEventTap (and not the alternatives)

| Approach | Verdict | Reason |
|---|---|---|
| **CGEventTap** | ✅ chosen | Covers keyboard, trackpad, scroll, gestures, external mice. User-space. Tap is auto-removed on process death — built-in safety net. One-time Accessibility grant. |
| `hidutil` key remap | ❌ | Doesn't disable trackpad. Defeats the use case. |
| IOKit `seize` HID devices | ❌ | Needs root. Risk of system instability. Apple may further restrict. |
| Kernel extension / DriverKit | ❌ | Massive overkill, complex distribution, requires extra entitlements. |

The trade-off accepted: users will see a one-time Accessibility prompt the first time they try to lock. This is well-understood by Mac users (Karabiner, Rectangle, BetterTouchTool, etc. all do the same).

---

## 3. Architecture

```
┌─────────────────┐
│   MenuBarView   │  status item + start button + duration submenu
└────────┬────────┘
         │ user clicks "Start"
         ▼
┌─────────────────┐         ┌──────────────────────┐
│ AppCoordinator  │────────▶│ PermissionCoordinator│  refuses if not trusted
│  (state machine)│         └──────────────────────┘
└────────┬────────┘
         │ enters .arming → .locked
         ▼
┌─────────────────┐         ┌──────────────────────┐
│  InputBlocker   │────────▶│      AbortGuard      │  tracks Esc-hold timing
│ (CGEventTap)    │◀────────│                      │  signals coordinator
└────────┬────────┘         └──────────────────────┘
         │ installs tap, schedules watchdog
         ▼
┌─────────────────┐
│ OverlayWindow   │  full-screen NSWindow at .screenSaver level
│   + countdown   │
└─────────────────┘
         │ on timer expiry / abort / sleep
         ▼
   restore input, dismiss overlay, return to .idle
```

### State machine

```
.idle ──start──▶ .arming(remaining: 3) ──tick──▶ .locked(remaining: N)
                          │                              │
                          │                              ├── tick to 0 ──▶ .unlocking
                          │                              ├── abort ─────▶ .unlocking
                          │                              ├── watchdog ──▶ .unlocking
                          │                              └── sleep ─────▶ .unlocking
                          ▼
                       cancelled ──▶ .idle
                                              .unlocking ──▶ .idle
```

Each transition is the only place that calls into `InputBlocker` (`install` on entering `.locked`, `uninstall` on entering `.unlocking`). This makes the surface area for "did we forget to release the tap?" bugs minimal.

---

## 4. Module-by-module spec

### `App.swift`
```swift
@main
struct ShineApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("Shine", systemImage: "sparkles") {
            MenuBarView(coordinator: coordinator)
        }
        Settings { SettingsView(coordinator: coordinator) }
    }
}
```
Set `LSUIElement = true` in `Info.plist`.

### `AppCoordinator.swift`
- `@Published var state: LockState`
- `start(duration: TimeInterval)` — entrypoint from menu
- Owns `InputBlocker`, `TimerService`, `OverlayWindowController`
- Subscribes to `NSWorkspace.willSleepNotification`

### `InputBlocker.swift`
Wraps `CGEventTapCreate`. Key signature:
```swift
final class InputBlocker {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let abortGuard: AbortGuard

    func install() throws {
        guard AXIsProcessTrusted() else { throw BlockerError.notAuthorized }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)        |
            (1 << CGEventType.keyUp.rawValue)          |
            (1 << CGEventType.flagsChanged.rawValue)   |
            (1 << CGEventType.mouseMoved.rawValue)     |
            (1 << CGEventType.leftMouseDown.rawValue)  |
            (1 << CGEventType.leftMouseUp.rawValue)    |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue)   |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)   |
            (1 << CGEventType.leftMouseDragged.rawValue)  |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)    |
            (1 << CGEventType.tabletPointer.rawValue)  |
            (1 << CGEventType.tabletProximity.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,         // .defaultTap allows us to drop events
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let me = Unmanaged<InputBlocker>.fromOpaque(refcon!).takeUnretainedValue()
                if me.abortGuard.shouldPassThrough(event: event, type: type) {
                    return Unmanaged.passUnretained(event)
                }
                return nil   // drop
            },
            userInfo: userInfo
        )
        // attach to runloop, enable, register atexit cleanup, schedule watchdog
    }

    func uninstall() { /* idempotent */ }
}
```

Notes:
- Use `.cghidEventTap` (not `.cgSessionEventTap`) so we catch hardware-level events before any other consumer.
- Use `.headInsertEventTap` so we run before competing taps.
- The `options: .defaultTap` (not `.listenOnly`) is what lets us drop events.
- Returning `nil` from the callback drops the event.

### `AbortGuard.swift`
- Tracks Esc keyDown timestamp
- Returns `true` from `shouldPassThrough` for the Esc key events themselves (so the OS doesn't think it's being held in some weird way)
- After Esc has been held continuously for ≥ 2.0s, posts a notification → coordinator transitions to `.unlocking`
- Resets on Esc keyUp

### `TimerService.swift`
- Two timers: a UI timer (50ms tick for countdown render) and a watchdog (`DispatchSourceTimer` on a background queue, fires at duration + 5s)
- Watchdog has a hard reference to the InputBlocker and calls `uninstall()` even if the coordinator is wedged

### `OverlayWindow.swift` / `OverlayView.swift`
- `NSWindow` with `styleMask = .borderless`, `level = .screenSaver`, `isOpaque = false`, alpha 0.95, covers all screens
- SwiftUI content: arming countdown ("3, 2, 1"), then big lock countdown + "Hold Esc for 2s to abort"
- On unlock, fade out over 300ms before close

### `PermissionCoordinator.swift`
```swift
func ensureAccessibility() -> Bool {
    let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
    return AXIsProcessTrustedWithOptions(opts)
}

func openAccessibilitySettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
}
```

### `MenuBarView.swift`
- Big "Start cleaning (60s)" button
- Submenu: 15 / 30 / 60 / 90 / 120s
- "Settings…" → opens Settings scene
- "Quit Shine"

### `SettingsView.swift`
- Default duration (slider 15–120, step 15)
- Sound on completion (Bool)
- Launch at login (Bool, via `SMAppService` if you want it)
- Link: "Open Accessibility settings"

---

## 5. `Info.plist` keys

```xml
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>CFBundleIdentifier</key><string>com.akshayguleria.shine</string>
<key>NSHumanReadableCopyright</key><string>© 2026 Akshay Guleria</string>
<!-- Required text shown in any Accessibility prompt the OS surfaces: -->
<key>NSAccessibilityUsageDescription</key>
<string>Shine briefly disables the keyboard and trackpad while you wipe your Mac clean, then restores input automatically.</string>
```

No special entitlements needed for CGEventTap. If you sign with Hardened Runtime (you should, for notarization), no extra exceptions are required for this functionality.

---

## 6. Project layout

```
Shine/
├── PROJECT_GUIDE.md              ← this document
├── Shine.xcodeproj               ← create via Xcode "App" template, SwiftUI, macOS
├── Shine/
│   ├── App.swift
│   ├── AppCoordinator.swift
│   ├── State/
│   │   └── LockState.swift
│   ├── Input/
│   │   ├── InputBlocker.swift
│   │   └── AbortGuard.swift
│   ├── Timing/
│   │   └── TimerService.swift
│   ├── UI/
│   │   ├── MenuBarView.swift
│   │   ├── OverlayWindow.swift
│   │   ├── OverlayView.swift
│   │   └── SettingsView.swift
│   ├── Permissions/
│   │   └── PermissionCoordinator.swift
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   └── Info.plist
│   └── Shine.entitlements        ← Hardened Runtime, no special exceptions
├── ShineTests/
│   ├── LockStateMachineTests.swift
│   ├── TimerServiceTests.swift
│   └── AbortGuardTests.swift
└── docs/
    └── DECISIONS.md              ← optional ADR-style notes as you go
```

---

## 7. Build phases

Work in this order. Each phase has a clear "done" criterion so you know when to move on.

### Phase 1 — CLI proof of concept (½ day)
**Goal:** prove `CGEventTap` can drop all events for N seconds, then restore.

Create a standalone Swift script (`docs/poc/lock_poc.swift`) that:
1. Calls `AXIsProcessTrustedWithOptions` and exits with a helpful message if not trusted.
2. Installs a CGEventTap with the full event mask.
3. Sleeps 5 seconds via `RunLoop.main.run(until:)`.
4. Removes the tap and exits.

Test by running `swift docs/poc/lock_poc.swift` from Terminal. The first run will trigger the Accessibility prompt — grant it to `Terminal.app` (or whatever shell you're in).

**Done when:** keyboard + trackpad are dead for 5s, then come back.

### Phase 2 — Xcode project scaffold (½ day)
- Create the Xcode project, App template, SwiftUI lifecycle, macOS target
- Wire `MenuBarExtra` + `Settings` scene
- Set `LSUIElement = true`
- Stub out the modules from §4 with empty implementations and unit-test targets
- Implement `LockState` enum + `AppCoordinator` state transitions + tests

**Done when:** menu bar shows the icon, button states change correctly in tests, no real input blocking yet.

### Phase 3 — Wire the tap (1 day)
- Port the POC into `InputBlocker`
- Connect `AppCoordinator` → `InputBlocker.install()` on entering `.locked`
- Implement watchdog
- Implement sleep observer
- For now, abort by killing the app (Activity Monitor)

**Done when:** clicking "Start" in the menu actually disables input; timer expiry restores; force-quit also restores.

### Phase 4 — Overlay window + countdown UI (½ day)
- Build `OverlayWindowController` that manages a borderless `NSWindow` at `.screenSaver` level
- SwiftUI content with arming countdown then lock countdown
- Fade in/out animations

**Done when:** lock mode shows a clear visual cue with seconds remaining.

### Phase 5 — Abort hotkey (½ day)
- Implement `AbortGuard` Esc-hold tracking
- Pass-through Esc events themselves
- Trigger unlock when held ≥ 2.0s
- Update overlay to show "Hold Esc for 2s to abort" hint

**Done when:** during locked state, pressing-and-holding Esc for 2s unlocks; tapping Esc briefly does nothing.

### Phase 6 — Permission UX (½ day)
- First-run check for Accessibility
- If missing, show a window with "Open Accessibility settings" button (deep-link)
- Refuse to enter `.locked` if permission gets revoked between launches

**Done when:** a fresh install on a clean machine walks the user through granting permission with no confusion.

### Phase 7 — Polish (1 day)
- `UserDefaults` persistence for default duration & sound preference
- Optional completion chime via `NSSound`
- Optional launch-at-login via `SMAppService.mainApp`
- App icon (a simple sparkle/cloth motif)
- About window

### Phase 8 — Sign + notarize (½ day, gated on Apple Developer account)
- Enable Hardened Runtime in build settings
- Code-sign with Developer ID Application certificate
- Notarize via `xcrun notarytool submit`
- Staple the ticket: `xcrun stapler staple Shine.app`
- Test on a clean machine via Gatekeeper

---

## 8. Test strategy

### Unit tests (no real input tap involved)
- **LockStateMachineTests** — every transition; can't go from `.idle` directly to `.locked`; abort during `.arming` cancels cleanly
- **TimerServiceTests** — tick fires at the right cadence; watchdog fires after expected delay; cancellation
- **AbortGuardTests** — Esc keyDown then keyUp before 2s does NOT trigger; continuous hold ≥ 2s DOES trigger; other keys never trigger

### Manual matrix (run before each release)
| Scenario | Expected |
|---|---|
| Permission missing on first launch | Friendly prompt, deep-link to Settings, can't start lock |
| Click Start, wait full duration | Input blocked entire time, restored on expiry |
| Click Start, wait 5s, hold Esc 2s | Input restored ~2s after Esc-hold begins |
| Click Start, force-quit Shine via Activity Monitor | Input restored within ~1s |
| Click Start, close laptop lid | Input restored on wake (sleep handler) |
| External Bluetooth keyboard during lock | Also blocked |
| External wired mouse during lock | Also blocked |
| External display connected during lock | Overlay covers all screens, lock still works |
| Two instances of Shine launched | Second instance refuses to start, no stacked taps |

---

## 9. Distribution checklist

When ready to ship to others:
1. Apple Developer Program membership active ($99/yr)
2. Developer ID Application certificate in Keychain
3. App-specific password for `notarytool` stored in Keychain via `xcrun notarytool store-credentials`
4. Build settings: Hardened Runtime ON, Code Signing = Developer ID Application
5. Archive → Export → Developer ID
6. `xcrun notarytool submit Shine.zip --keychain-profile shine-notary --wait`
7. `xcrun stapler staple Shine.app`
8. Verify on a fresh user account: `spctl --assess --verbose Shine.app`
9. Distribute as a `.dmg` or `.zip`

---

## 10. Open items / deferred decisions

- **Icon design** — concept: a sparkle or polished surface. Punted to phase 7.
- **Launch-at-login** — nice-to-have, gated on `SMAppService` API behavior.
- **Telemetry** — none planned. Personal-quality utility.
- **Multi-language** — English-only for v1.
- **Touch Bar Macs** — Touch Bar input also flows through the event tap mask — should "just work" but verify in phase 3.
- **Marketing site / DMG background image** — only relevant if distributing to others.

---

## 11. Handoff to code mode

When you start coding, the most efficient first prompt is something like:

> Read `PROJECT_GUIDE.md`. Start with Phase 1: write `docs/poc/lock_poc.swift` per §7. After it works on my machine, scaffold the Xcode project per §6 and begin Phase 2.

The guide is intended to be self-sufficient — code mode shouldn't need to refer back to this conversation.

---

## 12. References

- Apple, *Quartz Event Services* (`CGEventTap`, `CGEventTapCreate`) — https://developer.apple.com/documentation/coregraphics/quartz_event_services
- Apple, *Accessibility API* (`AXIsProcessTrustedWithOptions`) — https://developer.apple.com/documentation/applicationservices/axuielement_h
- Apple, *Notarizing macOS Software Before Distribution* — https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution
- Karabiner-Elements (reference implementation of low-level input handling on macOS) — https://github.com/pqrs-org/Karabiner-Elements
