#!/usr/bin/env swift
// Composes the warble DMG background from the official brand watermark (diagonal energy beam + rising
// sound-wave ribs, dark) with one quiet install line. The watermark's center is intentionally calm,
// so the app + Applications icons (placed by dmgbuild) read cleanly on top.
// Usage: swift make-dmg-bg.swift <out.png>   — expects watermark.png beside the output (media/).
import AppKit

let W = 600.0, H = 420.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-bg.png"
let wmPath = (out as NSString).deletingLastPathComponent.appending("/watermark.png")

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Base fill (in case the watermark has any transparent edge).
NSColor(red: 0x07/255.0, green: 0x08/255.0, blue: 0x0C/255.0, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// Watermark, aspect-FILL (cover) and centered, clipped to the frame.
if let wm = NSImage(contentsOfFile: wmPath) {
    let s = wm.size
    let scale = max(W / s.width, H / s.height)
    let dw = s.width * scale, dh = s.height * scale
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).setClip()
    wm.draw(in: NSRect(x: (W - dw) / 2, y: (H - dh) / 2, width: dw, height: dh),
            from: .zero, operation: .sourceOver, fraction: 1.0)
} else {
    FileHandle.standardError.write("watermark not found at \(wmPath)\n".data(using: .utf8)!)
}

// A soft scrim along the bottom so the install line always reads over the art.
NSGraphicsContext.current?.cgContext.saveGState()
if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [NSColor.black.withAlphaComponent(0).cgColor,
                               NSColor.black.withAlphaComponent(0.45).cgColor] as CFArray,
                      locations: [0, 1]) {
    NSGraphicsContext.current?.cgContext.drawLinearGradient(
        g, start: CGPoint(x: 0, y: 110), end: CGPoint(x: 0, y: 0), options: [])
}
NSGraphicsContext.current?.cgContext.restoreGState()

// One quiet install line near the bottom.
let hint = "Drag warble onto Applications to install" as NSString
let attr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
                                            .foregroundColor: NSColor(white: 0.92, alpha: 1)]
let hw = hint.size(withAttributes: attr).width
hint.draw(at: NSPoint(x: (W - hw) / 2, y: 40), withAttributes: attr)

NSGraphicsContext.restoreGraphicsState()

if let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: out)); print("wrote \(out)")
} else { FileHandle.standardError.write("failed to render\n".data(using: .utf8)!); exit(1) }
