#!/usr/bin/env swift
// Generates menu bar icon assets for Shine.
// Output: MenuBarIcon.imageset/menubar-icon.png (18px) and menubar-icon@2x.png (36px)
// Usage: swift scripts/generate-menubar-icon.swift [project-root]
import Foundation
import CoreGraphics
import ImageIO

let args = CommandLine.arguments
let projectRoot = args.count > 1 ? args[1] : FileManager.default.currentDirectoryPath
let outputDir = (projectRoot as NSString).appendingPathComponent(
    "Shine/Resources/Assets.xcassets/MenuBarIcon.imageset"
)
try? FileManager.default.createDirectory(atPath: outputDir,
                                         withIntermediateDirectories: true)

let sizes: [(name: String, px: Int)] = [
    ("menubar-icon",    18),
    ("menubar-icon@2x", 36),
]

// Draw a 4-pointed star centred at (cx, cy) with outer radius r (CG base coords).
func addSparkle(_ ctx: CGContext, cx: CGFloat, cy: CGFloat, r: CGFloat) {
    let inner = r * 0.22
    ctx.move(to: CGPoint(x: cx,        y: cy + r))
    ctx.addLine(to: CGPoint(x: cx + inner, y: cy + inner))
    ctx.addLine(to: CGPoint(x: cx + r,     y: cy))
    ctx.addLine(to: CGPoint(x: cx + inner, y: cy - inner))
    ctx.addLine(to: CGPoint(x: cx,         y: cy - r))
    ctx.addLine(to: CGPoint(x: cx - inner, y: cy - inner))
    ctx.addLine(to: CGPoint(x: cx - r,     y: cy))
    ctx.addLine(to: CGPoint(x: cx - inner, y: cy + inner))
    ctx.closePath()
}

func makeMenuBarIcon(px: Int) -> CGImage? {
    let s   = CGFloat(px)
    let cs  = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))

    let white = CGColor(colorSpace: cs, components: [1, 1, 1, 1])!

    // --- Diamond geometry (visual coords → CG: y_cg = s - y_vis) ---
    //  Pentagon outer points (visual):
    //    tl=(0.239,0.194)  tr=(0.761,0.194)
    //    r =(0.931,0.458)  bp=(0.500,0.917)  l=(0.069,0.458)
    //  Girdle centre: gc=(0.500, 0.458)
    //  Table centre top: tc=(0.500, 0.194)

    func pt(_ xv: CGFloat, _ yv: CGFloat) -> CGPoint {
        CGPoint(x: xv * s, y: s - yv * s)
    }

    let tl = pt(0.239, 0.194)
    let tr = pt(0.761, 0.194)
    let r  = pt(0.931, 0.458)
    let bp = pt(0.500, 0.917)
    let l  = pt(0.069, 0.458)
    let gc = pt(0.500, 0.458)
    let tc = pt(0.500, 0.194)

    // 1. Fill diamond silhouette
    ctx.setFillColor(white)
    ctx.beginPath()
    ctx.move(to: tl); ctx.addLine(to: tr); ctx.addLine(to: r)
    ctx.addLine(to: bp); ctx.addLine(to: l)
    ctx.closePath()
    ctx.fillPath()

    // 2. Cut crown facets (clear blend mode = transparent pixels)
    ctx.setBlendMode(.clear)
    let lw = s >= 30 ? 1.5 : 0.9
    ctx.setLineWidth(lw)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(CGColor(colorSpace: cs, components: [0, 0, 0, 1])!)

    // Crown V: tl → gc → tr
    ctx.beginPath()
    ctx.move(to: tl); ctx.addLine(to: gc); ctx.addLine(to: tr)
    ctx.strokePath()

    // Table centre drop: tc → gc
    ctx.beginPath()
    ctx.move(to: tc); ctx.addLine(to: gc)
    ctx.strokePath()

    ctx.setBlendMode(.normal)

    // 3. Sparkles (white, outside diamond, scaled to canvas)
    ctx.setFillColor(white)

    // Large sparkle — top-right
    ctx.beginPath()
    addSparkle(ctx, cx: s * 0.875, cy: s - s * 0.139, r: s * 0.100)
    ctx.fillPath()

    // Medium sparkle — top-left
    ctx.beginPath()
    addSparkle(ctx, cx: s * 0.111, cy: s - s * 0.056, r: s * 0.072)
    ctx.fillPath()

    // Small sparkle — bottom-right
    ctx.beginPath()
    addSparkle(ctx, cx: s * 0.847, cy: s - s * 0.722, r: s * 0.056)
    ctx.fillPath()

    return ctx.makeImage()
}

for (name, px) in sizes {
    guard let icon = makeMenuBarIcon(px: px) else {
        fputs("Error: failed to render \(name)\n", stderr); exit(1)
    }
    let path = (outputDir as NSString).appendingPathComponent("\(name).png")
    let url  = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fputs("Error: cannot create destination \(path)\n", stderr); exit(1)
    }
    CGImageDestinationAddImage(dest, icon, nil)
    guard CGImageDestinationFinalize(dest) else {
        fputs("Error: cannot write \(path)\n", stderr); exit(1)
    }
    print("✓ \(name).png (\(px)×\(px))")
}

print("\nMenu bar icons generated.")
