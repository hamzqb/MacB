import AppKit
import MacBCore
import SwiftUI

/// The widgets the library added on top of the original strip.
///
/// They live in their own file because the first file is already the length of
/// a chapter, not because they are a lesser kind of widget: each one reads from
/// a service the app already runs, so enabling one costs no new permission and
/// no new poll.

// MARK: - Battery

struct BatteryWidget: View {
    @ObservedObject var monitor: SystemMonitorService

    private var percent: Double? { monitor.snapshot.batteryPercent }

    private var tint: Color {
        guard let percent else { return MacBDesign.IslandToken.tertiaryText }
        if monitor.snapshot.isCharging { return Color(nsColor: .systemGreen) }
        if percent <= 15 { return MacBDesign.IslandToken.destructive }
        if percent <= 30 { return Color(nsColor: .systemYellow) }
        return MacBDesign.IslandToken.accent
    }

    var body: some View {
        WidgetCard {
            VStack(alignment: .leading, spacing: 8) {
                WidgetCaption("Pil", trailing: monitor.snapshot.isCharging ? "Şarjda" : nil)
                if let percent {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(percent))")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(MacBDesign.IslandToken.primaryText)
                        Text("%")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                        if monitor.snapshot.isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(tint)
                        }
                        Spacer(minLength: 0)
                    }
                    WidgetMeter(fraction: percent / 100, tint: tint)
                } else {
                    Text("Pil yok")
                        .font(.system(size: 11))
                        .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                }
                if monitor.snapshot.thermalState != .nominal {
                    Text(thermalTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MacBDesign.IslandToken.destructive)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityLabel(percent.map { "Pil yüzde \(Int($0))" } ?? "Pil bilgisi yok")
    }

    private var thermalTitle: String {
        switch monitor.snapshot.thermalState {
        case .fair: return "Isınıyor"
        case .serious: return "Sıcak"
        case .critical: return "Çok sıcak"
        default: return ""
        }
    }
}

// MARK: - Storage

struct StorageWidget: View {
    @ObservedObject var monitor: SystemMonitorService
    @Environment(\.islandWidgetSpan) private var span

    private var isNarrow: Bool { span <= 1 }

    private var used: Double {
        let total = Double(monitor.snapshot.totalDisk)
        guard total > 0 else { return 0 }
        return 1 - Double(monitor.snapshot.availableDisk) / total
    }

    private var tint: Color {
        used >= 0.92 ? MacBDesign.IslandToken.destructive : MacBDesign.IslandToken.accent
    }

