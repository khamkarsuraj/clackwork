import AppKit
import SwiftUI

/// A stylized 60% keyboard drawn from the selected profile's palette.
/// Keys the animator reports as down are drawn sunk, so held modifiers and chords show correctly.
///
/// The keys are Core Animation layers, not SwiftUI shapes, and presses reach them directly
/// from the animator. A SwiftUI animation re-renders the whole window on every frame, and
/// even a plain SwiftUI state change lays out the whole window; together they cost 10-30%
/// CPU while typing (issue #33). A layer animation runs in the window server instead.
struct KeyboardIllustration: View {
    typealias KeyID = KeyboardLayout.Location

    let palette: KeyboardProfile.Palette
    let animator: KeyPressAnimator

    var body: some View {
        KeyboardKeys(palette: palette, animator: animator)
            .frame(height: KeyboardKeysView.boardHeight)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.body)
                    .shadow(color: .black.opacity(0.2), radius: 11, y: 8)
            }
            .accessibilityHidden(true)
    }
}

private struct KeyboardKeys: NSViewRepresentable {
    let palette: KeyboardProfile.Palette
    let animator: KeyPressAnimator

    func makeNSView(context: Context) -> KeyboardKeysView { KeyboardKeysView() }

    func updateNSView(_ view: KeyboardKeysView, context: Context) {
        view.update(palette: palette)
        view.update(pressedKeys: animator.pressedKeys)
        animator.onChange = { [weak view] keys in view?.update(pressedKeys: keys) }
    }

    static func dismantleNSView(_ view: KeyboardKeysView, coordinator: ()) {
        view.isDetached = true
    }
}

/// One layer per key cap, with a darker lip along its bottom edge. A pressed key sinks and
/// its lip thins, animated by Core Animation.
final class KeyboardKeysView: NSView {
    typealias KeyID = KeyboardIllustration.KeyID

    private static let layout = KeyboardLayout.rows
    private static let gap: CGFloat = 3
    private static let keyHeight: CGFloat = 19
    private static let cornerRadius: CGFloat = 3
    static let pressDepth: CGFloat = 2
    static let lipHeight: CGFloat = 3
    static let pressedLipHeight: CGFloat = 1
    private static let pressDuration: CFTimeInterval = 0.07

    /// Rows are a fixed height, so the board's height is known without measuring it.
    static var boardHeight: CGFloat {
        let rows = CGFloat(layout.count)
        return keyHeight * rows + gap * (rows - 1)
    }

    private enum Role { case cap, modifier, accent }

    private struct Key {
        let cap: CALayer
        let lip: CALayer
        let units: Double
        let role: Role
    }

    private var keys: [KeyID: Key] = [:]
    private var palette: KeyboardProfile.Palette?
    private var pressedKeys: Set<KeyID> = []
    /// Set once SwiftUI removes the view; a stale animator callback is then ignored.
    var isDetached = false

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        let lipColor = NSColor.black.withAlphaComponent(0.2).cgColor
        for (rowIndex, row) in Self.layout.enumerated() {
            for (columnIndex, units) in row.enumerated() {
                let id = KeyID(row: rowIndex, column: columnIndex)
                let cap = CALayer()
                cap.cornerRadius = Self.cornerRadius
                cap.masksToBounds = true
                let lip = CALayer()
                lip.backgroundColor = lipColor
                cap.addSublayer(lip)
                layer?.addSublayer(cap)
                keys[id] = Key(cap: cap, lip: lip, units: units,
                               role: Self.role(for: id, units: units, rowCount: row.count))
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(palette: KeyboardProfile.Palette) {
        guard palette != self.palette else { return }
        self.palette = palette
        withoutAnimation {
            for key in keys.values { key.cap.backgroundColor = color(for: key.role, in: palette) }
        }
    }

    /// Sinks newly pressed keys and raises released ones, animated.
    func update(pressedKeys: Set<KeyID>) {
        guard !isDetached else { return }
        let changed = pressedKeys.symmetricDifference(self.pressedKeys)
        self.pressedKeys = pressedKeys
        guard !changed.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.pressDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        for id in changed {
            guard let key = keys[id] else { continue }
            applyPress(to: key, isDown: pressedKeys.contains(id))
        }
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutKeys()
    }

    override func layout() {
        super.layout()
        layoutKeys()
    }

    private func layoutKeys() {
        withoutAnimation {
            var y: CGFloat = 0
            for (rowIndex, row) in Self.layout.enumerated() {
                let totalUnits = row.reduce(0, +)
                let unitWidth = (bounds.width - Self.gap * CGFloat(row.count - 1)) / totalUnits
                var x: CGFloat = 0
                for columnIndex in row.indices {
                    let id = KeyID(row: rowIndex, column: columnIndex)
                    guard let key = keys[id] else { continue }
                    let width = unitWidth * key.units
                    // Bounds and position, not frame: frame is undefined while a press transform is set.
                    key.cap.bounds = CGRect(x: 0, y: 0, width: width, height: Self.keyHeight)
                    key.cap.position = CGPoint(x: x + width / 2, y: y + Self.keyHeight / 2)
                    applyPress(to: key, isDown: pressedKeys.contains(id))
                    x += width + Self.gap
                }
                y += Self.keyHeight + Self.gap
            }
        }
    }

    /// The cap and lip layers drawn for a key, for tests.
    func layers(for id: KeyID) -> (cap: CALayer, lip: CALayer)? {
        keys[id].map { ($0.cap, $0.lip) }
    }

    private func applyPress(to key: Key, isDown: Bool) {
        key.cap.setAffineTransform(isDown ? CGAffineTransform(translationX: 0, y: Self.pressDepth) : .identity)
        let lipHeight = isDown ? Self.pressedLipHeight : Self.lipHeight
        let size = key.cap.bounds.size
        key.lip.frame = CGRect(x: 0, y: size.height - lipHeight, width: size.width, height: lipHeight)
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    private func color(for role: Role, in palette: KeyboardProfile.Palette) -> CGColor {
        let color: Color
        switch role {
        case .cap: color = palette.cap
        case .modifier: color = palette.modifier
        case .accent: color = palette.accent
        }
        return NSColor(color).cgColor
    }

    private static func role(for id: KeyID, units: Double, rowCount: Int) -> Role {
        let isAccent = (id.row == 0 && id.column == 0) || (id.row == 2 && id.column == rowCount - 1)
        if isAccent { return .accent }
        return units != 1 && id != .space ? .modifier : .cap
    }
}

#Preview {
    let animator = KeyPressAnimator()
    return KeyboardIllustration(palette: KeyboardProfile.defaultProfile.light, animator: animator)
        .frame(width: 340)
        .padding(40)
        .onAppear { animator.press(.space, reduceMotion: false) }
}
