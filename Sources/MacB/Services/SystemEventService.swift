import AppKit
import Combine
import Foundation
import IOKit.ps
import MacBCore

/// Watches the few system changes the island reacts to.
///
/// Nothing here polls in a loop: the power source publishes its changes, so
/// MacB listens and stays idle in between. Only the power state is read.
@MainActor final class SystemEventService: ObservableObject {
    /// The event the island should show right now, if any.
    @Published private(set) var event: IslandEvent?

    private var powerSource: CFRunLoopSource?
    private var dismissTask: Task<Void, Never>?
    private var isRunning = false

    /// Set once the first reading is taken, so starting MacB does not announce
    /// the state the Mac was already in.
    private var lastCharging: Bool?
    private var lastLowWarning: Date?

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startPower()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopPower()
        dismissTask?.cancel()
        dismissTask = nil
        event = nil
    }

    /// Publishes an event from elsewhere, such as a track change the media
    /// service noticed.
    func present(_ candidate: IslandEvent) {
        if let current = event, !candidate.outranks(current) { return }
        event = candidate
        dismissTask?.cancel()
        dismissTask = Task { [weak self, duration = candidate.duration] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self, self.event == candidate else { return }
            self.event = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        event = nil
    }

    // MARK: - Power

    private func startPower() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<SystemEventService>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in service.powerChanged() }
        }, context)?.takeRetainedValue() else { return }
        powerSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        lastCharging = Self.powerState().isCharging
    }

    private func stopPower() {
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
            self.powerSource = nil
        }
    }

    private func powerChanged() {
        let state = Self.powerState()
        defer { lastCharging = state.isCharging }
        if let lastCharging, lastCharging != state.isCharging {
            present(state.isCharging ? .charging(state.percent) : .unplugged(state.percent))
            return
        }
        // A low battery is worth saying once, not every time the reading ticks.
        guard let percent = state.percent, percent <= 15, !state.isCharging else { return }
        if let lastLowWarning, Date().timeIntervalSince(lastLowWarning) < 900 { return }
        lastLowWarning = Date()
        present(.batteryLow(percent))
    }

    private static func powerState() -> (percent: Int?, isCharging: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, false)
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int
            let max = description[kIOPSMaxCapacityKey] as? Int
            let charging = (description[kIOPSIsChargingKey] as? Bool) == true
            let percent: Int? = {
                guard let current, let max, max > 0 else { return nil }
                return Int((Double(current) / Double(max) * 100).rounded())
            }()
            return (percent, charging)
        }
        return (nil, false)
    }
}
