#!/usr/bin/env swift
// Draws the voz DMG background (dark, one electric-blue accent, an arrow toward Applications).
// Usage: swift make-dmg-bg.swift <out.png>   → matches the 600×420 window release.sh sets.
import AppKit

let W = 600.0, H = 420.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-bg.png"

let black = NSColor(red: 0x07/255.0, green: 0x08/255.0, blue: 0x0C/255.0, alpha: 1)
let electric = NSColor(red: 0x2E/255.0, green: 0x74/255.0, blue: 0xFF/255.0, alpha: 1)
let textHi = NSColor(white: 0.95, alpha: 1)
let mist = NSColor(red: 0x8B/255.0, green: 0x87/255.0, blue: 0x94/255.0, alpha: 1)

// Draw into a fixed 600×420-pixel bitmap (not lockFocus, which would 2× on a retina display and
// mismatch the DMG window's point size).
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

black.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()

// Wordmark + tagline (top-left). Finder y-origin is top; AppKit draws bottom-up.
("voz" as NSString).draw(at: NSPoint(x: 40, y: H - 78),
    withAttributes: [.font: NSFont.systemFont(ofSize: 40, weight: .bold), .foregroundColor: textHi])
("the voice layer for your Mac" as NSString).draw(at: NSPoint(x: 44, y: H - 104),
    withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .regular), .foregroundColor: mist])

// Arrow from the app icon (~x150) toward Applications (~x450), at the icon row.
let ay = H - 205.0 // mirror Finder icon y≈205
let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: 248, y: ay)); shaft.line(to: NSPoint(x: 352, y: ay))
shaft.lineWidth = 3; shaft.lineCapStyle = .round; electric.setStroke(); shaft.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 352, y: ay)); head.line(to: NSPoint(x: 339, y: ay + 8))
head.move(to: NSPoint(x: 352, y: ay)); head.line(to: NSPoint(x: 339, y: ay - 8))
head.lineWidth = 3; head.lineCapStyle = .round; electric.setStroke(); head.stroke()

// Install hint (bottom-center).
let hint = "Drag voz onto Applications to install" as NSString
let hAttr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                             .foregroundColor: NSColor(white: 0.82, alpha: 1)]
let hw = hint.size(withAttributes: hAttr).width
hint.draw(at: NSPoint(x: (W - hw) / 2, y: 64), withAttributes: hAttr)

NSGraphicsContext.restoreGraphicsState()

if let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
} else {
    FileHandle.standardError.write("failed to render\n".data(using: .utf8)!)
    exit(1)
}
