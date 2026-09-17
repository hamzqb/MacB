import AppKit
import MacBCore

/// Blurs the whole built-in screen while the lid is closing.
///
/// Nothing is captured, recorded or read. The overlay is an ordinary window and
/// the blur is the compositor's own, applied to pixels it already owns, the same
/// mechanism a sidebar uses. No Screen Recording permission is involved and no
/// pixel of the user's screen ever reaches MacB.
///
/// Where the window server will take a radius from us the picture is blurred
/// once, at a radius that climbs with the hinge, so the fold has a real dial
/// behind it. Where it will not, three stacked materials imitate one, each
/// blurring the one below it; it darkens more than it should, but it is the
/// only way to deepen a fixed radius.
///
/// Only the built-in display is covered. Closing the lid with an external
/// monitor attached is how people work in clamshell, and blurring the monitor
/// they are about to keep using would be vandalism.
///
/// The window is transparent to the mouse throughout, and a watchdog tears
/// everything down if the hinge stops reporting, so a stalled sensor can never
/// leave somebody with a screen they cannot see through.
@MainActor final class LidBlurOverlay {
    /// The one overlay, because its windows have to exist before the run loop
    /// starts and there is only one moment in the program's life like that.
    static let shared = LidBlurOverlay()

    private var panes: [NSWindow] = []
    private var dim: NSWindow?
    /// The display the overlay is built on, by its identifier rather than by the
    /// `NSScreen` object.
    ///
    /// `NSScreen.screens` hands back a fresh array of fresh objects on every
    /// call, so comparing the object to the one from last frame was never equal
    /// and the whole overlay was torn down and rebuilt sixty times a second.
    /// The radius was then being set on a window the compositor had not finished
    /// putting up, and the blur silently did nothing at all.
    private var screenID: CGDirectDisplayID?
    private var watchdog: Timer?
    /// Whether the hinge is still answering. See `LidBlurLiveness`.
    private var liveness = LidBlurLiveness()
    private var lastRadius: Double = -1
    private var isShowing = false

    var isVisible: Bool { isShowing }

    /// Whether the compositor is doing the blurring, rather than stacked materials.
    static var usesRealBlur: Bool { WindowBlur.isAvailable && !reduceTransparency }

    /// Somebody who has asked the system for less transparency has asked not to
    /// be shown a blurred version of what is behind something. They still get
    /// the screen going dark as the lid comes down, which is the part that
    /// carries the meaning; they do not get frosted glass over their work.
    private static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// Builds the windows, while the window server will still give them a blur.
    ///
    /// This has to happen before `NSApplication.run()`, and there is no way
    /// around it. A window created after the run loop starts — in a launch
    /// delegate, in a timer, anywhere — is accepted by the compositor and then
    /// never blurred: `CGSSetWindowBackgroundBlurRadius` returns success and the
    /// screen stays perfectly sharp for the rest of that window's life. Measured
    /// both ways against a striped test pattern; the difference is absolute, not
    /// a matter of degree.
    ///
    /// So the panes are made once, at the very start, kept out of sight, and
    /// brought forward when the hinge moves. The cost is two borderless windows
    /// with no content view sitting ordered-out for the session, which is
    /// nothing; the alternative is a lid that never blurs anything.
    func prepare() {
        guard panes.isEmpty, Self.usesRealBlur else { return }
        guard let screen = Self.builtInScreen(), let id = Self.displayID(of: screen) else { return }
        build(on: screen, id: id)
        for pane in panes { pane.orderOut(nil) }
        dim?.orderOut(nil)
    }

    /// Follows the hinge. Zero takes everything down.
    func apply(progress: Double) {
        guard progress > 0.001 else { return hide() }
        guard let screen = Self.builtInScreen(), let id = Self.displayID(of: screen) else { return hide() }
        if screenID != id {
            build(on: screen, id: id)
        } else if !isShowing {
            show(on: screen)
        }

        if Self.usesRealBlur {
            let radius = LidScreenBlur.blurRadius(progress: progress)
            // The window server is asked for a new radius only when the number
            // it would receive has actually changed, so a hinge reporting the
            // same angle sixty times a second does not become sixty round trips.
            if let pane = panes.first, abs(radius - lastRadius) >= 1 {
                lastRadius = radius
                WindowBlur.apply(radius: radius, to: pane)
            }
        } else {
            for (index, pane) in panes.enumerated() {
                pane.alphaValue = LidScreenBlur.layerAlpha(index, progress: progress)
            }
        }
        dim?.alphaValue = LidScreenBlur.dimAlpha(progress: progress)
        liveness.sawReading(at: ProcessInfo.processInfo.systemUptime)
        armWatchdog()
    }

