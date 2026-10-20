#if DEBUG
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Development aid, active only in Debug builds.
///
/// `--snapshot /path/out.png [--dark]` renders the main window's layer tree to a PNG and quits.
/// `--render-canvas /path/out.png [--dark]` renders `KeyboardsView` alone via ImageRenderer and quits.
/// `--render-popover /path/out.png [--dark] [--popover-state off|muted|timed] [--popover-profile mx-red]` renders the menu bar popover and quits.
/// `--export-sounds /path/dir` writes every loaded sound as a WAV file and quits.
/// `--section settings` opens the window on that sidebar section (with any of the above).
/// `--dump-views 1` prints the window's AppKit view tree with frames and quits.
/// `--stress-sounds 300` plays that many random keys 12 ms apart from two threads, then quits.
/// `--render-cheatsheet /path/out.png [--dark]` renders the shortcut cheat sheet and quits.
/// `--render-hud /path/out.png [--dark] [--hud-action toggleMute|toggleSound|nextKeyboard|volumeUp]` renders the shortcut HUD and quits.
/// `--mic-report 1` prints which processes CoreAudio reports as running audio input, and quits.
/// `--test-shortcuts 1` runs every shortcut action through the hot key router and prints the state.
/// `--test-keymap 1` prints how sample key codes are classified and whether Input Monitoring is granted.
/// `--latency-report 1` prints the audio device's buffer and output latency, then quits.
/// `--test-soundpacks 1` prints whether each profile's pack loaded and how many sounds it has.
/// All work without screen-recording permission. Every flag takes a value because AppKit
/// pairs `-key value` arguments; a stray word would be opened as a document and no window shows.
enum DebugSnapshot {
    /// `--section keyboards|shortcuts|settings` opens the window on that sidebar section.
    static var initialSection: SidebarSection? {
        value(after: "--section", in: CommandLine.arguments).flatMap { raw in
            SidebarSection.allCases.first { $0.rawValue.lowercased() == raw.lowercased() }
        }
    }

    static func runIfRequested() {
        let args = CommandLine.arguments
        let dark = args.contains("--dark")
        if dark { NSApp.appearance = NSAppearance(named: .darkAqua) }

        if let path = value(after: "--render-canvas", in: args) {
            let state = AppState(defaults: UserDefaults(suiteName: "debug-snapshot")!)
            renderAndQuit(to: path, dark: dark) {
                KeyboardsView()
                    .environmentObject(state)
                    .frame(width: 700, height: 548)
            }
            return
        }

        if let path = value(after: "--render-popover", in: args) {
            let defaults = UserDefaults(suiteName: "debug-popover")!
            defaults.removePersistentDomain(forName: "debug-popover")
            let state = AppState(defaults: defaults, engine: nil)
            if let id = value(after: "--popover-profile", in: args),
               let profile = KeyboardProfile.all.first(where: { $0.id == id }) {
                state.selectedProfile = profile
            }
            switch value(after: "--popover-state", in: args) {
            case "off": state.isEnabled = false
            case "muted": state.mute()
            case "timed": state.mute(for: 15 * 60)
            default: break
            }
            let host = NSHostingView(rootView: PopoverView { _ in }.environmentObject(state))
            host.frame.size = host.fittingSize
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                defer { NSApp.terminate(nil) }
                render(host, in: window, to: path)
            }
            return
        }

        if let dir = value(after: "--export-sounds", in: args) {
            defer { NSApp.terminate(nil) }
            do {
                try SoundEngine().exportSounds(to: URL(fileURLWithPath: dir))
                print("sounds: wrote \(dir)")
            } catch {
                FileHandle.standardError.write(Data("sounds: \(error)\n".utf8))
            }
            return
        }

