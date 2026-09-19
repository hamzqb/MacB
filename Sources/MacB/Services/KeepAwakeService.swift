import Combine
import Foundation
import IOKit.pwr_mgt
import MacBCore

/// Keeps the display, and so the Mac, from going to sleep for a while.
///
/// One power assertion, the same kind `caffeinate -d` takes, released when the
/// time is up, when it is turned off, or when MacB quits — macOS also drops it
/// by itself if MacB dies. It does not stop a closed lid from sleeping the Mac
/// and does not touch any system setting.
@MainActor final class KeepAwakeService: ObservableObject {
    static let shared = KeepAwakeService()

    @Published private(set) var isActive = false
    /// When it ends, or nil for "until turned off".
    @Published private(set) var endDate: Date?
    /// Ticks once a minute while active so the countdown redraws.
    @Published private(set) var now = Date()

    private var assertion: IOPMAssertionID = 0
    private var ticker: Timer?

    var remainingText: String { KeepAwakeDuration.remainingText(until: endDate, now: now) }

    /// Starts, or restarts with a new length. Zero minutes means no end.
    @discardableResult
    func start(minutes: Int) -> Bool {
        if !isActive {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "MacB: Uyanık tut" as CFString, &id)
            guard result == kIOReturnSuccess else { return false }
            assertion = id
            isActive = true
        }
        now = Date()
        endDate = minutes > 0 ? now.addingTimeInterval(TimeInterval(minutes * 60)) : nil
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        return true
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        if isActive { IOPMAssertionRelease(assertion) }
        assertion = 0
        isActive = false
        endDate = nil
    }

    /// Turns it on for `minutes`, or off if it is already on.
    @discardableResult
    func toggle(minutes: Int) -> Bool {
        if isActive { stop(); return false }
        return start(minutes: minutes)
    }

    private func tick() {
        now = Date()
        if let endDate, now >= endDate { stop() }
    }
}
