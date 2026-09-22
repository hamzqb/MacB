import MacBCore
import SwiftUI

/// The ruler timer. Dragging the ruler picks a duration; presets jump to common ones.
struct IslandTimerView: View {
    @ObservedObject var timer: TimerService

    private let minuteSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.regular) {
            HStack(spacing: MacBDesign.Space.comfortable) {
                timerHero
                VStack(alignment: .leading, spacing: MacBDesign.Space.close) {
                    ruler
                    presetRow
                }
            }
        }

    }


    private var timerHero: some View {
        ZStack {
            Circle().stroke(MacBDesign.IslandToken.Fill.base, lineWidth: 6)
            Circle()
                .trim(from: 0, to: timer.isActive ? CGFloat(timer.progress) : CGFloat(max(0.02, timer.selectedMinutes / TimerService.maximumMinutes)))
                .stroke(MacBDesign.IslandToken.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .motion(MacBDesign.Motion.progress, value: timer.progress)
            VStack(spacing: MacBDesign.Space.hair) {
                Text(timer.isActive ? timer.remainingText : timer.selectionText)
                    .font(.system(size: MacBDesign.TypeScale.title, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MacBDesign.IslandToken.primaryText)
                Text(timer.isActive ? (timer.isRunning ? "akıyor" : "durdu") : "seç")
                    .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                    .foregroundStyle(MacBDesign.IslandToken.accent)
            }
        }
        .frame(width: 94, height: 94)
        .accessibilityLabel(timer.isActive ? "Kalan süre \(timer.remainingText)" : "Seçilen süre \(timer.selectionText)")
    }

    private var presetRow: some View {
        HStack(spacing: MacBDesign.Space.snug) {
            ForEach(TimerService.presets, id: \.self) { minutes in
                Button { timer.selectedMinutes = Double(minutes) } label: {
                    Text("\(minutes) dk")
                        .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                        .foregroundStyle(Int(timer.selectedMinutes) == minutes ? Color.black : .white)
                        .padding(.horizontal, MacBDesign.Space.comfortable)
                        .frame(height: MacBDesign.IslandToken.pillHeight)
                        .background(Int(timer.selectedMinutes) == minutes ? Color.white : MacBDesign.IslandToken.navFill,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(minutes) dakika")
            }
            Spacer(minLength: 0)
            primaryAction
        }
    }

    @ViewBuilder private var primaryAction: some View {
        if timer.isActive {
            HStack(spacing: MacBDesign.Space.close) {
                actionPill(timer.isRunning ? "Duraklat" : "Sürdür") {
                    timer.isRunning ? timer.pause() : timer.resume()
                }
                actionPill("İptal", isDestructive: true) { timer.cancel() }
            }
        } else {
            actionPill("Başlat") { timer.start() }
        }
    }

    private func actionPill(_ title: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                .foregroundStyle(isDestructive ? MacBDesign.IslandToken.destructive : MacBDesign.IslandToken.accent)
                .padding(.horizontal, MacBDesign.Space.loose)
                .frame(height: MacBDesign.IslandToken.pillHeight + 2)
                .background((isDestructive ? MacBDesign.IslandToken.destructive : MacBDesign.IslandToken.accent).opacity(0.18),
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var ruler: some View {
        GeometryReader { proxy in
            let center = proxy.size.width / 2
            let visible = Int(ceil(proxy.size.width / minuteSpacing)) + 2
            let start = Int(timer.selectedMinutes) - visible / 2
            ZStack(alignment: .topLeading) {
                ForEach(start...(start + visible), id: \.self) { minute in
                    let wrapped = wrap(minute)
                    let x = center + CGFloat(minute) * minuteSpacing - CGFloat(timer.selectedMinutes) * minuteSpacing
                    tick(minute: wrapped, isMajor: wrapped % 5 == 0)
                        .position(x: x, y: 26)
                }
                Triangle()
                    .fill(MacBDesign.IslandToken.accent)
                    .frame(width: 9, height: 7)
                    .position(x: center, y: 48)
                    .accessibilityHidden(true)
            }
            .clipped()
            // Fade both ends so a half-drawn number never sits against the panel edge.
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.05),
                    .init(color: .black, location: 0.95),
                    .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = -value.translation.width / minuteSpacing
                        timer.selectedMinutes = wrapMinutes(timer.selectedMinutes + delta / 12)
                    }
            )
        }
        .frame(height: 46)
        .accessibilityElement()
        .accessibilityLabel("Süre cetveli")
        .accessibilityValue(timer.selectionText)
        .accessibilityAdjustableAction { direction in
            timer.selectedMinutes = wrapMinutes(timer.selectedMinutes + (direction == .increment ? 1 : -1))
        }
    }

    @ViewBuilder private func tick(minute: Int, isMajor: Bool) -> some View {
        VStack(spacing: MacBDesign.Space.tight) {
            if isMajor {
                Text("\(minute)")
                    .font(.system(size: MacBDesign.TypeScale.micro, weight: minute == Int(timer.selectedMinutes) ? .bold : .regular))
                    .foregroundStyle(minute == Int(timer.selectedMinutes) ? Color.white : MacBDesign.IslandToken.accent)
                    .fixedSize()
            } else {
                Color.clear.frame(height: 12)
            }
            Rectangle()
                .fill(MacBDesign.IslandToken.accent.opacity(isMajor ? 0.9 : 0.4))
                .frame(width: 1, height: isMajor ? 16 : 9)
        }
    }

    /// The ruler wraps past two hours back to zero, as in the reference.
    private func wrap(_ minute: Int) -> Int {
        let span = Int(TimerService.rulerSpan)
        return ((minute % span) + span) % span
    }

    private func wrapMinutes(_ value: Double) -> Double {
        let span = TimerService.rulerSpan
        let wrapped = (value.truncatingRemainder(dividingBy: span) + span).truncatingRemainder(dividingBy: span)
        // The five minutes past two hours are the seam, not a selectable duration.
        return wrapped > TimerService.maximumMinutes ? 0 : wrapped
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
