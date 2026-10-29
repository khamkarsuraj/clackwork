import AppKit

/// The menu bar icon: the app icon's sound-wave T, with a thin slash while muted and dimmed while off (FR-14).
/// Drawn as a template image so macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    enum State: Equatable {
        case on, muted, off
        /// Paused for an excluded app in front: drawn like muted, described differently.
        case paused

        /// Off wins over muted: a muted app that is turned off shows as off. Muted by the
        /// user or automatically (microphone in use) wins over paused for an app.
        init(isEnabled: Bool, isMuted: Bool, isAutoMuted: Bool = false, isPausedForApp: Bool = false) {
            if !isEnabled {
                self = .off
            } else if isMuted || isAutoMuted {
                self = .muted
            } else if isPausedForApp {
                self = .paused
            } else {
                self = .on
            }
        }

        /// No sound is coming in either state; the glyph is the same.
        var showsSlash: Bool { self == .muted || self == .paused }

        var accessibilityDescription: String {
            switch self {
            case .on: "Thlick"
            case .muted: "Thlick, muted"
            case .paused: "Thlick, paused for the app in front"
            case .off: "Thlick, sound off"
            }
        }
    }

    static func image(for state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            // Template images are tinted by alpha, so "off" is the same glyph drawn faint.
            c.setAlpha(state == .off ? 0.4 : 1)
            c.beginTransparencyLayer(auxiliaryInfo: nil)
            drawWaveT(in: c)
            if state.showsSlash { drawSlash(in: c) }
            c.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityDescription
        return image
    }

    /// The app icon's T made of sound-wave bars: a symmetric wave for the crossbar and the center bar
    /// running down as the stem. The app icon has seven bars; at 18 pt the outer dots turn into specks,
    /// so this keeps five. Coordinates are points in the 18 × 18 box, y up.
    private static func drawWaveT(in c: CGContext) {
        c.setFillColor(.black)
        let width: CGFloat = 2, crossbarY: CGFloat = 12.5
        // (center x, center y, height) for each bar, left to right.
        let bars: [(CGFloat, CGFloat, CGFloat)] = [
            (3, crossbarY, 3), (6, crossbarY, 5), (9, 9.25, 14.5), (12, crossbarY, 5), (15, crossbarY, 3),
        ]
        for (x, y, height) in bars {
            c.addPath(CGPath(roundedRect: CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height),
                             cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
        }
        c.fillPath()
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
