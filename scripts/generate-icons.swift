#!/usr/bin/env swift
// Generates all macOS app icon sizes for Shine from docs/logo.png.
// Usage: swift scripts/generate-icons.swift [project-root]
import Foundation
import CoreGraphics
import ImageIO

let args = CommandLine.arguments
let projectRoot = args.count > 1 ? args[1] : FileManager.default.currentDirectoryPath

let sourcePath = (projectRoot as NSString).appendingPathComponent("docs/logo.png")
let outputDir  = (projectRoot as NSString).appendingPathComponent(
    "Shine/Resources/Assets.xcassets/AppIcon.appiconset"
)

guard let provider = CGDataProvider(filename: sourcePath),
      let source   = CGImage(pngDataProviderSource: provider, decode: nil,
                             shouldInterpolate: true, intent: .defaultIntent) else {
    fputs("Error: cannot load \(sourcePath)\n", stderr)
    exit(1)
}

let srcW = CGFloat(source.width)
let srcH = CGFloat(source.height)

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16",     16),
    ("icon_16x16@2x",  32),
    ("icon_32x32",     32),
    ("icon_32x32@2x",  64),
    ("icon_128x128",   128),
    ("icon_128x128@2x",256),
    ("icon_256x256",   256),
    ("icon_256x256@2x",512),
    ("icon_512x512",   512),
    ("icon_512x512@2x",1024),
]

func makeIcon(px: Int) -> CGImage? {
    let s   = CGFloat(px)
    let cs  = CGColorSpaceCreateDeviceRGB()

    guard let ctx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.interpolationQuality = .high

    // Gradient: navy #1a1a2e -> black #000000, top-left to bottom-right
    let comps: [CGFloat] = [
        0.102, 0.102, 0.180, 1.0,  // #1a1a2e
        0.000, 0.000, 0.000, 1.0,  // #000000
    ]
    guard let grad = CGGradient(colorSpace: cs, colorComponents: comps,
                                locations: [0.0, 1.0], count: 2) else { return nil }
    // CG origin is bottom-left; (0,s)=visual top-left, (s,0)=visual bottom-right
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: 0, y: s),
        end:   CGPoint(x: s, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Diamond: preserve aspect ratio, 88% fill (6% padding per side)
    let pad   = s * 0.06
    let box   = s - pad * 2
    let scale = min(box / srcW, box / srcH)
    let dw    = srcW * scale
    let dh    = srcH * scale
    let dx    = pad + (box - dw) / 2
    let dy    = pad + (box - dh) / 2

    // CGContext.draw is right-side up in default lower-left-origin context.
    // Rect in CG base coords: y-origin is at the bottom of the draw area.
    ctx.draw(source, in: CGRect(x: dx, y: s - dy - dh, width: dw, height: dh))

    return ctx.makeImage()
}

for (name, px) in sizes {
    guard let icon = makeIcon(px: px) else {
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

print("\nAll icons generated.")