    var body: some View {
        WidgetCard {
            VStack(alignment: .leading, spacing: 8) {
                WidgetCaption(isNarrow ? "Disk" : "Depolama")
                if monitor.snapshot.totalDisk > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Self.short(monitor.snapshot.availableDisk))
                            .font(.system(size: isNarrow ? 16 : 19, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(MacBDesign.IslandToken.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if !isNarrow {
                            Text("boş")
                                .font(.system(size: 11))
                                .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    WidgetMeter(fraction: used, tint: tint)
                    Text(isNarrow ? "boş" : "\(Self.short(monitor.snapshot.totalDisk)) toplam")
                        .font(.system(size: 10))
                        .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                        .lineLimit(1)
                } else {
                    Text("Disk okunamadı")
                        .font(.system(size: 11))
                        .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityLabel("Diskte \(Self.short(monitor.snapshot.availableDisk)) boş alan")
    }

    /// Decimal gigabytes, the way Finder reports them, so the two never disagree.
    static func short(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: max(0, bytes))
    }
}

// MARK: - Shelf

struct ShelfWidget: View {
    @ObservedObject var shelf: ShelfStore
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            WidgetCard {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetCaption("Raf", trailing: shelf.items.isEmpty ? nil : "\(shelf.items.count)")
                    if shelf.items.isEmpty {
                        Text("Dosya sürükle")
                            .font(.system(size: 11))
                            .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                    } else {
                        HStack(spacing: 7) {
                            ForEach(shelf.items.prefix(4)) { item in
                                Image(nsImage: icon(for: item))
                                    .resizable()
                                    .frame(width: 26, height: 26)
                                    .opacity(item.isAvailable ? 1 : 0.4)
                            }
                            if shelf.items.count > 4 {
                                Text("+\(shelf.items.count - 4)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Raf, \(shelf.items.count) öğe")
    }

    /// A shelf entry can outlive the file it points at, so the generic document
    /// icon stands in rather than the card losing its row.
    private func icon(for item: ShelfItem) -> NSImage {
        guard let url = item.url else { return NSWorkspace.shared.icon(for: .data) }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Note

struct NotesWidget: View {
    @ObservedObject var note: QuickNoteStore
    @FocusState private var isFocused: Bool

    var body: some View {
        WidgetCard(isActive: isFocused) {
            VStack(alignment: .leading, spacing: 4) {
                WidgetCaption("Not", trailing: note.isEmpty ? nil : "\(note.text.count)")
                // A plain text view rather than a scrolling editor: the card is
                // four lines tall, and a note that needs more than that belongs
                // in a document, not in the island.
                TextField("Aklına geleni yaz", text: $note.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(4, reservesSpace: true)
                    .font(.system(size: 11))
                    .foregroundStyle(MacBDesign.IslandToken.primaryText)
                    .focused($isFocused)
                    .accessibilityLabel("Hızlı not")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !note.isEmpty {
                Button { note.clear() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                        .frame(width: 16, height: 16)
                        .background(MacBDesign.IslandToken.navFill, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .help("Notu temizle")
                .accessibilityLabel("Notu temizle")
            }
        }
    }
}

// MARK: - World clock

struct WorldClockWidget: View {
    @ObservedObject var preferences: Preferences
    @Environment(\.islandWidgetSpan) private var span

    private var isNarrow: Bool { span <= 1 }

    /// The cities offered in the menu. A short, opinionated list beats a picker
    /// with six hundred identifiers in a card this size.
    static let choices: [(identifier: String, name: String)] = [
        ("America/New_York", "New York"),
        ("America/Los_Angeles", "Los Angeles"),
        ("America/Sao_Paulo", "São Paulo"),
        ("Europe/London", "Londra"),
        ("Europe/Berlin", "Berlin"),
        ("Europe/Moscow", "Moskova"),
        ("Asia/Dubai", "Dubai"),
        ("Asia/Tokyo", "Tokyo"),
        ("Asia/Shanghai", "Şanghay"),
        ("Australia/Sydney", "Sidney")
    ]

    private var zone: TimeZone { TimeZone(identifier: preferences.secondaryTimeZone) ?? .current }

    private var name: String {
        Self.choices.first { $0.identifier == preferences.secondaryTimeZone }?.name
            ?? preferences.secondaryTimeZone.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
            ?? preferences.secondaryTimeZone
    }

    var body: some View {
        WidgetCard {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    WidgetCaption(name, trailing: isNarrow ? nil : Self.offsetLabel(zone))
                    Text(Self.time(context.date, in: zone))
                        .font(.system(size: isNarrow ? 18 : 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MacBDesign.IslandToken.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(isNarrow ? Self.shortDay(context.date, in: zone) : Self.day(context.date, in: zone))
                        .font(.system(size: 10))
                        .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                    Spacer(minLength: 0)
                }
            }
        }
        .contextMenu {
            ForEach(Self.choices, id: \.identifier) { choice in
                Button(choice.name) { preferences.secondaryTimeZone = choice.identifier }
            }
        }
        .accessibilityLabel("\(name) saati")
    }

    private static func time(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = zone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func shortDay(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = zone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private static func day(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = zone
        formatter.dateFormat = "d MMM EEEE"
        return formatter.string(from: date)
    }

    /// The difference from where the user actually is, which is the only reason
    /// to keep a second clock at all.
    static func offsetLabel(_ zone: TimeZone) -> String? {
        let seconds = zone.secondsFromGMT() - TimeZone.current.secondsFromGMT()
        guard seconds != 0 else { return nil }
        let hours = Double(seconds) / 3600
        let sign = hours > 0 ? "+" : "−"
        let magnitude = abs(hours)
        let text = magnitude == magnitude.rounded()
            ? String(Int(magnitude))
            : String(format: "%.1f", magnitude)
        return "\(sign)\(text) sa"
    }
}

/// The bar every metered widget draws, so battery and storage read as one family.
struct WidgetMeter: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.2), value: fraction)
    }
}
