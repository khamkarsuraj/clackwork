import AppKit

/// The menu bar icon: a solid Cherry MX switch, with a thin slash while muted and dimmed while off (FR-14).
/// Drawn as a template image so macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    enum State: Equatable {
        case on, muted, off

        /// Off wins over muted: a muted app that is turned off shows as off. Muted by the
        /// user or automatically (microphone in use) looks the same: no sound is coming.
        init(isEnabled: Bool, isMuted: Bool, isAutoMuted: Bool = false) {
            self = !isEnabled ? .off : (isMuted || isAutoMuted ? .muted : .on)
        }

        var accessibilityDescription: String {
            switch self {
            case .on: "Clackwork"
            case .muted: "Clackwork, muted"
            case .off: "Clackwork, sound off"
            }
        }
    }

    static func image(for state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            // Template images are tinted by alpha, so "off" is the same glyph drawn faint.
            c.setAlpha(state == .off ? 0.4 : 1)
            c.beginTransparencyLayer(auxiliaryInfo: nil)
            drawSwitch(in: c)
            if state == .muted { drawSlash(in: c) }
            c.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityDescription
        return image
    }

    /// A Cherry MX switch in the style of the AirPods symbols: soft solid parts, with a thin
    /// clear gap where one sits in front of another. Coordinates are points in the 18 × 18 box, y up.
    private static func drawSwitch(in c: CGContext) {
        c.setFillColor(.black)

        // Pins, the same length on both sides, tucked under the housing.
        for x: CGFloat in [5.5, 12.5] {
            c.addPath(CGPath(roundedRect: CGRect(x: x - 0.8, y: 1.4, width: 1.6, height: 3.6),
                             cornerWidth: 0.8, cornerHeight: 0.8, transform: nil))
        }
        c.fillPath()

        // Lower housing and the sloped top housing, split by a thin gap.
        c.addPath(roundedPolygon([(2, 4.2), (16, 4.2), (16, 8.4), (2, 8.4)], radius: 1.4))
        c.addPath(roundedPolygon([(2.2, 9.2), (15.8, 9.2), (12.9, 12.5), (5.1, 12.5)], radius: 1.1))
        c.fillPath()

        // Cross stem in front of the housing, with a clear outline around it.
        let stem = CGMutablePath()
        stem.addRoundedRect(in: CGRect(x: 8.1, y: 11.4, width: 1.8, height: 5.4), cornerWidth: 0.63, cornerHeight: 0.63)
        stem.addRoundedRect(in: CGRect(x: 6.3, y: 13.8, width: 5.4, height: 1.8), cornerWidth: 0.63, cornerHeight: 0.63)
        c.setBlendMode(.clear)
        c.addPath(stem)
        c.setLineWidth(1.6)
        c.setLineJoin(.round)
        c.strokePath()
        c.setBlendMode(.normal)
        c.addPath(stem)
        c.fillPath()
    }

    /// A closed polygon with every corner rounded, like the soft corners of SF Symbols.
    private static func roundedPolygon(_ points: [(CGFloat, CGFloat)], radius: CGFloat) -> CGPath {
        let corners = points.map { CGPoint(x: $0.0, y: $0.1) }
        let path = CGMutablePath()
        // Start midway along the first edge so every corner, including the first, gets its arc.
        path.move(to: CGPoint(x: (corners[0].x + corners[1].x) / 2, y: (corners[0].y + corners[1].y) / 2))
        for i in 1...corners.count {
            path.addArc(tangent1End: corners[i % corners.count],
                        tangent2End: corners[(i + 1) % corners.count], radius: radius)
        }
        path.closeSubpath()
        return path
    }

    /// A thin diagonal slash, about the weight of the system's `wifi.slash`, with a clear gap
    /// around it so it stays readable over the solid housing.
    private static func drawSlash(in c: CGContext) {
        let from = CGPoint(x: 2.5, y: 15.5), to = CGPoint(x: 15.5, y: 2.5)
        c.setBlendMode(.clear)
        c.setLineWidth(2.6)
        c.strokeLineSegments(between: [from, to])
        c.setBlendMode(.normal)
        c.setLineWidth(1.1)
        c.strokeLineSegments(between: [from, to])
    }
}
