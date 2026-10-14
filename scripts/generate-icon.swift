#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-icon.swift OUTPUT.icns\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fileManager = FileManager.default
let iconsetURL = fileManager.temporaryDirectory.appendingPathComponent("Gaugent-\(UUID().uuidString).iconset", isDirectory: true)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconsetURL) }

let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512), ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for entry in entries {
    let size = CGFloat(entry.pixels)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: entry.pixels, pixelsHigh: entry.pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { continue }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let inset = size * 0.035
    let tileRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: size * 0.225, yRadius: size * 0.225)
    NSColor(red: 24 / 255, green: 124 / 255, blue: 118 / 255, alpha: 1).setFill()
    tile.fill()

    // The bitmap context is not flipped, so the dial is drawn in y-up coordinates: the arc
    // runs from 225° (lower left) counterclockwise... which in y-up space means sweeping over
    // the top from the lower left to the lower right, matching the in-app template icon.
    let dialRect = tileRect.insetBy(dx: tileRect.width * 0.21, dy: tileRect.height * 0.21)
    let radius = min(dialRect.width, dialRect.height) * 0.42
    let center = NSPoint(x: dialRect.midX, y: dialRect.minY + dialRect.height * 0.44)
    let lineWidth = max(size < 64 ? size * 0.1 : size * 0.058, 1.6)

    let arc = NSBezierPath()
    arc.lineWidth = lineWidth
    arc.lineCapStyle = .round
    arc.appendArc(withCenter: center, radius: radius, startAngle: 225, endAngle: -45, clockwise: true)
    NSColor.white.setStroke()
    arc.stroke()

    let remaining = 0.72
    let degrees = 225 - 270 * remaining
    let radians = degrees * .pi / 180
    let needle = NSBezierPath()
    needle.lineWidth = lineWidth
    needle.lineCapStyle = .round
    needle.move(to: center)
    needle.line(to: NSPoint(x: center.x + cos(radians) * radius * 0.78, y: center.y + sin(radians) * radius * 0.78))
    needle.stroke()

    let dot = lineWidth * 0.9
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)).fill()

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: iconsetURL.appendingPathComponent(entry.name), options: .atomic)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
