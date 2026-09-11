import AppKit
import MacBCore
import SwiftUI

/// The home strip: one row of equal-height widgets whose widths come from the layout store.
struct IslandWidgetStrip: View {
    @ObservedObject var store: IslandLayoutStore
    @ObservedObject var media: MediaService
    @ObservedObject var timer: TimerService
    @ObservedObject var clipboard: ClipboardShelfStore
    @ObservedObject var aiActivity: AIActivityService
    @ObservedObject var systemMonitor: SystemMonitorService
    @ObservedObject var recentFiles: RecentFileStore
    @ObservedObject var tasks: TaskStore
    @ObservedObject var launcher: AppLauncherStore
    @ObservedObject var weather: WeatherService
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var note: QuickNoteStore
    @ObservedObject var preferences: Preferences
    let width: CGFloat
    var select: (NotchContent) -> Void
    var openSettings: () -> Void
    var notify: (String, String) -> Void

    @State private var dragging: UUID?

    private var columns: Int { IslandGeometry.columns(forWidth: width) }
    private var columnWidth: CGFloat { IslandGeometry.columnWidth(forWidth: width, columns: columns) }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandGeometry.gap) {
            grid
            if store.isEditing {
                IslandWidgetLibrary(store: store)
                    .transition(.opacity)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: IslandGeometry.gap) {
            ForEach(Array(store.rows(columns: columns).enumerated()), id: \.offset) { _, row in
                HStack(spacing: IslandGeometry.gap) {
                    ForEach(row.widgets) { widget in
                        widgetBody(widget)
                            .environment(\.islandWidgetSpan, widget.size.columns)
                            // While editing, the card is a thing being arranged
                            // rather than a thing being used: its own button
                            // would otherwise swallow the size and remove taps
                            // that sit on top of it.
                            .allowsHitTesting(!store.isEditing)
                            .frame(width: IslandGeometry.widgetWidth(columnWidth: columnWidth, span: widget.size.columns),
                                   height: IslandGeometry.widgetHeight)
                            .clipShape(RoundedRectangle(cornerRadius: MacBDesign.IslandToken.widgetRadius, style: .continuous))
                            .overlay(editingOverlay(widget))
                            .opacity(dragging == widget.id ? 0.4 : 1)
                            .onDrag {
                                dragging = widget.id
                                return NSItemProvider(object: widget.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: WidgetDropDelegate(target: widget, store: store, dragging: $dragging))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private func widgetBody(_ widget: IslandWidget) -> some View {
        switch widget.kind {
        case .media: MediaWidget(media: media, style: preferences.mediaWidgetStyle, notify: notify)
        case .timer: TimerWidget(timer: timer, open: { select(.timer) })
        case .clipboard: ClipboardWidget(clipboard: clipboard, open: { select(.clipboard) })
        case .calendar: CalendarWidget()
        case .weather: WeatherWidget(weather: weather, style: preferences.weatherWidgetStyle, openSettings: openSettings)
        case .assistantActivity: AssistantWidget(activity: aiActivity)
        case .systemStats: SystemStatsWidget(monitor: systemMonitor)
        case .quickLaunch: QuickLaunchWidget(launcher: launcher, open: { select(.apps) })
        case .tasks: TasksWidget(tasks: tasks)
        case .recentFiles: RecentFilesWidget(recentFiles: recentFiles, open: { select(.files) })
        case .battery: BatteryWidget(monitor: systemMonitor)
        case .storage: StorageWidget(monitor: systemMonitor)
        case .shelf: ShelfWidget(shelf: shelf, open: { select(.files) })
        case .notes: NotesWidget(note: note)
        case .worldClock: WorldClockWidget(preferences: preferences)
        }
    }

    @ViewBuilder private func editingOverlay(_ widget: IslandWidget) -> some View {
        if store.isEditing {
            // The card is dimmed while it is being arranged. On a one-unit
            // widget the controls sit directly over the caption, and a scrim is
            // what keeps that readable as a control bar rather than a collision.
            RoundedRectangle(cornerRadius: MacBDesign.IslandToken.widgetRadius, style: .continuous)
                .fill(Color.black.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: MacBDesign.IslandToken.widgetRadius, style: .continuous)
                        .strokeBorder(MacBDesign.IslandToken.accent, lineWidth: 1.5))
                .overlay(alignment: .topTrailing) { editingControls(widget).padding(6) }
        }
    }

    /// The edit controls sit on their own dark bar rather than floating over the
    /// card. A one-unit widget is narrower than four round buttons, so at that
    /// width the three size letters collapse into one menu instead of sliding
    /// on top of each other and of the title underneath.
    private func editingControls(_ widget: IslandWidget) -> some View {
        HStack(spacing: 4) {
            if widget.size == .small {
                Menu {
                    ForEach(IslandWidgetSize.allCases, id: \.rawValue) { size in
                        Button(sizeName(size).capitalized) { store.resize(id: widget.id, to: size) }
                    }
                } label: {
                    Text(sizeLabel(widget.size))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 18, height: 18)
                        .background(Color.white, in: Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 18, height: 18)
                .accessibilityLabel("\(widget.kind.title) boyutu")
            } else {
                ForEach(IslandWidgetSize.allCases, id: \.rawValue) { size in
                    Button { store.resize(id: widget.id, to: size) } label: {
                        Text(sizeLabel(size))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(widget.size == size ? Color.black : .white)
                            .frame(width: 18, height: 18)
                            .background(widget.size == size ? Color.white : Color.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(widget.kind.title) \(sizeName(size))")
                }
            }
            Button { store.setEnabled(id: widget.id, false) } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 18, height: 18)
                    .background(MacBDesign.IslandToken.destructive, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(widget.kind.title) widget'ını kaldır")
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.62)))
    }

    private func sizeLabel(_ size: IslandWidgetSize) -> String {
        switch size {
        case .small: return "K"
        case .medium: return "O"
        case .wide: return "G"
        }
    }

    private func sizeName(_ size: IslandWidgetSize) -> String {
        switch size {
        case .small: return "küçük"
        case .medium: return "orta"
        case .wide: return "geniş"
        }
    }
}

private struct WidgetDropDelegate: DropDelegate {
    let target: IslandWidget
    let store: IslandLayoutStore
    @Binding var dragging: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target.id,
              let index = store.layout.widgets.firstIndex(where: { $0.id == target.id }) else { return }
        store.move(id: dragging, to: index)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

// MARK: - Widgets

/// How many grid units the widget being drawn occupies.
///
/// A one-unit card is about sixty points of usable width, which is not enough
/// for a caption and a value on the same line. Widgets read this to drop the
/// parts that would otherwise arrive as an ellipsis.
private struct IslandWidgetSpanKey: EnvironmentKey { static let defaultValue = 2 }

extension EnvironmentValues {
    var islandWidgetSpan: Int {
        get { self[IslandWidgetSpanKey.self] }
        set { self[IslandWidgetSpanKey.self] = newValue }
    }
}

/// The quiet label every widget opens with. Keeping it in one place keeps the strip on one baseline.
struct WidgetCaption: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer(minLength: 0)
            if let trailing { Text(trailing).fontWeight(.semibold) }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(MacBDesign.IslandToken.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

struct WidgetCard<Content: View>: View {
    var isActive = false
    @ViewBuilder var content: Content
    @Environment(\.islandWidgetSpan) private var span

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, span <= 1 ? 9 : 12)
            .padding(.vertical, 10)
            .background(isActive ? MacBDesign.IslandToken.widgetActiveFill : MacBDesign.IslandToken.widgetFill)
    }
}

struct MediaWidget: View {
    @ObservedObject var media: MediaService
    let style: MediaWidgetStyle
    var notify: (String, String) -> Void

    private var isLive: Bool { media.isPlaying || media.isRunning }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let artwork = media.artwork, style != .compact && style != .record {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    LinearGradient(colors: [.black.opacity(style == .glass ? 0.68 : 0.5), .black.opacity(0.1), .black.opacity(0.82)],
                                   startPoint: .top, endPoint: .bottom)
                } else {
                    MacBDesign.IslandToken.widgetFill
                }
                if isLive {
                    if proxy.size.width < 205 { compactPlaying }
                    else if style == .record { recordPlaying }
                    else { playing }
                } else { idle }
            }
        }
    }

    private var compactPlaying: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(media.source.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 5)
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.title.isEmpty ? media.source.title : media.title)
                        .font(.system(size: 14, weight: .bold)).lineLimit(1)
                    if !media.artist.isEmpty {
                        Text(media.artist).font(.system(size: 10))
                            .foregroundStyle(MacBDesign.IslandToken.secondaryText).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button(action: media.playPause) {
                    Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(media.isPlaying ? "Duraklat" : "Oynat")
            }
        }
        .padding(14)
    }

    private var recordPlaying: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.black)
                ForEach([0.72, 0.48], id: \.self) { scale in
                    Circle().stroke(.white.opacity(0.14), lineWidth: 1).scaleEffect(scale)
                }
                if let artwork = media.artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                        .clipShape(Circle()).padding(19)
                } else { Circle().fill(.orange).padding(24) }
            }
            .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 5) {
                Text(media.title).font(.system(size: 14, weight: .bold)).lineLimit(2)
                Text(media.artist.isEmpty ? media.source.title : media.artist)
                    .font(.system(size: 10)).foregroundStyle(MacBDesign.IslandToken.secondaryText).lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 18) {
                    control("backward.fill", "Önceki", size: 10, action: media.previousTrack)
                    control(media.isPlaying ? "pause.fill" : "play.fill", "Oynat veya duraklat", size: 13, action: media.playPause)
                    control("forward.fill", "Sonraki", size: 10, action: media.nextTrack)
                }
            }
            .padding(.vertical, 13)
        }
        .padding(12)
    }

    private var playing: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(media.artist.isEmpty ? media.source.title : media.artist)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if !media.artist.isEmpty {
                        Text(media.source.title)
                            .font(.system(size: 9))
                            .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: media.source.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 2)
            Text(media.title.isEmpty ? media.source.title : media.title)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
            if media.duration > 0 { progress } else { Spacer().frame(height: 5) }
            HStack(spacing: 22) {
                Spacer(minLength: 0)
                if media.source != .browser {
                    control("backward.fill", "Önceki", size: 11, action: media.previousTrack)
                }
                control(media.isPlaying ? "pause.fill" : "play.fill",
                        media.isPlaying ? "Duraklat" : "Oynat", size: 14, action: media.playPause)
                if media.source != .browser {
                    control("forward.fill", "Sonraki", size: 11, action: media.nextTrack)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Nothing is playing. A quiet single line beats an empty transport that does nothing.
    private var idle: some View {
        HStack(spacing: 9) {
            Image(systemName: "play.slash")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
            Text("Çalan bir şey yok")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MacBDesign.IslandToken.secondaryText)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
    }

    /// Elapsed and remaining sit above the line, the way a player prints them,
    /// so the bar itself stays the widest uninterrupted element in the card.
    private var progress: some View {
        VStack(spacing: 3) {
            HStack {
                Text(TimerService.format(media.position))
                Spacer(minLength: 6)
                Text("-" + TimerService.format(max(0, media.duration - media.position)))
            }
            .font(.system(size: 9))
            .monospacedDigit()
            .foregroundStyle(MacBDesign.IslandToken.secondaryText)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white)
                        .frame(width: proxy.size.width * min(1, max(0, media.position / max(1, media.duration))))
                }
            }
            .frame(height: 2)
        }
        .padding(.top, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(TimerService.format(media.position)) geçti, \(TimerService.format(max(0, media.duration - media.position))) kaldı")
    }

    private func control(_ symbol: String, _ label: String, size: CGFloat,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct TimerWidget: View {
    @ObservedObject var timer: TimerService
    var open: () -> Void

    var body: some View {
        WidgetCard {
            if timer.isActive {
                activeTimer
            } else {
                VStack(spacing: 4) {
                    WidgetCaption("Zamanlayıcı")
                    Spacer(minLength: 0)
                    Text(timer.selectionText)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MacBDesign.IslandToken.accent)
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        roundButton("play.fill", label: "Başlat", tint: MacBDesign.IslandToken.accent) { timer.start() }
                        roundButton("slider.horizontal.3", label: "Süre seç", tint: .white.opacity(0.18), action: open)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .overlay { if timer.isActive { progressRing } }
    }

    /// The remaining time drawn on the card's own edge.
    ///
    /// A ring inside the card would compete with the numerals for the little
    /// space a widget has; the border is free real estate and reads from across
    /// the room. The stroke is not rotated: rotating a non-square rounded
    /// rectangle rotates its frame too, and the trim lands off the card.
    private var progressRing: some View {
        let shape = RoundedRectangle(cornerRadius: MacBDesign.IslandToken.widgetRadius, style: .continuous)
        return ZStack {
            shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 2)
            shape
                .inset(by: 1)
                .trim(from: 0, to: max(0.001, 1 - timer.progress))
                .stroke(MacBDesign.IslandToken.accent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .animation(.linear(duration: 0.25), value: timer.progress)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var activeTimer: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetCaption(timer.isRunning ? "Zamanlayıcı" : "Duraklatıldı")
            Spacer(minLength: 0)
            Text(timer.remainingText)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(MacBDesign.IslandToken.accent)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                roundButton(timer.isRunning ? "pause.fill" : "play.fill",
                            label: timer.isRunning ? "Duraklat" : "Sürdür",
                            tint: MacBDesign.IslandToken.accent) {
                    timer.isRunning ? timer.pause() : timer.resume()
                }
                roundButton("xmark", label: "İptal", tint: .white.opacity(0.14)) { timer.cancel() }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Zamanlayıcı, \(timer.remainingText) kaldı")
    }

    private func roundButton(_ symbol: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint, in: Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct ClipboardWidget: View {
    @ObservedObject var clipboard: ClipboardShelfStore
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            WidgetCard {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetCaption("Pano", trailing: clipboard.items.isEmpty ? nil : "\(clipboard.items.count)")
                    if let latest = clipboard.items.first {
                        Text(latest.text)
                            .font(.system(size: 11))
                            .foregroundStyle(MacBDesign.IslandToken.primaryText)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("Kopyaladıkların burada birikir.")
                            .font(.system(size: 11))
                            .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pano, \(clipboard.items.count) öğe")
    }

}

struct CalendarWidget: View {
    private var now: Date { Date() }

    var body: some View {
        WidgetCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(weekday).foregroundStyle(MacBDesign.IslandToken.destructive)
                    Text(month).foregroundStyle(MacBDesign.IslandToken.primaryText)
                }
                .font(.system(size: 15, weight: .bold))
                Spacer(minLength: 0)
                Text(day)
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(MacBDesign.IslandToken.primaryText)
            }
        }
        .accessibilityLabel("\(weekday) \(day) \(month)")
    }

    private func text(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate(format)
        return formatter.string(from: now)
    }

    private var weekday: String { text("EEE") }
    private var month: String { text("MMM") }
    private var day: String { text("d") }
}

struct WeatherWidget: View {
    @ObservedObject var weather: WeatherService
    let style: WeatherWidgetStyle
    var openSettings: () -> Void

    var body: some View {
        WidgetCard {
            GeometryReader { proxy in
                let isNarrow = proxy.size.width < 150
                if let snapshot = weather.snapshot {
                    reading(snapshot, isNarrow: isNarrow)
                } else {
                    prompt(isNarrow: isNarrow)
                }
            }
        }
    }

    private func reading(_ snapshot: WeatherSnapshot, isNarrow: Bool) -> some View {
        ZStack {
            if style == .color {
                LinearGradient(colors: snapshot.isDay ? [.blue.opacity(0.8), .cyan.opacity(0.45)] : [.indigo.opacity(0.72), .black.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .padding(-14)
            } else if style == .horizon {
                Circle().fill(snapshot.isDay ? Color.orange : Color.indigo)
                    .blur(radius: 8).frame(width: 42, height: 42).offset(x: 32, y: 35)
            }
            weatherReading(snapshot, isNarrow: isNarrow)
        }
    }

    private func weatherReading(_ snapshot: WeatherSnapshot, isNarrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(snapshot.place)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: snapshot.symbol)
                    .symbolRenderingMode(.hierarchical)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MacBDesign.IslandToken.secondaryText)
            Spacer(minLength: 0)
            Text("\(snapshot.temperature)°")
                .font(.system(size: isNarrow ? 24 : (style == .bold ? 40 : 32), weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(snapshot.condition)
                .font(.system(size: isNarrow ? 10 : 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("Hissedilen \(snapshot.feelsLike)°")
                .font(.system(size: 10))
                .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.place), \(snapshot.temperature) derece, \(snapshot.condition)")
    }

    /// One unit is too narrow for a sentence, so the empty state is an icon and a verb.
    private func prompt(isNarrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetCaption("Hava")
            Spacer(minLength: 0)
            Button(action: openSettings) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "location.magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(MacBDesign.IslandToken.accent)
                    Text(weather.errorMessage ?? "Şehir seç")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacBDesign.IslandToken.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if !isNarrow {
                        Text("Ayarlar, Widget'lar")
                            .font(.system(size: 10))
                            .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hava durumu için şehir seç")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AssistantWidget: View {
    @ObservedObject var activity: AIActivityService

    var body: some View {
        WidgetCard(isActive: activity.isActive) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetCaption("Asistanlar")
                if activity.statuses.isEmpty {
                    Text("Çalışan görev yok")
                        .font(.system(size: 11))
                        .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                } else {
                    ForEach(activity.statuses.prefix(3)) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.kind.symbol)
                                .font(.system(size: 10))
                                .foregroundStyle(MacBDesign.IslandToken.accent)
                            Text(item.kind.rawValue).font(.system(size: 11, weight: .medium))
                            Spacer(minLength: 0)
                            Text(item.detail)
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

}

struct SystemStatsWidget: View {
    @ObservedObject var monitor: SystemMonitorService

    var body: some View {
        WidgetCard {
            VStack(alignment: .leading, spacing: 6) {
                WidgetCaption("Sistem")
                row("CPU", "\(Int(monitor.snapshot.cpuUsage))%")
                row("RAM", ratio(monitor.snapshot.usedMemory, monitor.snapshot.totalMemory))
                if let battery = monitor.snapshot.batteryPercent {
                    row("Pil", "\(Int(battery))%")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(MacBDesign.IslandToken.secondaryText)
            Spacer()
            Text(value).foregroundStyle(MacBDesign.IslandToken.primaryText).monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }

    private func ratio(_ used: UInt64, _ total: UInt64) -> String {
        guard total > 0 else { return "—" }
        return "\(Int(Double(used) / Double(total) * 100))%"
    }
}

struct QuickLaunchWidget: View {
    @ObservedObject var launcher: AppLauncherStore
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            WidgetCard {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetCaption("Hızlı erişim")
                    if launcher.items.isEmpty {
                        Text("Uygulama ekle")
                            .font(.system(size: 11))
                            .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                    } else {
                        HStack(spacing: 7) {
                            ForEach(quickItems.prefix(4)) { item in
                                Image(nsImage: item.icon)
                                    .resizable()
                                    .frame(width: 26, height: 26)
                                    .opacity(item.isAvailable ? 1 : 0.4)
                            }
                            if quickItems.count > 4 {
                                Text("+\(quickItems.count - 4)")
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
        .accessibilityLabel("Hızlı uygulamalar")
    }

    private var quickItems: [LauncherItem] { launcher.items }
}

struct TasksWidget: View {
    @ObservedObject var tasks: TaskStore

    var body: some View {
        WidgetCard {
            VStack(alignment: .leading, spacing: 6) {
                WidgetCaption("Yapılacaklar")
                if tasks.items.isEmpty {
                    Text("Liste boş")
                        .font(.system(size: 11))
                        .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                } else {
                    ForEach(tasks.items.prefix(3)) { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(item.isCompleted ? MacBDesign.IslandToken.accent : MacBDesign.IslandToken.tertiaryText)
                            Text(item.title).font(.system(size: 11)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct RecentFilesWidget: View {
    @ObservedObject var recentFiles: RecentFileStore
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            WidgetCard {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetCaption("Son dosyalar")
                    if recentFiles.items.isEmpty {
                        Text("Yeni dosya yok")
                            .font(.system(size: 11))
                            .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                    } else {
                        ForEach(recentFiles.items.prefix(3)) { item in
                            HStack(spacing: 6) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                    .resizable().frame(width: 14, height: 14)
                                Text(item.name).font(.system(size: 11)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Son dosyalar")
    }
}
