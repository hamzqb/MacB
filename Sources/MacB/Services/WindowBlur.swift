import AppKit

/// Blurs whatever the window server has already drawn behind a window, at a
/// radius MacB chooses.
///
/// `NSVisualEffectView` is the supported way to blur a backdrop, but its radius
/// is fixed by the material: a sidebar's blur is a sidebar's blur, and stacking
/// panes only tints, it does not deepen. A lid closing needs the opposite — a
/// radius that climbs with the hinge, from nothing to unreadable — so the only
/// honest options are the window server's own control or a fake.
///
/// The window server exposes it, and every dock replacement and menu bar tool on
/// the Mac uses it, but it is not in a public header. So it is looked up by name
/// at runtime instead of linked: if a future macOS drops it, `isAvailable` goes
/// false, every call becomes a no-op, and the caller falls back to a material.
/// MacB never fails to launch over it.
///
/// This reads nothing. It asks the compositor to blur pixels it already owns;
/// no frame ever reaches MacB, and no Screen Recording permission is involved.
enum WindowBlur {
    private typealias MainConnectionID = @convention(c) () -> UInt32
    private typealias SetBlurRadius = @convention(c) (UInt32, Int, Int) -> Int32

    private static let symbols: (connection: UInt32, setRadius: SetBlurRadius)? = {
        // RTLD_DEFAULT: CoreGraphics is already linked, so this is a lookup in
        // the images that are loaded, not a dlopen of a private framework.
        let handle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let connectionSymbol = dlsym(handle, "CGSMainConnectionID"),
              let radiusSymbol = dlsym(handle, "CGSSetWindowBackgroundBlurRadius") else { return nil }
        let connection = unsafeBitCast(connectionSymbol, to: MainConnectionID.self)()
        guard connection != 0 else { return nil }
        return (connection, unsafeBitCast(radiusSymbol, to: SetBlurRadius.self))
    }()

    /// Whether the window server will take a radius from us on this macOS.
    static var isAvailable: Bool { symbols != nil }

    /// Sets the blur radius behind `window`, in points. Zero removes it.
    ///
    /// The window has to be non-opaque with a background that is not fully
    /// clear, or the compositor has nothing to composite the blur into.
    @discardableResult
    static func apply(radius: Double, to window: NSWindow) -> Bool {
        guard let symbols else { return false }
        let clamped = Int(max(0, min(200, radius.rounded())))
        return symbols.setRadius(symbols.connection, window.windowNumber, clamped) == 0
    }

    static func remove(from window: NSWindow) {
        guard let symbols else { return }
        _ = symbols.setRadius(symbols.connection, window.windowNumber, 0)
    }
}
