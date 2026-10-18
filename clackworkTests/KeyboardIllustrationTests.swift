import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import clackwork

/// Issue #33: the on-screen keyboard is drawn with one Core Animation layer per key.
@MainActor
struct KeyboardIllustrationTests {
    typealias KeyID = KeyboardLayout.Location

    private let width: CGFloat = 312
    private let palette = KeyboardProfile.defaultProfile.light

    private func makeView() -> KeyboardKeysView {
        let view = KeyboardKeysView()
        view.setFrameSize(NSSize(width: width, height: KeyboardKeysView.boardHeight))
        view.update(palette: palette)
        return view
    }

    private var allKeys: [KeyID] {
        KeyboardLayout.rows.enumerated().flatMap { row, keys in
            keys.indices.map { KeyID(row: row, column: $0) }
        }
    }

    @Test func drawsEveryKeyOfTheLayout() {
        let view = makeView()
        #expect(allKeys.count == 61)
        for id in allKeys { #expect(view.layers(for: id) != nil) }
    }

    @Test func eachRowFillsTheBoardWidth() throws {
        let view = makeView()
        for (row, keys) in KeyboardLayout.rows.enumerated() {
            var total: CGFloat = 0
            for column in keys.indices {
                total += try #require(view.layers(for: KeyID(row: row, column: column))).cap.bounds.width
            }
            total += 3 * CGFloat(keys.count - 1)
            #expect(abs(total - width) < 0.01, "row \(row)")
        }
    }

    @Test func pressedKeySinksAndItsLipThins() throws {
        let view = makeView()
        view.update(pressedKeys: [.space])

        let space = try #require(view.layers(for: .space))
        #expect(space.cap.affineTransform() == CGAffineTransform(translationX: 0, y: KeyboardKeysView.pressDepth))
        #expect(space.lip.frame.height == KeyboardKeysView.pressedLipHeight)
        #expect(space.lip.frame.maxY == space.cap.bounds.height)

        let other = try #require(view.layers(for: KeyID(row: 1, column: 1)))
        #expect(other.cap.affineTransform() == .identity)
        #expect(other.lip.frame.height == KeyboardKeysView.lipHeight)
    }

    @Test func releasedKeyComesBackUp() throws {
        let view = makeView()
        view.update(pressedKeys: [.space])
        view.update(pressedKeys: [])
        let space = try #require(view.layers(for: .space))
        #expect(space.cap.affineTransform() == .identity)
        #expect(space.lip.frame.height == KeyboardKeysView.lipHeight)
    }

    /// Core Animation skips implicit animations on layers that were never drawn, so this test
    /// puts the view in an on-screen window and lets one frame render first, as in the app.
    @Test func pressAnimatesOnlyTheChangedKeyWithTheDesignedTiming() async throws {
        let view = makeView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        window.orderFrontRegardless()
        defer { window.close() }
        CATransaction.flush()
        try await Task.sleep(nanoseconds: 200_000_000)

        view.update(pressedKeys: [.space])
        let space = try #require(view.layers(for: .space))
        let other = try #require(view.layers(for: KeyID(row: 1, column: 1)))
        let animation = try #require(space.cap.animation(forKey: "transform") as? CABasicAnimation)
        #expect(animation.duration == 0.07)
        #expect(animation.timingFunction == CAMediaTimingFunction(name: .easeOut))
        #expect(other.cap.animationKeys() == nil)
    }

    @Test func detachedViewIgnoresPresses() throws {
        let view = makeView()
        view.isDetached = true
        view.update(pressedKeys: [.space])
        #expect(try #require(view.layers(for: .space)).cap.affineTransform() == .identity)
    }

    @Test func capsUseThePaletteColors() throws {
        let view = makeView()
        let escape = try #require(view.layers(for: KeyID(row: 0, column: 0)))
        let tab = try #require(view.layers(for: KeyID(row: 1, column: 0)))
        let q = try #require(view.layers(for: KeyID(row: 1, column: 1)))
        #expect(escape.cap.backgroundColor == NSColor(palette.accent).cgColor)
        #expect(tab.cap.backgroundColor == NSColor(palette.modifier).cgColor)
        #expect(q.cap.backgroundColor == NSColor(palette.cap).cgColor)
    }
}
