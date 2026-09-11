import AppKit
import Combine

/// A single countdown owned by the island. It keeps running while the panel is closed,
/// because the collapsed indicator is the reason the timer exists.
@MainActor final class TimerService: ObservableObject {
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published var selectedMinutes: Double = 5

    static let presets: [Int] = [5, 10, 25]
    /// Ruler range in minutes. The reference wraps past two hours back to zero.
    static let maximumMinutes: Double = 120
    /// One full turn of the ruler. The extra step keeps 120 and 0 a label apart instead of colliding.
    static let rulerSpan: Double = 125

    private var ticker: Timer?
    private var deadline: Date?

    var isActive: Bool { isRunning || remaining > 0 }

    var progress: Double {
        guard total > 0 else { return 0 }
        return max(0, min(1, 1 - remaining / total))
    }

    var remainingText: String { Self.format(remaining) }

    var selectionText: String { Self.format(selectedMinutes * 60) }

    static func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds % 60) }
        return String(format: "%d:%02d", minutes, seconds % 60)
    }

    func start(minutes: Double? = nil) {
        let requested = max(1.0 / 60, minutes ?? selectedMinutes)
        total = requested * 60
        remaining = total
        deadline = Date().addingTimeInterval(total)
        isRunning = true
        schedule()
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        deadline = nil
        ticker?.invalidate()
        ticker = nil
    }

    func resume() {
        guard !isRunning, remaining > 0 else { return }
        deadline = Date().addingTimeInterval(remaining)
        isRunning = true
        schedule()
    }

    func cancel() {
        ticker?.invalidate()
        ticker = nil
        deadline = nil
        isRunning = false
        remaining = 0
        total = 0
    }

    private func schedule() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        guard let deadline else { return }
        remaining = max(0, deadline.timeIntervalSinceNow)
        guard remaining <= 0 else { return }
        finish()
    }

    private func finish() {
        ticker?.invalidate()
        ticker = nil
        self.deadline = nil
        isRunning = false
        remaining = 0
        NSSound(named: "Glass")?.play()
    }
}
