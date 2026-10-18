
import AppKit
import Foundation

guard (2...3).contains(CommandLine.arguments.count) else {
    fputs("usage: generate-icons.sh OUTPUT.icns [WEB_ASSETS_DIRECTORY]\n", stderr)
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

    BrandArtwork.draw(in: NSRect(x: 0, y: 0, width: size, height: size), detailed: entry.pixels >= 64)

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: iconsetURL.appendingPathComponent(entry.name), options: .atomic)
    if CommandLine.arguments.count == 3 {
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename: String? = switch entry.name {
        case "icon_16x16.png": "favicon-16.png"
        case "icon_32x32.png": "favicon-32.png"
        case "icon_256x256.png": "logo.png"
        default: nil
        }
        if let filename { try data.write(to: directory.appendingPathComponent(filename), options: .atomic) }
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
