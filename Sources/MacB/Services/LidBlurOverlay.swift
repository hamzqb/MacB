import AppKit
import MacBCore

/// Blurs the whole built-in screen while the lid is closing.
///
/// Nothing is captured, recorded or read: the panes are ordinary windows whose
/// material blurs whatever the window server has already drawn behind them, the
/// same mechanism a sidebar uses. So there is no Screen Recording permission and
/// no pixel of the user's screen ever reaches MacB.
///
/// Only the built-in display is covered. Closing the lid with an external
/// monitor attached is how people work in clamshell, and blurring the monitor
/// they are about to keep using would be vandalism.
///
/// The panes are transparent to the mouse throughout, and a watchdog tears
/// everything down if the hinge stops reporting, so a stalled sensor can never
/// leave somebody with a screen they cannot see through.
@MainActor final class LidBlurOverlay {
    private var panes: [NSWindow] = []
    private var screen: NSScreen?
    private var watchdog: Timer?
    private var lastProgress: Double = 0

    /// How long the blur may sit at one value before it is assumed to be stuck.
    /// Long enough for a slow, deliberate close; short enough to be a blink.
    private static let stallTimeout: TimeInterval = 8

    var isVisible: Bool { !panes.isEmpty }

    /// Follows the hinge. Zero takes everything down.
    func apply(progress: Double) {
        guard progress > 0.001 else { return hide() }
        guard let screen = Self.builtInScreen() else { return hide() }
        if panes.isEmpty || self.screen != screen { build(on: screen) }

        for (index, pane) in panes.enumerated() {
            pane.alphaValue = LidScreenBlur.layerAlpha(index, progress: progress)
        }

        if abs(progress - lastProgress) > 0.001 { armWatchdog() }
        lastProgress = progress
    }

    func hide() {
        watchdog?.invalidate(); watchdog = nil
        for pane in panes { pane.orderOut(nil) }
        panes = []; screen = nil; lastProgress = 0
    }

    // MARK: - Panes

    private func build(on screen: NSScreen) {
        hide()
        self.screen = screen
        var previous: NSWindow?
        for _ in 0..<LidScreenBlur.layerCount {
            let window = Self.makePane(on: screen)
            window.alphaValue = 0
            // Ordered explicitly rather than by luck: a pane only deepens the
            // blur if it sits above the one it is meant to be blurring.
            if let previous {
                window.order(.above, relativeTo: previous.windowNumber)
            } else {
                window.orderFront(nil)
            }
            previous = window
            panes.append(window)
        }
    }

    private static func makePane(on screen: NSScreen) -> NSWindow {
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

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: screen.frame.size))
        effect.autoresizingMask = [.width, .height]
        effect.material = .fullScreenUI
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        window.contentView = effect
        return window
    }

    /// The lid's own display. It is the only one that goes away when the lid shuts.
    private static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(number) != 0
        }
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