    /// Takes the blur off the screen without throwing the windows away: they can
    /// never be replaced, so they are only ever ordered out. See `prepare()`.
    func hide() {
        watchdog?.invalidate(); watchdog = nil
        for pane in panes {
            WindowBlur.remove(from: pane)
            pane.orderOut(nil)
        }
        dim?.orderOut(nil)
        isShowing = false; lastRadius = -1
        liveness.reset()
    }

    private func show(on screen: NSScreen) {
        for pane in panes {
            pane.setFrame(screen.frame, display: false)
            pane.orderFront(nil)
        }
        if let dim, let top = panes.last {
            dim.setFrame(screen.frame, display: false)
            dim.order(.above, relativeTo: top.windowNumber)
        }
        isShowing = true
    }

    // MARK: - Panes

    private func build(on screen: NSScreen, id: CGDirectDisplayID) {
        for pane in panes { WindowBlur.remove(from: pane); pane.orderOut(nil) }
        dim?.orderOut(nil)
        panes = []; dim = nil; lastRadius = -1
        screenID = id

        if Self.usesRealBlur {
            let window = Self.makeWindow(on: screen)
            // The compositor needs something to composite the blur into: a
            // window with a fully clear background has no surface to blur onto.
            window.backgroundColor = NSColor(white: 0, alpha: 0.001)
            window.orderFront(nil)
            panes = [window]
        } else {
            var previous: NSWindow?
            for _ in 0..<LidScreenBlur.layerCount {
                let window = Self.makeWindow(on: screen)
                window.alphaValue = 0
                let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
                effect.autoresizingMask = [.width, .height]
                effect.material = .fullScreenUI
                effect.blendingMode = .behindWindow
                effect.state = .active
                effect.appearance = NSAppearance(named: .darkAqua)
                window.contentView = effect
                // Ordered explicitly rather than by luck: a pane only deepens
                // the blur if it sits above the one it is meant to be blurring.
                if let previous {
                    window.order(.above, relativeTo: previous.windowNumber)
                } else {
                    window.orderFront(nil)
                }
                previous = window
                panes.append(window)
            }
        }

        // The dim rides above the blur so it darkens the blurred picture rather
        // than being blurred itself, which would do nothing at all. The stacked
        // materials darken plenty on their own, so it is only for the real path.
        guard Self.usesRealBlur else { isShowing = true; return }
        let shade = Self.makeWindow(on: screen)
        shade.backgroundColor = .black
        shade.alphaValue = 0
        if let top = panes.last {
            shade.order(.above, relativeTo: top.windowNumber)
        } else {
            shade.orderFront(nil)
        }
        dim = shade
        isShowing = true
    }

    private static func makeWindow(on screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false, screen: screen)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.hidesOnDeactivate = false
        // Level with the menu bar so the blur covers it, but under the island,
        // which is the one thing that should stay sharp while it folds away.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                     .stationary, .ignoresCycle]
        window.setFrame(screen.frame, display: false)
        return window
    }

    /// The lid's own display. It is the only one that goes away when the lid shuts.
    private static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = displayID(of: screen) else { return false }
            return CGDisplayIsBuiltin(number) != 0
        }
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    // MARK: - Watchdog

    /// A blur nobody asked to keep is worse than no blur at all, so the overlay
    /// removes itself if the hinge stops reporting altogether.
    ///
    /// One repeating timer that reads a timestamp, rather than a fresh one-shot
    /// per reading: the hinge reports thirty times a second while it moves, and
    /// that was thirty timers created and thrown away every second.
    private func armWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.liveness.isStalled(at: ProcessInfo.processInfo.systemUptime) else { return }
                self.hide()
            }
        }
    }
}
