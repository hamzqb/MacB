import Combine
import Foundation
import MacBCore

/// Publishes the hinge angle and what the island should do about it.
///
/// The sensor is cheap to read but not free, so it is polled slowly while the
/// lid is sitting still and quickly while it is moving. Nothing polls at all on
/// a machine without the sensor, or while the feature is switched off.
@MainActor final class LidAngleService: ObservableObject {
    /// 0 while the lid is open, 1 when the island has folded away.
    @Published private(set) var foldProgress: Double = 0
    @Published private(set) var angle: Double?
    /// Raised for a moment when the lid has just been opened from shut.
    let didOpen = PassthroughSubject<Void, Never>()
    /// Raised once as the lid starts going down, so something can be put on
    /// screen to fold. A closed island has nothing to animate.
    let willFold = PassthroughSubject<Void, Never>()

    private let sensor = LidAngleSensor()
    private var tracker = LidFoldTracker()
    private var timer: Timer?
    private var isEnabled = false
    private var lastAngle: Double?
    private var stillReadings = 0

    /// Slow while nothing moves, fast while the hinge is turning.
    private static let restingInterval: TimeInterval = 0.5
    private static let movingInterval: TimeInterval = 1.0 / 30
    /// How many identical readings before dropping back to the slow cadence.
    private static let stillLimit = 12

    var isAvailable: Bool { sensor.isAvailable }
    var diagnostic: String { sensor.diagnostic }

    /// Where the fold starts. Changing it re-reads at once so the settings
    /// slider moves the island while the user is dragging it.
    func setOpenAngle(_ degrees: Double) {
        guard LidFold.clampOpenAngle(degrees) != tracker.openAngle else { return }
        tracker.setOpenAngle(degrees)
        foldProgress = tracker.progress
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled, sensor.isAvailable {
            schedule(interval: Self.restingInterval)
            tick()
        } else {
            timer?.invalidate(); timer = nil
            foldProgress = 0
            angle = nil
        }
    }

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = interval / 4
    }

    private func tick() {
        let reading = sensor.read()
        let event = tracker.update(angle: reading)
        angle = reading
        foldProgress = tracker.progress
        switch event {
        case .opened: didOpen.send()
        case .folding: willFold.send()
        case .none: break
        }

        // A hinge that has not moved for a few readings does not need thirty
        // samples a second; one that just moved almost certainly will again.
        let moved = reading != lastAngle
        lastAngle = reading
        stillReadings = moved ? 0 : stillReadings + 1
        let wantsFast = moved || stillReadings < Self.stillLimit
        let wanted = wantsFast ? Self.movingInterval : Self.restingInterval
        if let timer, abs(timer.timeInterval - wanted) > 0.001 { schedule(interval: wanted) }
    }
}
