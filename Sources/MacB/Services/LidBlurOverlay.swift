import AppKit
import QuartzCore
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
    private var lastProgress: Double = 0
    private var lastRadius: Double = -1

    /// How long the blur may sit at one value before it is assumed to be stuck.
    /// Long enough for a slow, deliberate close; short enough to be a blink.
    private static let stallTimeout: TimeInterval = 8

    var isVisible: Bool { !panes.isEmpty || dim != nil }

    /// Whether the compositor is doing the blurring, rather than stacked materials.
    ///
    /// Off by default, and deliberately. The window server accepts the radius —
    /// the call returns success — but on this macOS it only actually blurs for a
    /// window that was put up in an earlier run loop pass than the one that asks
    /// for the blur, and the overlay builds and asks in the same pass because
    /// the hinge gives it no warning. Ordering the window front, flushing the
    /// transaction and re-sending the radius all fail to change that; the same
    /// sequence in a standalone window blurs perfectly.
    ///
    /// Until that is understood rather than guessed at, the lid keeps the
    /// stacked materials it has always had, and the real path is here behind a
    /// switch so it can be finished without a rebuild for every attempt.
    static var usesRealBlur: Bool {
        WindowBlur.isAvailable && !reduceTransparency
            && ProcessInfo.processInfo.environment["MACB_REAL_BLUR"] == "1"
    }

    /// Somebody who has asked the system for less transparency has asked not to
    /// be shown a blurred version of what is behind something. They still get
    /// the screen going dark as the lid comes down, which is the part that
    /// carries the meaning; they do not get frosted glass over their work.
    private static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// Follows the hinge. Zero takes everything down.
    func apply(progress: Double) {
        guard progress > 0.001 else { return hide() }
        guard let screen = Self.builtInScreen(), let id = Self.displayID(of: screen) else { return hide() }
        if screenID != id { build(on: screen, id: id) }

        if Self.usesRealBlur {
            let radius = LidScreenBlur.blurRadius(progress: progress)
            // The window server is asked for a new radius only when the number
            // it would receive has actually changed, so a hinge reporting the
            // same angle sixty times a second does not become sixty round trips.
            if let pane = panes.first, abs(radius - lastRadius) >= 1 {
                WindowBlur.apply(radius: radius, to: pane)
                lastRadius = radius
            }
        } else {
            for (index, pane) in panes.enumerated() {
                pane.alphaValue = LidScreenBlur.layerAlpha(index, progress: progress)
            }
        }
        dim?.alphaValue = LidScreenBlur.dimAlpha(progress: progress)

        if abs(progress - lastProgress) > 0.001 { armWatchdog() }
        lastProgress = progress
    }

    func hide() {
        watchdog?.invalidate(); watchdog = nil
        for pane in panes {
            WindowBlur.remove(from: pane)
            pane.orderOut(nil)
        }
        dim?.orderOut(nil)
        panes = []; dim = nil; screenID = nil; lastProgress = 0; lastRadius = -1
    }

    // MARK: - Panes

    private func build(on screen: NSScreen, id: CGDirectDisplayID) {
        hide()
        screenID = id

        if Self.usesRealBlur {
            let window = Self.makeWindow(on: screen)
            // The compositor needs something to composite the blur into: a
            // window with a fully clear background has no surface to blur onto.
            window.backgroundColor = NSColor(white: 0, alpha: 0.001)
            window.orderFront(nil)
            // The window server will not attach a blur to a window it has not
            // finished putting up, and it says nothing when it declines: the
            // call reports success and the screen stays perfectly sharp. The
            // flush is what makes the window real before a radius is asked for.
            window.displayIfNeeded()
            CATransaction.flush()
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
        guard Self.usesRealBlur else { return }
        let shade = Self.makeWindow(on: screen)
        shade.backgroundColor = .black
        shade.alphaValue = 0
        if let top = panes.last {
            shade.order(.above, relativeTo: top.windowNumber)
        } else {
            shade.orderFront(nil)
        }
        dim = shade
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
    /// removes itself if the hinge stops moving without ever reaching the end.
    private func armWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: Self.stallTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }
}
