import MacBCore
import SwiftUI

/// The stats section: processor, memory and GPU over network and disk, each a
/// running line of the last minute or so, sampled once a second while the
/// section is open and not at all otherwise.
struct IslandStatsView: View {
    @ObservedObject var monitor: SystemMonitorService

    private static let cpuColor = Color(red: 0.25, green: 0.56, blue: 1)
    private static let memoryColor = Color(red: 0.30, green: 0.85, blue: 0.39)
    private static let gpuColor = Color(red: 0.75, green: 0.35, blue: 0.95)
    private static let downColor = Color(red: 1, green: 0.62, blue: 0.04)
    private static let upColor = Color(red: 1, green: 0.27, blue: 0.23)
    private static let readColor = Color(red: 0.39, green: 0.82, blue: 1)
    private static let writeColor = Color(red: 1, green: 0.84, blue: 0.04)

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                percentCard("CPU", symbol: "cpu", color: Self.cpuColor,
                            value: monitor.snapshot.cpuUsage / 100, series: monitor.cpuHistory)
                percentCard("Bellek", symbol: "memorychip", color: Self.memoryColor,
                            value: memoryFraction, series: monitor.memoryHistory)
                percentCard("GPU", symbol: "display", color: Self.gpuColor,
                            value: monitor.gpuHistory.last, series: monitor.gpuHistory)
            }
            .frame(height: 146)
            HStack(spacing: 10) {
                rateCard("Ağ", symbol: "network", first: ("↓", Self.downColor, monitor.networkInHistory),
                         second: ("↑", Self.upColor, monitor.networkOutHistory))
                rateCard("Disk", symbol: "internaldrive", first: ("R", Self.readColor, monitor.diskReadHistory),
                         second: ("W", Self.writeColor, monitor.diskWriteHistory))
            }
            .frame(height: 116)
        }
        .frame(height: IslandGeometry.statsHeight, alignment: .top)
    }

    private var memoryFraction: Double {
        let total = Double(monitor.snapshot.totalMemory)
        return total > 0 ? Double(monitor.snapshot.usedMemory) / total : 0
    }

    private func percentCard(_ title: String, symbol: String, color: Color,
                             value: Double?, series: [Double]) -> some View {
        StatCard {
            VStack(spacing: 6) {
                StatTitle(title: title, symbol: symbol, color: color)
                Text(value.map { String(format: "%.1f%%", $0 * 100) } ?? "—")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
                    .contentTransition(.numericText())
                    .motion(.smooth(duration: 0.3), value: value)
                    .frame(maxWidth: .infinity)
                AreaChart(series: series, maximum: 1, color: color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) yüzde \(Int(((value ?? 0) * 100).rounded()))")
    }

    private func rateCard(_ title: String, symbol: String,
                          first: (label: String, color: Color, series: [Double]),
                          second: (label: String, color: Color, series: [Double])) -> some View {
        let peak = max(1, (first.series + second.series).max() ?? 1)
        return StatCard {
            VStack(spacing: 6) {
                StatTitle(title: title, symbol: symbol, color: first.color)
                HStack(spacing: 8) {
                    Text("\(first.label) \(Self.rate(first.series.last))").foregroundStyle(first.color)
                    Circle().fill(.white.opacity(0.3)).frame(width: 3, height: 3)
                    Text("\(second.label) \(Self.rate(second.series.last))").foregroundStyle(second.color)
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                MirroredChart(up: first.series, down: second.series, maximum: peak,
                              upColor: first.color, downColor: second.color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(first.label) \(Self.rate(first.series.last)), \(second.label) \(Self.rate(second.series.last))")
    }

    static func rate(_ bytesPerSecond: Double?) -> String {
        guard let value = bytesPerSecond else { return "—" }
        let megabytes = value / 1_000_000
        if megabytes >= 1 { return String(format: "%.1f MB/s", megabytes) }
        return String(format: "%.0f KB/s", value / 1_000)
    }
}

private struct StatCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

private struct StatTitle: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(title).foregroundStyle(.white.opacity(0.62))
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .semibold))
    }
}

/// A line over a soft fill, newest on the right.
private struct AreaChart: View {
    let series: [Double]
    let maximum: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let points = ChartPoints.make(series, maximum: maximum, size: proxy.size, capacity: SystemMonitorService.statsHistoryLength)
            ZStack {
                ChartPoints.area(points, baseline: proxy.size.height)
                    .fill(LinearGradient(colors: [color.opacity(0.38), color.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                ChartPoints.line(points)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// Two series sharing a baseline: one above it, one mirrored below.
private struct MirroredChart: View {
    let up: [Double]
    let down: [Double]
    let maximum: Double
    let upColor: Color
    let downColor: Color

    var body: some View {
        GeometryReader { proxy in
            let half = CGSize(width: proxy.size.width, height: proxy.size.height / 2)
            let capacity = SystemMonitorService.statsHistoryLength
            let top = ChartPoints.make(up, maximum: maximum, size: half, capacity: capacity)
            let bottom = ChartPoints.make(down, maximum: maximum, size: half, capacity: capacity)
                .map { CGPoint(x: $0.x, y: proxy.size.height - $0.y) }
            ZStack {
                Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
                    .position(x: proxy.size.width / 2, y: half.height)
                ChartPoints.area(top, baseline: half.height)
                    .fill(upColor.opacity(0.18))
                ChartPoints.line(top).stroke(upColor, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                ChartPoints.area(bottom, baseline: half.height)
                    .fill(downColor.opacity(0.18))
                ChartPoints.line(bottom).stroke(downColor, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private enum ChartPoints {
    /// The line spans the whole width, newest reading at the right edge.
    static func make(_ series: [Double], maximum: Double, size: CGSize, capacity: Int) -> [CGPoint] {
        guard !series.isEmpty, size.width > 0, maximum > 0 else { return [] }
        let values = series.count == 1 ? [series[0], series[0]] : Array(series.suffix(capacity))
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let fraction = min(1, max(0, value / maximum))
            return CGPoint(x: step * CGFloat(index), y: size.height - 2 - (size.height - 4) * fraction)
        }
    }

    static func line(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
        }
    }

    static func area(_ points: [CGPoint], baseline: CGFloat) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: baseline))
            points.forEach { path.addLine(to: $0) }
            path.addLine(to: CGPoint(x: last.x, y: baseline))
            path.closeSubpath()
        }
    }
}
