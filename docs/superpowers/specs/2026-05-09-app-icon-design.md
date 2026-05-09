# App Icon Asset Pipeline

**Date:** 2026-05-09  
**Branch:** feature/next-work

## Problem

- `logo.png` is 389×372 (non-square) — macOS requires square icons
- All 10 `Contents.json` slots reference the same `logo.png` — each needs its own correctly-sized PNG

## Design

### Visual

- **Source:** `docs/logo.png` (dark diamond gem with sparkles)
- **Background:** linear gradient, dark navy `#1a1a2e` → black `#000000`, 135°
- **Diamond:** centered, aspect-ratio preserved, 88% canvas fill (6% padding each side)

### Implementation: Option C — Swift + Core Graphics

No external dependencies. Uses `swift` CLI (included in Xcode Command Line Tools).

### Script: `scripts/generate-icons.swift`

- Accepts project root as argv[1] (defaults to cwd)
- Loads `docs/logo.png` via `CGDataProvider`
- Creates 1024×1024 `CGBitmapContext`, draws gradient, composites diamond
- Scales down to each required size using `kCGInterpolationHigh`
- Writes PNGs to `Shine/Resources/Assets.xcassets/AppIcon.appiconset/`

### Sizes

| File | px |
|---|---|
| icon_16x16.png | 16 |
| icon_16x16@2x.png | 32 |
| icon_32x32.png | 32 |
| icon_32x32@2x.png | 64 |
| icon_128x128.png | 128 |
| icon_128x128@2x.png | 256 |
| icon_256x256.png | 256 |
| icon_256x256@2x.png | 512 |
| icon_512x512.png | 512 |
| icon_512x512@2x.png | 1024 |

### Script: `scripts/generate-icons.sh`

Shell wrapper: `swift scripts/generate-icons.swift "$PROJECT_ROOT"`

### `Contents.json` update

Each of the 10 slots gets its own `filename` key matching the table above.

## Verification

- All 10 PNGs exist in appiconset directory
- `sips` reports each file at exact expected pixel dimensions
- `Contents.json` has no slots pointing to `logo.png`
