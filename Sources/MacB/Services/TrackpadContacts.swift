import AppKit
import MacBCore

/// How many fingers are on the trackpad, and nothing else.
///
/// AppKit will not say. Touch events reach a view only while the application is
/// frontmost, and MacB is an accessory that is never frontmost, so the public
/// route is closed for a gesture that has to work over somebody else's window.
/// `MultitouchSupport` is the framework every trackpad tool on the Mac uses for
/// this, and it is looked up by name at runtime rather than linked — exactly
/// like the window server's blur — so a macOS that drops it turns this feature
/// off instead of stopping MacB from launching.
///
/// Only the finger count is read. The callback hands it over as a plain integer
/// argument; the frame of contact positions beside it is never touched, because
/// its layout is private and a wrong guess reads whatever is next in memory.
/// Nothing is recorded, nothing is stored, and where the fingers are is never
/// known.
@MainActor final class TrackpadContacts {
    /// The one monitor, because the callback the framework takes is a plain C
    /// function pointer with nowhere to put a reference to an instance.
    static let shared = TrackpadContacts()

    /// Called on the main actor when the count changes, with the new count.
    var onFrame: ((Int, Double) -> Void)?

    private typealias DeviceRef = UnsafeMutableRawPointer
    private typealias ContactCallback = @convention(c) (DeviceRef?, UnsafeMutableRawPointer?,
                                                        Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias RegisterCallback = @convention(c) (DeviceRef, ContactCallback) -> Void
    private typealias UnregisterCallback = @convention(c) (DeviceRef, ContactCallback) -> Void
    private typealias DeviceStart = @convention(c) (DeviceRef, Int32) -> Void
    private typealias DeviceStop = @convention(c) (DeviceRef) -> Void

    private struct Symbols {
        let createList: CreateList
        let register: RegisterCallback
        let unregister: UnregisterCallback
        let start: DeviceStart
        let stop: DeviceStop
    }

    private static let symbols: Symbols? = {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }
        guard let createList = load("MTDeviceCreateList", as: CreateList.self),
              let register = load("MTRegisterContactFrameCallback", as: RegisterCallback.self),
              let unregister = load("MTUnregisterContactFrameCallback", as: UnregisterCallback.self),
              let start = load("MTDeviceStart", as: DeviceStart.self),
              let stop = load("MTDeviceStop", as: DeviceStop.self) else { return nil }
        return Symbols(createList: createList, register: register, unregister: unregister,
                       start: start, stop: stop)
    }()

    /// Whether this macOS still answers the question at all.
    static var isSupported: Bool { symbols != nil }

    private var devices: [DeviceRef] = []
    private var isRunning = false
    private var wakeObserver: NSObjectProtocol?

    /// Whether a trackpad was actually found, for the settings window to say so
    /// rather than leaving somebody toggling a switch that cannot work.
    private(set) var deviceCount = 0

    func start() {
        guard !isRunning, let symbols = Self.symbols else { return }
        guard let list = symbols.createList()?.takeRetainedValue() else { return }
        let count = CFArrayGetCount(list)
        for index in 0..<count {
            guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
            let ref = DeviceRef(mutating: device)
            symbols.register(ref, trackpadContactCallback)
            symbols.start(ref, 0)
            devices.append(ref)
        }
        deviceCount = devices.count
        isRunning = !devices.isEmpty
        observeWake()
    }

    func stop() {
        guard let symbols = Self.symbols else { return }
        for device in devices {
            symbols.stop(device)
            symbols.unregister(device, trackpadContactCallback)
        }
        devices = []
        deviceCount = 0
        isRunning = false
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    /// A trackpad that has been asleep comes back as a different device, and the
    /// callback registered against the old one is never called again. Waking up
    /// with a gesture that silently stopped working is worse than not having it.
    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isRunning else { return }
                    self.stop()
                    self.start()
                }
            }
    }

    fileprivate func report(fingers: Int, at time: Double) {
        onFrame?(fingers, time)
    }
}

/// The trackpad's own thread calls this many times a second. It does the least
/// it possibly can: reads one integer and hands it to the main actor.
private let trackpadContactCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
                                                     Int32, Double, Int32) -> Int32 = { _, _, fingers, timestamp, _ in
    let count = Int(fingers)
    Task { @MainActor in
        TrackpadContacts.shared.report(fingers: count, at: timestamp)
    }
    return 0
}