        if let count = value(after: "--stress-sounds", in: args).flatMap(Int.init) {
            let engine = SoundEngine()
            print("stress: render rate \(engine.sampleRate) Hz")
            var played = 0
            // Half the keys play from a background thread, like the key listener does,
            // so the engine's locking is exercised from two threads at once.
            let listenerLike = DispatchQueue(label: "stress.listener", qos: .userInteractive)
            Timer.scheduledTimer(withTimeInterval: 0.012, repeats: true) { timer in
                MainActor.assumeIsolated {
                    engine.play(KeyType.allCases.randomElement()!, profile: KeyboardProfile.all.randomElement()!)
                    listenerLike.async {
                        engine.play(KeyType.allCases.randomElement()!, profileID: KeyboardProfile.all.randomElement()!.id)
                    }
                    played += 1
                    if played >= count {
                        timer.invalidate()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            print("stress: played \(played)")
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
            return
        }

        if let path = value(after: "--render-cheatsheet", in: args) {
            let defaults = UserDefaults(suiteName: "debug-cheatsheet")!
            defaults.removePersistentDomain(forName: "debug-cheatsheet")
            let store = ShortcutStore(defaults: defaults)
            renderAndQuit(to: path, dark: dark) {
                ShortcutCheatSheet()
                    .environmentObject(store)
                    .environmentObject(WindowRouter())
            }
            return
        }

        if let path = value(after: "--render-hud", in: args) {
            let state = AppState(defaults: UserDefaults(suiteName: "debug-hud")!, engine: nil)
            let store = ShortcutStore(defaults: UserDefaults(suiteName: "debug-hud")!)
            let action = value(after: "--hud-action", in: args).flatMap(ShortcutAction.init(rawValue:)) ?? .toggleMute
            switch action {
            case .toggleMute: state.mute()
            case .toggleSound: state.isEnabled = false
            default: break
            }
            let hud = HUDController(reduceMotion: { true })
            hud.show(HUDContent(after: action, isEnabled: state.isEnabled, isMuted: state.isMuted,
                                profile: state.selectedProfile, volume: 0.6, combo: store.combo(for: action)))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                defer { NSApp.terminate(nil) }
                guard let panel = hud.panel, let view = panel.contentView else { return }
                render(view, in: panel, to: path)
            }
            return
        }

        if args.contains("--mic-report") {
            defer { NSApp.terminate(nil) }
            if let processes = MicrophoneMonitor.processes() {
                print("mic: process API available; \(processes.count) processes known to CoreAudio")
                for p in processes where p.isRunningInput {
                    let note = MicrophoneMonitor.isSystemListener(p) ? " (system listener, ignored)" : ""
                    print("mic: running input: \(p.bundleID ?? "?") (pid \(p.pid))\(note)")
                }
                print("mic: in use = \(MicrophoneMonitor.anyRunningInput(processes, ownPID: getpid()))")
            } else {
                print("mic: process API unavailable (needs macOS 14.2); auto-mute is unsupported here")
            }
            return
        }

        if args.contains("--test-shortcuts") {
            defer { NSApp.terminate(nil) }
            let defaults = UserDefaults(suiteName: "debug-shortcuts")!
            defaults.removePersistentDomain(forName: "debug-shortcuts")
            let state = AppState(defaults: defaults, engine: nil)
            let store = ShortcutStore(defaults: defaults)
            let center = HotKeyCenter(appState: state, shortcuts: store, hud: HUDController(), router: WindowRouter())
            func report(_ label: String) {
                print("\(label): enabled=\(state.isEnabled) muted=\(state.isMuted) profile=\(state.selectedProfile.id) volume=\(String(format: "%.2f", state.volume))")
            }
            report("start")
            center.handle(id: 0); report("toggleSound")
            center.handle(id: 0); report("toggleSound")
            center.handle(id: 1); report("toggleMute")
            center.handle(id: 1); report("toggleMute")
            center.handle(id: 2); report("nextKeyboard")
            center.handle(id: 3); report("previousKeyboard")
            center.handle(id: 3); report("previousKeyboard")
            center.handle(id: 4); report("volumeUp")
            center.handle(id: 5); report("volumeDown")
            center.handle(id: 99); report("unknown id")

            // Conflict handling: giving toggleSound the mute shortcut must unassign toggleMute.
            store.set(ShortcutAction.toggleMute.defaultCombo, for: .toggleSound)
            print("conflict: toggleSound=\(store.combo(for: .toggleSound)?.display ?? "nil") toggleMute=\(store.combo(for: .toggleMute)?.display ?? "nil")")
            let reloaded = ShortcutStore(defaults: defaults)
            print("reloaded: toggleMute=\(reloaded.combo(for: .toggleMute)?.display ?? "nil")")
            store.restoreDefaults()
            print("restored: toggleMute=\(store.combo(for: .toggleMute)?.display ?? "nil")")
            return
        }

        if args.contains("--latency-report") {
            defer { NSApp.terminate(nil) }
            let engine = SoundEngine()
            let deviceRate = engine.outputDeviceSampleRate
            print(String(format: "latency: device %.0f Hz, IO buffer %u frames (%.2f ms), output latency %.2f ms, audio path worst case %.2f ms",
                         deviceRate, engine.ioBufferFrames,
                         deviceRate > 0 ? Double(engine.ioBufferFrames) / deviceRate * 1000 : 0,
                         engine.outputLatency * 1000, engine.audioPathLatencyMs))
            return
        }

        if args.contains("--test-soundpacks") {
            defer { NSApp.terminate(nil) }
            let engine = SoundEngine()
            for profile in KeyboardProfile.all {
                let source = engine.loadedProfileIDs.contains(profile.id) ? "loaded" : "MISSING"
                let counts = KeyType.allCases.map { "\($0.rawValue) \(engine.variationCount(profileID: profile.id, key: $0))" }
                print("soundpack: \(profile.id) \(source): \(counts.joined(separator: ", "))")
            }
            return
        }

        if args.contains("--test-keymap") {
            defer { NSApp.terminate(nil) }
            let samples: [(String, Int)] = [
                ("A", kVK_ANSI_A), ("5", kVK_ANSI_5), ("Space", kVK_Space), ("Return", kVK_Return),
                ("KeypadEnter", kVK_ANSI_KeypadEnter), ("Delete", kVK_Delete), ("FwdDelete", kVK_ForwardDelete),
                ("Shift", kVK_Shift), ("RightCommand", kVK_RightCommand), ("Fn", kVK_Function),
                ("Escape", kVK_Escape), ("Left", kVK_LeftArrow), ("F5", kVK_F5),
                ("K", kVK_ANSI_K), ("S", kVK_ANSI_S), ("Backslash", kVK_ANSI_Backslash),
            ]
            for (name, code) in samples {
                let location = KeyboardLayout.location(for: code).map { "row \($0.row) col \($0.column)" } ?? "not drawn"
                print("keymap: \(name) -> \(KeyListener.keyType(for: Int64(code)).rawValue), \(location)")
            }
            print("keymap: hasAccess=\(KeyListener.hasAccess)")
            return
        }

        if args.contains("--dump-views") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                defer { NSApp.terminate(nil) }
                guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView else { return }
                dump(view, depth: 0)
                fflush(stdout)
            }
            return
        }

