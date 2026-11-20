import AppKit

/// Monochrome provider marks adapted from Simple Icons 14.0.0 (CC0).
/// Source: https://github.com/simple-icons/simple-icons/tree/14.0.0/icons
/// Provider names and marks belong to their respective owners.
/// Native paths keep the menu bar sharp at every backing scale without resource-bundle lookup.
enum ProviderArtwork {
    static func menuBarIcon(providerID: String?) -> NSImage? {
        let path: NSBezierPath
        let name: String
        switch providerID {
        case "codex": path = openAI(); name = "OpenAI"
        case "claude": path = anthropic(); name = "Anthropic"
        default: return nil
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            let transform = NSAffineTransform()
            transform.translateX(by: rect.minX + 1, yBy: rect.minY + 1)
            transform.scaleX(by: (rect.width - 2) / 24, yBy: (rect.height - 2) / 24)
            transform.concat()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = name
        return image
    }

    private static func openAI() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 22.28190, y: 9.82110))
        path.curve(to: NSPoint(x: 22.55412, y: 7.31004),
                   controlPoint1: NSPoint(x: 22.55024, y: 9.01300), controlPoint2: NSPoint(x: 22.64305, y: 8.15686))
        path.curve(to: NSPoint(x: 21.76620, y: 4.91030),
                   controlPoint1: NSPoint(x: 22.46520, y: 6.46321), controlPoint2: NSPoint(x: 22.19656, y: 5.64503))
        path.curve(to: NSPoint(x: 18.98398, y: 2.39926),
                   controlPoint1: NSPoint(x: 21.12827, y: 3.79990), controlPoint2: NSPoint(x: 20.15376, y: 2.92037))
        path.curve(to: NSPoint(x: 15.25640, y: 2.01030),
                   controlPoint1: NSPoint(x: 17.81420, y: 1.87814), controlPoint2: NSPoint(x: 16.50856, y: 1.74190))
        path.curve(to: NSPoint(x: 11.59637, y: 0.05994),
                   controlPoint1: NSPoint(x: 14.30370, y: 0.95055), controlPoint2: NSPoint(x: 13.00732, y: 0.25974))
        path.curve(to: NSPoint(x: 7.53873, y: 0.91741),
                   controlPoint1: NSPoint(x: 10.18542, y: -0.13987), controlPoint2: NSPoint(x: 8.74821, y: 0.16385))
        path.curve(to: NSPoint(x: 4.98070, y: 4.18180),
                   controlPoint1: NSPoint(x: 6.32925, y: 1.67098), controlPoint2: NSPoint(x: 5.42320, y: 2.82722))
        path.curve(to: NSPoint(x: 2.66875, y: 5.20019),
                   controlPoint1: NSPoint(x: 4.14639, y: 4.35288), controlPoint2: NSPoint(x: 3.35814, y: 4.70010))
        path.curve(to: NSPoint(x: 0.98300, y: 7.08180),
                   controlPoint1: NSPoint(x: 1.97937, y: 5.70028), controlPoint2: NSPoint(x: 1.40462, y: 6.34181))
        path.curve(to: NSPoint(x: 0.19589, y: 10.75134),
                   controlPoint1: NSPoint(x: 0.33814, y: 8.19035), controlPoint2: NSPoint(x: 0.06240, y: 9.47584))
        path.curve(to: NSPoint(x: 1.72570, y: 14.17840),
                   controlPoint1: NSPoint(x: 0.32938, y: 12.02684), controlPoint2: NSPoint(x: 0.86529, y: 13.22739))
        path.curve(to: NSPoint(x: 1.45075, y: 16.68895),
                   controlPoint1: NSPoint(x: 1.45637, y: 14.98611), controlPoint2: NSPoint(x: 1.36263, y: 15.84209))
        path.curve(to: NSPoint(x: 2.23670, y: 19.08910),
                   controlPoint1: NSPoint(x: 1.53887, y: 17.53580), controlPoint2: NSPoint(x: 1.80685, y: 18.35415))
        path.curve(to: NSPoint(x: 5.02141, y: 21.60075),
                   controlPoint1: NSPoint(x: 2.87544, y: 20.19991), controlPoint2: NSPoint(x: 3.85080, y: 21.07963))
        path.curve(to: NSPoint(x: 8.75130, y: 21.98920),
                   controlPoint1: NSPoint(x: 6.19202, y: 22.12187), controlPoint2: NSPoint(x: 7.49843, y: 22.25792))
        path.curve(to: NSPoint(x: 10.78861, y: 23.48114),
                   controlPoint1: NSPoint(x: 9.31654, y: 22.62573), controlPoint2: NSPoint(x: 10.01115, y: 23.13440))
        path.curve(to: NSPoint(x: 13.25990, y: 24.00000),
                   controlPoint1: NSPoint(x: 11.56607, y: 23.82788), controlPoint2: NSPoint(x: 12.40864, y: 24.00478))
        path.curve(to: NSPoint(x: 16.83177, y: 22.83849),
                   controlPoint1: NSPoint(x: 14.54333, y: 24.00118), controlPoint2: NSPoint(x: 15.79451, y: 23.59432))
        path.curve(to: NSPoint(x: 19.03170, y: 19.79420),
                   controlPoint1: NSPoint(x: 17.86903, y: 22.08265), controlPoint2: NSPoint(x: 18.63964, y: 21.01628))
        path.curve(to: NSPoint(x: 21.34339, y: 18.77539),
                   controlPoint1: NSPoint(x: 19.86591, y: 19.62282), controlPoint2: NSPoint(x: 20.65405, y: 19.27547))
        path.curve(to: NSPoint(x: 23.02940, y: 16.89410),
                   controlPoint1: NSPoint(x: 22.03273, y: 18.27531), controlPoint2: NSPoint(x: 22.60756, y: 17.63391))
        path.curve(to: NSPoint(x: 23.80339, y: 13.23635),
                   controlPoint1: NSPoint(x: 23.66664, y: 15.78718), controlPoint2: NSPoint(x: 23.93763, y: 14.50652))
        path.curve(to: NSPoint(x: 22.28190, y: 9.82120),
                   controlPoint1: NSPoint(x: 23.66916, y: 11.96618), controlPoint2: NSPoint(x: 23.13645, y: 10.77046))
        path.line(to: NSPoint(x: 22.28190, y: 9.82110))
        path.close()
        path.move(to: NSPoint(x: 13.25990, y: 22.42920))
        path.curve(to: NSPoint(x: 10.38350, y: 21.38840),
                   controlPoint1: NSPoint(x: 12.20887, y: 22.43086), controlPoint2: NSPoint(x: 11.19011, y: 22.06224))
        path.line(to: NSPoint(x: 10.52540, y: 21.30800))
        path.line(to: NSPoint(x: 15.30370, y: 18.54980))
        path.curve(to: NSPoint(x: 15.59021, y: 18.26112),
                   controlPoint1: NSPoint(x: 15.42262, y: 18.48006), controlPoint2: NSPoint(x: 15.52137, y: 18.38056))
        path.curve(to: NSPoint(x: 15.69640, y: 17.86850),
                   controlPoint1: NSPoint(x: 15.65906, y: 18.14168), controlPoint2: NSPoint(x: 15.69566, y: 18.00636))
        path.line(to: NSPoint(x: 15.69640, y: 11.13160))
        path.line(to: NSPoint(x: 17.71640, y: 12.30020))
        path.curve(to: NSPoint(x: 17.74164, y: 12.32164),
                   controlPoint1: NSPoint(x: 17.72638, y: 12.30526), controlPoint2: NSPoint(x: 17.73503, y: 12.31261))
        path.curve(to: NSPoint(x: 17.75440, y: 12.35220),
                   controlPoint1: NSPoint(x: 17.74824, y: 12.33068), controlPoint2: NSPoint(x: 17.75261, y: 12.34115))
        path.line(to: NSPoint(x: 17.75440, y: 17.93480))
        path.curve(to: NSPoint(x: 16.43518, y: 21.11005),
                   controlPoint1: NSPoint(x: 17.75186, y: 19.12558), controlPoint2: NSPoint(x: 17.27720, y: 20.26806))
        path.curve(to: NSPoint(x: 13.25990, y: 22.42920),
                   controlPoint1: NSPoint(x: 15.59317, y: 21.95205), controlPoint2: NSPoint(x: 14.45068, y: 22.42669))
        path.line(to: NSPoint(x: 13.25990, y: 22.42920))
        path.close()
        path.move(to: NSPoint(x: 3.59920, y: 18.30380))
        path.curve(to: NSPoint(x: 3.06460, y: 15.29010),
                   controlPoint1: NSPoint(x: 3.07210, y: 17.39364), controlPoint2: NSPoint(x: 2.88272, y: 16.32603))
        path.line(to: NSPoint(x: 3.20660, y: 15.37530))
        path.line(to: NSPoint(x: 7.98960, y: 18.13350))
        path.curve(to: NSPoint(x: 8.37990, y: 18.23956),
                   controlPoint1: NSPoint(x: 8.10794, y: 18.20294), controlPoint2: NSPoint(x: 8.24269, y: 18.23956))
        path.curve(to: NSPoint(x: 8.77020, y: 18.13350),
                   controlPoint1: NSPoint(x: 8.51711, y: 18.23956), controlPoint2: NSPoint(x: 8.65186, y: 18.20294))
        path.line(to: NSPoint(x: 14.61300, y: 14.76500))
        path.line(to: NSPoint(x: 14.61300, y: 17.09740))
        path.curve(to: NSPoint(x: 14.60343, y: 17.13195),
                   controlPoint1: NSPoint(x: 14.61245, y: 17.10949), controlPoint2: NSPoint(x: 14.60918, y: 17.12130))
        path.curve(to: NSPoint(x: 14.57980, y: 17.15890),
                   controlPoint1: NSPoint(x: 14.59768, y: 17.14259), controlPoint2: NSPoint(x: 14.58960, y: 17.15181))
        path.line(to: NSPoint(x: 9.74000, y: 19.95020))
        path.curve(to: NSPoint(x: 6.32901, y: 20.39735),
                   controlPoint1: NSPoint(x: 8.70752, y: 20.54498), controlPoint2: NSPoint(x: 7.47991, y: 20.70591))
        path.curve(to: NSPoint(x: 3.59920, y: 18.30380),
                   controlPoint1: NSPoint(x: 5.17811, y: 20.08878), controlPoint2: NSPoint(x: 4.19565, y: 19.33531))
        path.line(to: NSPoint(x: 3.59920, y: 18.30380))
        path.close()
        path.move(to: NSPoint(x: 2.34080, y: 7.89560))
        path.curve(to: NSPoint(x: 4.70630, y: 5.92280),
                   controlPoint1: NSPoint(x: 2.87156, y: 6.97959), controlPoint2: NSPoint(x: 3.70987, y: 6.28044))
        path.line(to: NSPoint(x: 4.70630, y: 11.60000))
        path.curve(to: NSPoint(x: 4.80778, y: 11.99127),
                   controlPoint1: NSPoint(x: 4.70450, y: 11.73714), controlPoint2: NSPoint(x: 4.73955, y: 11.87229))
        path.curve(to: NSPoint(x: 5.09420, y: 12.27650),
                   controlPoint1: NSPoint(x: 4.87600, y: 12.11026), controlPoint2: NSPoint(x: 4.97493, y: 12.20877))
        path.line(to: NSPoint(x: 10.90860, y: 15.63080))
        path.line(to: NSPoint(x: 8.88850, y: 16.79930))
        path.curve(to: NSPoint(x: 8.85300, y: 16.80814),
                   controlPoint1: NSPoint(x: 8.87757, y: 16.80510), controlPoint2: NSPoint(x: 8.86538, y: 16.80814))
        path.curve(to: NSPoint(x: 8.81750, y: 16.79930),
                   controlPoint1: NSPoint(x: 8.84062, y: 16.80814), controlPoint2: NSPoint(x: 8.82843, y: 16.80510))
        path.line(to: NSPoint(x: 3.98720, y: 14.01280))
        path.curve(to: NSPoint(x: 1.89557, y: 11.28248),
                   controlPoint1: NSPoint(x: 2.95665, y: 13.41544), controlPoint2: NSPoint(x: 2.20403, y: 12.43300))
        path.curve(to: NSPoint(x: 2.34080, y: 7.87200),
                   controlPoint1: NSPoint(x: 1.58710, y: 10.13195), controlPoint2: NSPoint(x: 1.74731, y: 8.90478))
        path.line(to: NSPoint(x: 2.34080, y: 7.89560))
        path.close()
        path.move(to: NSPoint(x: 18.93710, y: 11.75140))
        path.line(to: NSPoint(x: 13.10380, y: 8.36400))
        path.line(to: NSPoint(x: 15.11920, y: 7.20000))
        path.curve(to: NSPoint(x: 15.15470, y: 7.19116),
                   controlPoint1: NSPoint(x: 15.13013, y: 7.19420), controlPoint2: NSPoint(x: 15.14232, y: 7.19116))
        path.curve(to: NSPoint(x: 15.19020, y: 7.20000),
                   controlPoint1: NSPoint(x: 15.16708, y: 7.19116), controlPoint2: NSPoint(x: 15.17927, y: 7.19420))
        path.line(to: NSPoint(x: 20.02050, y: 9.99130))
        path.curve(to: NSPoint(x: 22.07632, y: 12.58333),
                   controlPoint1: NSPoint(x: 21.01009, y: 10.56231), controlPoint2: NSPoint(x: 21.74565, y: 11.48971))
        path.curve(to: NSPoint(x: 21.80112, y: 15.88019),
                   controlPoint1: NSPoint(x: 22.40700, y: 13.67695), controlPoint2: NSPoint(x: 22.30853, y: 14.85653))
        path.curve(to: NSPoint(x: 19.34400, y: 18.09550),
                   controlPoint1: NSPoint(x: 21.29370, y: 16.90385), controlPoint2: NSPoint(x: 20.41457, y: 17.69646))
        path.line(to: NSPoint(x: 19.34400, y: 12.41830))
        path.curve(to: NSPoint(x: 19.22874, y: 12.03096),
                   controlPoint1: NSPoint(x: 19.33981, y: 12.28139), controlPoint2: NSPoint(x: 19.30009, y: 12.14789))
        path.curve(to: NSPoint(x: 18.93700, y: 11.75130),
                   controlPoint1: NSPoint(x: 19.15739, y: 11.91403), controlPoint2: NSPoint(x: 19.05684, y: 11.81764))
        path.line(to: NSPoint(x: 18.93710, y: 11.75140))
        path.close()
        path.move(to: NSPoint(x: 20.94780, y: 8.72830))
        path.line(to: NSPoint(x: 20.80580, y: 8.64310))
        path.line(to: NSPoint(x: 16.03230, y: 5.86130))
        path.curve(to: NSPoint(x: 15.63960, y: 5.75458),
                   controlPoint1: NSPoint(x: 15.91324, y: 5.79143), controlPoint2: NSPoint(x: 15.77765, y: 5.75458))
        path.curve(to: NSPoint(x: 15.24690, y: 5.86130),
                   controlPoint1: NSPoint(x: 15.50155, y: 5.75458), controlPoint2: NSPoint(x: 15.36596, y: 5.79143))
        path.line(to: NSPoint(x: 9.40900, y: 9.22970))
        path.line(to: NSPoint(x: 9.40900, y: 6.89740))
        path.curve(to: NSPoint(x: 9.41474, y: 6.86274),
                   controlPoint1: NSPoint(x: 9.40776, y: 6.88554), controlPoint2: NSPoint(x: 9.40974, y: 6.87357))
        path.curve(to: NSPoint(x: 9.43740, y: 6.83590),
                   controlPoint1: NSPoint(x: 9.41974, y: 6.85192), controlPoint2: NSPoint(x: 9.42757, y: 6.84264))
        path.line(to: NSPoint(x: 14.26770, y: 4.04930))
        path.curve(to: NSPoint(x: 17.54743, y: 3.56904),
                   controlPoint1: NSPoint(x: 15.25966, y: 3.47785), controlPoint2: NSPoint(x: 16.43327, y: 3.30599))
        path.curve(to: NSPoint(x: 20.26602, y: 5.46549),
                   controlPoint1: NSPoint(x: 18.66159, y: 3.83209), controlPoint2: NSPoint(x: 19.63440, y: 4.51071))
        path.curve(to: NSPoint(x: 20.94790, y: 8.70930),
                   controlPoint1: NSPoint(x: 20.89764, y: 6.42027), controlPoint2: NSPoint(x: 21.14164, y: 7.58102))
        path.line(to: NSPoint(x: 20.94780, y: 8.72830))
        path.close()
        path.move(to: NSPoint(x: 8.30650, y: 12.86300))
        path.line(to: NSPoint(x: 6.28650, y: 11.69920))
        path.curve(to: NSPoint(x: 6.26118, y: 11.67508),
                   controlPoint1: NSPoint(x: 6.27639, y: 11.69312), controlPoint2: NSPoint(x: 6.26775, y: 11.68488))
        path.curve(to: NSPoint(x: 6.24850, y: 11.64250),
                   controlPoint1: NSPoint(x: 6.25462, y: 11.66528), controlPoint2: NSPoint(x: 6.25029, y: 11.65416))
        path.line(to: NSPoint(x: 6.24850, y: 6.07420))
        path.curve(to: NSPoint(x: 7.47315, y: 2.99458),
                   controlPoint1: NSPoint(x: 6.24999, y: 4.92960), controlPoint2: NSPoint(x: 6.68820, y: 3.82763))
        path.curve(to: NSPoint(x: 10.47458, y: 1.58915),
                   controlPoint1: NSPoint(x: 8.25809, y: 2.16154), controlPoint2: NSPoint(x: 9.33209, y: 1.65863))
        path.curve(to: NSPoint(x: 13.62420, y: 2.62050),
                   controlPoint1: NSPoint(x: 11.61706, y: 1.51967), controlPoint2: NSPoint(x: 12.74409, y: 1.88872))
        path.line(to: NSPoint(x: 13.48220, y: 2.70100))
        path.line(to: NSPoint(x: 8.70400, y: 5.45900))
        path.curve(to: NSPoint(x: 8.41749, y: 5.74768),
                   controlPoint1: NSPoint(x: 8.58508, y: 5.52874), controlPoint2: NSPoint(x: 8.48633, y: 5.62824))
        path.curve(to: NSPoint(x: 8.31130, y: 6.14030),
                   controlPoint1: NSPoint(x: 8.34864, y: 5.86712), controlPoint2: NSPoint(x: 8.31204, y: 6.00244))
        path.line(to: NSPoint(x: 8.30650, y: 12.86300))
        path.close()
        path.move(to: NSPoint(x: 9.40410, y: 10.49760))
        path.line(to: NSPoint(x: 12.00610, y: 8.99780))
        path.line(to: NSPoint(x: 14.61300, y: 10.49760))
        path.line(to: NSPoint(x: 14.61300, y: 13.49700))
        path.line(to: NSPoint(x: 12.01560, y: 14.99670))
        path.line(to: NSPoint(x: 9.40890, y: 13.49700))
        path.line(to: NSPoint(x: 9.40410, y: 10.49760))
        path.close()
        return path
    }

    private static func anthropic() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 17.30410, y: 3.54100))
        path.line(to: NSPoint(x: 13.63230, y: 3.54100))
        path.line(to: NSPoint(x: 20.32830, y: 20.45900))
        path.line(to: NSPoint(x: 24.00000, y: 20.45900))
        path.line(to: NSPoint(x: 17.30410, y: 3.54100))
        path.close()
        path.move(to: NSPoint(x: 6.69590, y: 3.54100))
        path.line(to: NSPoint(x: 0.00000, y: 20.45900))
        path.line(to: NSPoint(x: 3.74420, y: 20.45900))
        path.line(to: NSPoint(x: 5.11350, y: 16.90630))
        path.line(to: NSPoint(x: 12.11870, y: 16.90630))
        path.line(to: NSPoint(x: 13.48800, y: 20.45910))
        path.line(to: NSPoint(x: 17.23220, y: 20.45910))
        path.line(to: NSPoint(x: 10.53630, y: 3.54090))
        path.line(to: NSPoint(x: 6.69590, y: 3.54100))
        path.close()
        path.move(to: NSPoint(x: 6.32470, y: 13.76420))
        path.line(to: NSPoint(x: 8.61610, y: 7.81860))
        path.line(to: NSPoint(x: 10.90750, y: 13.76420))
        path.line(to: NSPoint(x: 6.32470, y: 13.76420))
        path.close()
        return path
    }

}
