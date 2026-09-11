import MacBCore
import SwiftUI

/// The scan animation in the notch: a MacB face, not Apple's.
///
/// Three states, one shape. Scanning sweeps a line down the outline, success
/// snaps the outline shut around a tick, failure shakes once. Reduce Motion
/// keeps every state but drops the movement.
struct IslandFaceScanView: View {
    let phase: FaceScanPhase
    var instruction: String = "Karşıya bak"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = 0
    @State private var shake: CGFloat = 0

    private var tint: Color {
        switch phase {
        case .failure: return MacBDesign.IslandToken.destructive
        default: return MacBDesign.IslandToken.accent
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            outline
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacBDesign.IslandToken.primaryText)
                Text(detail).font(.system(size: 10))
                    .foregroundStyle(MacBDesign.IslandToken.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .offset(x: shake)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
        .onChange(of: phaseKey) { _, _ in react() }
        .onAppear { react() }
    }

    private var phaseKey: String {
        switch phase {
        case .idle: return "idle"
        case .scanning: return "scanning"
        case .success: return "success"
        case .failure: return "failure"
        }
    }

    private var title: String {
        switch phase {
        case .idle: return "Hazır"
        case .scanning: return "Yüzüne bakılıyor"
        case .success(let message): return message
        case .failure(let message): return message
        }
    }

    private var detail: String {
        switch phase {
        case .scanning: return instruction
        case .success: return "Açıldı."
        case .failure: return "Touch ID ile devam edebilirsin."
        case .idle: return ""
        }
    }

    private var outline: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(tint.opacity(0.30), lineWidth: 1.5)
                .frame(width: 30, height: 30)
            corners
            switch phase {
            case .scanning:
                Capsule()
                    .fill(tint)
                    .frame(width: 22, height: 2)
                    .offset(y: sweep)
                    .shadow(color: tint.opacity(0.7), radius: 5)
            case .success:
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
            case .failure:
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
            case .idle:
                Image(systemName: "faceid")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(tint.opacity(0.6))
            }
        }
        .frame(width: 34, height: 34)
    }

    /// Four brackets, the way a viewfinder frames a subject.
    private var corners: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Bracket()
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 11, height: 11)
                    .rotationEffect(.degrees(Double(index) * 90))
                    .offset(x: index == 0 || index == 3 ? -10 : 10,
                            y: index < 2 ? -10 : 10)
            }
        }
    }

    private func react() {
        switch phase {
        case .scanning:
            sweep = -11
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { sweep = 11 }
        case .failure:
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.12, dampingFraction: 0.25)) { shake = 6 }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.4).delay(0.12)) { shake = 0 }
        default:
            sweep = 0
            shake = 0
        }
    }
}

private struct Bracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