        guard let path = value(after: "--snapshot", in: args) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            defer { NSApp.terminate(nil) }
            // Render the frame view (content + title bar + toolbar) when available.
            guard let window = NSApp.windows.first(where: { $0.isVisible }),
                  let view = window.contentView?.superview ?? window.contentView else {
                FileHandle.standardError.write(Data("snapshot: no window\n".utf8))
                return
            }
            render(view, in: window, to: path)
        }
    }

    /// Renders a SwiftUI view on the window background at 2x with ImageRenderer, writes it
    /// as a PNG and quits. For views without materials; those need a real window (`render`).
    private static func renderAndQuit(to path: String, dark: Bool, @ViewBuilder content: @escaping () -> some View) {
        DispatchQueue.main.async {
            defer { NSApp.terminate(nil) }
            let view = content()
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            write(renderer.nsImage, to: path)
        }
    }

    /// Draws a view's layer tree over the window background and writes it as a PNG.
    private static func render(_ view: NSView, in window: NSWindow, to path: String) {
        guard let layer = view.layer else {
            FileHandle.standardError.write(Data("snapshot: view has no layer\n".utf8))
            return
        }
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
        if view.isFlipped || layer.isGeometryFlipped {
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        write(image, to: path)
    }

    private static func dump(_ view: NSView, depth: Int) {
        let name = String(describing: type(of: view))
        let f = view.frame
        var extra = ""
        if let control = view as? NSControl, !control.stringValue.isEmpty { extra = " \"\(control.stringValue)\"" }
        if let text = view as? NSTextField { extra = " \"\(text.stringValue)\"" }
        let line = String(repeating: "  ", count: depth) + "\(name) \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))\(extra)\(view.isHidden ? " hidden" : "")\n"
        print(line, terminator: "")
        for sub in view.subviews { dump(sub, depth: depth + 1) }
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    private static func write(_ image: NSImage?, to path: String) {
        guard let image, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("snapshot: could not render\n".utf8))
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("snapshot: wrote \(path)")
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
        }
    }
}
#endif
