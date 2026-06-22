#!/usr/bin/env swift
// Draws the voz DMG background — dark gradient, a soft electric glow, the wordmark, a curved arrow
// from the app toward Applications, and install copy. Matches the 600×440 window dmgbuild sets.
// Usage: swift make-dmg-bg.swift <out.png>
import AppKit

let W = 600.0, H = 440.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-bg.png"

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(red: r/255.0, green: g/255.0, blue: b/255.0, alpha: a)
}
let electric = rgb(0x2E, 0x74, 0xFF)
let textHi = NSColor(white: 0.96, alpha: 1)
let mist = rgb(0x8B, 0x87, 0x94)

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// 1. Vertical gradient backdrop.
NSGradient(starting: rgb(0x0B, 0x0C, 0x15), ending: rgb(0x06, 0x07, 0x0B))!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

// 2. Soft electric glow centred behind the icon row.
ctx.saveGState()
let glowCenter = CGPoint(x: 300, y: 220)
if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [electric.withAlphaComponent(0.16).cgColor, electric.withAlphaComponent(0).cgColor] as CFArray,
                      locations: [0, 1]) {
    ctx.drawRadialGradient(g, startCenter: glowCenter, startRadius: 0,
                           endCenter: glowCenter, endRadius: 300, options: [])
}
ctx.restoreGState()

func centered(_ s: String, y: Double, font: NSFont, color: NSColor) {
    let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let w = (s as NSString).size(withAttributes: attr).width
    (s as NSString).draw(at: NSPoint(x: (W - w) / 2, y: y), withAttributes: attr)
}

// 3. Wordmark + tagline (top, centred).
centered("voz", y: H - 70, font: .systemFont(ofSize: 34, weight: .bold), color: textHi)
centered("the voice layer for your Mac", y: H - 96, font: .systemFont(ofSize: 12.5, weight: .regular), color: mist)

// 4. Instruction (above the icon row).
centered("Drag voz onto Applications to install", y: 280,
         font: .systemFont(ofSize: 13.5, weight: .semibold), color: NSColor(white: 0.88, alpha: 1))

// 5. Curved arrow from just right of the app icon (x≈215) to just left of Applications (x≈385),
//    at the icon-row height (y≈220 from top → y≈220 from bottom here). A gentle downward swoop.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 232, y: 232))
arrow.curve(to: NSPoint(x: 372, y: 222), controlPoint1: NSPoint(x: 280, y: 196), controlPoint2: NSPoint(x: 330, y: 198))
arrow.lineWidth = 3.5; arrow.lineCapStyle = .round
electric.setStroke(); arrow.stroke()
// Arrowhead.
let head = NSBezierPath()
head.move(to: NSPoint(x: 372, y: 222)); head.line(to: NSPoint(x: 357, y: 230))
head.move(to: NSPoint(x: 372, y: 222)); head.line(to: NSPoint(x: 361, y: 209))
head.lineWidth = 3.5; head.lineCapStyle = .round; electric.setStroke(); head.stroke()

// 6. Footer microcopy.
centered("100% on-device · notarized · nothing leaves your Mac", y: 40,
         font: .systemFont(ofSize: 11, weight: .regular), color: rgb(0x6A, 0x67, 0x74))

NSGraphicsContext.restoreGraphicsState()

if let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: out)); print("wrote \(out)")
} else { FileHandle.standardError.write("failed to render\n".data(using: .utf8)!); exit(1) }
