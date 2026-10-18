import AppKit

/// Shared artwork for the application bundle, native brand marks, and website exports.
/// Coordinates use a 128-point, y-up canvas; small icons omit the instrument detail.
enum BrandArtwork {
    static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect, detailed: size >= 64)
            return true
        }
    }

    static func draw(in rect: NSRect, detailed: Bool) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 128, yBy: rect.height / 128)
        transform.concat()

        let tile = NSBezierPath(roundedRect: NSRect(x: 7, y: 7, width: 114, height: 114), xRadius: 27, yRadius: 27)
        NSGradient(starting: color(0x0B454B), ending: color(0x289F91))!.draw(in: tile, angle: 75)
        if detailed {
            let edge = NSBezierPath(roundedRect: NSRect(x: 8, y: 8, width: 112, height: 112), xRadius: 26, yRadius: 26)
            edge.lineWidth = 0.8
            NSColor.white.withAlphaComponent(0.25).setStroke()
            edge.stroke()
            let face = NSBezierPath(ovalIn: NSRect(x: 19, y: 19, width: 90, height: 90))
            NSGradient(starting: color(0x125B60), ending: color(0x0B4048))!.draw(in: face, angle: 90)
            face.lineWidth = 0.8
            color(0xB5F4D7).withAlphaComponent(0.28).setStroke()
            face.stroke()
        }

        let center = NSPoint(x: 64, y: 61)
        let radius: CGFloat = detailed ? 34 : 35
        let weight: CGFloat = detailed ? 7 : 10
        arc(center, radius: radius, from: 225, to: 58, width: weight, color: color(0xF3FFF7))
        arc(center, radius: radius, from: 44, to: -45, width: weight, color: color(0x94E6BC))

        if detailed {
            // A second scale and calibration ticks give the large icon an instrument face.
            arc(center, radius: 24, from: 225, to: -45, width: 1, color: color(0xB5F4D7).withAlphaComponent(0.24))
            for degree in stride(from: -45, through: 225, by: 45) {
                let angle = Double(degree) * .pi / 180
                let a = point(center, radius: 41, angle: angle)
                let b = point(center, radius: 44, angle: angle)
                let tick = NSBezierPath()
                tick.move(to: a); tick.line(to: b)
                tick.lineWidth = 1.2
                color(0xD6FFEB).withAlphaComponent(0.55).setStroke()
                tick.stroke()
            }
        }

        // The tapered pointer crosses the open segment of the scale, creating the signature cut.
        let pointer = NSBezierPath()
        pointer.move(to: NSPoint(x: 58, y: 57))
        pointer.line(to: NSPoint(x: 90, y: 90))
        pointer.line(to: NSPoint(x: 69, y: 55))
        pointer.close()
        color(0xF3FFF7).setFill()
        pointer.fill()
        let pivot = NSBezierPath(ovalIn: NSRect(x: 58, y: 55, width: 12, height: 12))
        color(0xF3FFF7).setFill(); pivot.fill()
        let pin = NSBezierPath(ovalIn: NSRect(x: 61.5, y: 58.5, width: 5, height: 5))
        color(0x135C61).setFill(); pin.fill()
        if detailed {
            let indicator = NSBezierPath(roundedRect: NSRect(x: 57, y: 26, width: 14, height: 3), xRadius: 1.5, yRadius: 1.5)
            color(0x94E6BC).setFill(); indicator.fill()
        }
    }

    private static func point(_ center: NSPoint, radius: CGFloat, angle: Double) -> NSPoint {
        NSPoint(x: center.x + CGFloat(Foundation.cos(angle)) * radius,
                y: center.y + CGFloat(Foundation.sin(angle)) * radius)
    }

    private static func arc(_ center: NSPoint, radius: CGFloat, from: CGFloat, to: CGFloat,
                            width: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.appendArc(withCenter: center, radius: radius, startAngle: from, endAngle: to, clockwise: true)
        color.setStroke(); path.stroke()
    }

    private static func color(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}
