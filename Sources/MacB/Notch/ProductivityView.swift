import SwiftUI

/// Compact reusable content for a future Tools tab or Settings section.
struct ProductivityView: View {
    @ObservedObject var aiActivity: AIActivityService
    @ObservedObject var systemMonitor: SystemMonitorService
    @ObservedObject var keyboardCleaning: KeyboardCleaningService

    var body: some View {
        VStack(spacing: 8) {
            ForEach(visibleActivities) { activity in
                statusRow(symbol: activity.kind.symbol, title: activity.kind.rawValue,
                          detail: "\(activity.source) · \(activity.elapsedText)", tint: .orange)
            }
            HStack(spacing: 7) {
                metric("CPU", value: "\(Int(systemMonitor.snapshot.cpuUsage))%")
                metric("RAM", value: byteRatio(systemMonitor.snapshot.usedMemory, systemMonitor.snapshot.totalMemory))
                if let battery = systemMonitor.snapshot.batteryPercent {
                    metric("Pil", value: "\(Int(battery))%")
                }
            }
            if keyboardCleaning.isActive {
                Button(action: keyboardCleaning.stop) {
                    Label(keyboardCleaning.remainingSeconds > 0 ? "Kilidi aç · \(keyboardCleaning.remainingSeconds) sn" : "Kilidi aç",
                          systemImage: "keyboard.badge.ellipsis")
                        .font(.system(size: 10, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 32)
                        .background(.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            } else {
                Button { keyboardCleaning.start(duration: 60) } label: {
                    Label("Klavyeyi 1 dakika kilitle", systemImage: "keyboard")
                        .font(.system(size: 10, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 32)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
            if let error = keyboardCleaning.errorMessage {
                Text(error).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(2)
            }
        }
    }

    private var visibleActivities: [AIActivity] {
        AIAssistantKind.allCases.compactMap { kind in
            aiActivity.activities.first(where: { $0.kind == kind })
        }
    }

    private func statusRow(symbol: String, title: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 30, height: 30).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail).font(.system(size: 9)).foregroundStyle(.white.opacity(0.42))
            }
            Spacer()
        }.padding(8).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.38))
        }.frame(maxWidth: .infinity).frame(height: 42).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
    }

    private func byteRatio(_ used: UInt64, _ total: UInt64) -> String {
        guard total > 0 else { return "—" }
        return "\(Int(Double(used) / Double(total) * 100))%"
    }
}
