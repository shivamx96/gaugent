import SwiftUI

enum GaugentAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }
    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case glyph
    case glyphAndPercent

    var id: Self { self }
    var title: String { self == .glyph ? "Icon" : "Icon + lowest remaining" }
}

enum GaugentTheme {
    static let accentLight = Color(red: 24 / 255, green: 124 / 255, blue: 118 / 255)
    static let accentDark = Color(red: 98 / 255, green: 200 / 255, blue: 192 / 255)

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 34 / 255, green: 35 / 255, blue: 39 / 255)
            : Color(red: 253 / 255, green: 253 / 255, blue: 252 / 255)
    }

    static func surfaceSunk(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 38 / 255, green: 40 / 255, blue: 44 / 255)
            : Color(red: 241 / 255, green: 241 / 255, blue: 238 / 255)
    }

    static func chrome(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 25 / 255, green: 26 / 255, blue: 29 / 255)
            : Color(red: 247 / 255, green: 247 / 255, blue: 245 / 255)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 41 / 255, green: 43 / 255, blue: 48 / 255)
            : Color.white
    }

    static func track(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.08) : Color(red: 20 / 255, green: 22 / 255, blue: 26 / 255).opacity(0.08)
    }

    static func primaryInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 233 / 255, green: 234 / 255, blue: 236 / 255)
            : Color(red: 25 / 255, green: 26 / 255, blue: 28 / 255)
    }

    static func secondaryInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 155 / 255, green: 160 / 255, blue: 168 / 255)
            : Color(red: 92 / 255, green: 97 / 255, blue: 106 / 255)
    }

    static func tertiaryInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 155 / 255, green: 160 / 255, blue: 168 / 255)
            : Color(red: 101 / 255, green: 106 / 255, blue: 114 / 255)
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.09) : Color(red: 20 / 255, green: 22 / 255, blue: 26 / 255).opacity(0.10)
    }

    static func hover(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.05) : Color(red: 20 / 255, green: 22 / 255, blue: 26 / 255).opacity(0.045)
    }

    static func selected(_ scheme: ColorScheme) -> Color {
        accent(scheme).opacity(scheme == .dark ? 0.15 : 0.09)
    }

    static func segmentSelection(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 49 / 255, green: 51 / 255, blue: 57 / 255) : .white
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? accentDark : accentLight
    }

    static func good(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 111 / 255, green: 165 / 255, blue: 126 / 255)
            : Color(red: 63 / 255, green: 125 / 255, blue: 83 / 255)
    }

    static func warning(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 193 / 255, green: 163 / 255, blue: 102 / 255)
            : Color(red: 138 / 255, green: 106 / 255, blue: 40 / 255)
    }

    static func danger(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 208 / 255, green: 138 / 255, blue: 131 / 255)
            : Color(red: 162 / 255, green: 79 / 255, blue: 73 / 255)
    }

    /// Bar colour for a remaining share: accent when comfortable, warning when low, danger when empty.
    static func level(_ remaining: Double, threshold: Double, scheme: ColorScheme) -> Color {
        if remaining <= 0 { return danger(scheme) }
        if remaining <= threshold { return warning(scheme) }
        return accent(scheme)
    }
}

struct BrandMark: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 19

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(GaugentTheme.accent(colorScheme))
            GaugeMark(strokeColor: .white.opacity(0.96), lineWidth: max(1.2, size * 0.1), remaining: 0.72)
                .padding(size * 0.2)
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(.white.opacity(0.04), lineWidth: 0.5)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A 270° dial with a needle. `remaining` of 1 points to the full end, 0 to empty, nil hides the needle.
struct GaugeMark: View {
    let strokeColor: Color
    let lineWidth: CGFloat
    var remaining: Double?

    var body: some View {
        Canvas { context, size in
            let geometry = GaugeGeometry(size: size)
            var arc = Path()
            arc.addArc(center: geometry.center, radius: geometry.radius, startAngle: .degrees(135), endAngle: .degrees(45), clockwise: false)
            context.stroke(arc, with: .color(strokeColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            if let remaining {
                var needle = Path()
                needle.move(to: geometry.center)
                needle.addLine(to: geometry.needleTip(remaining: remaining))
                context.stroke(needle, with: .color(strokeColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            let dot = max(1, lineWidth * 0.9)
            context.fill(Path(ellipseIn: CGRect(x: geometry.center.x - dot, y: geometry.center.y - dot, width: dot * 2, height: dot * 2)), with: .color(strokeColor))
        }
    }
}

/// Shared dial maths, in a y-down coordinate space, so the SwiftUI mark and the AppKit menu icon agree.
struct GaugeGeometry {
    let center: CGPoint
    let radius: CGFloat

    init(size: CGSize) {
        radius = min(size.width, size.height) * 0.42
        center = CGPoint(x: size.width / 2, y: size.height * 0.56)
    }

    /// Empty sits at the lower left (135°) and full at the lower right (45°), sweeping over the top.
    func needleTip(remaining: Double) -> CGPoint {
        let clamped = min(1, max(0, remaining))
        let degrees = 135 + 270 * clamped
        let radians = degrees * .pi / 180
        let length = radius * 0.78
        return CGPoint(x: center.x + cos(radians) * length, y: center.y + sin(radians) * length)
    }
}

struct QuietIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(configuration.isPressed ? GaugentTheme.primaryInk(colorScheme) : GaugentTheme.tertiaryInk(colorScheme))
            .frame(width: 22, height: 22)
            .background(GaugentTheme.hover(colorScheme).opacity(configuration.isPressed ? 1 : 0), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(prominent ? Color.white : GaugentTheme.primaryInk(colorScheme))
            .padding(.horizontal, 10)
            .frame(height: 23)
            .background(
                prominent ? GaugentTheme.accent(colorScheme) : GaugentTheme.segmentSelection(colorScheme),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(GaugentTheme.hairline(colorScheme), lineWidth: 0.5)
                }
            }
            .opacity(configuration.isPressed ? 0.74 : 1)
    }
}
