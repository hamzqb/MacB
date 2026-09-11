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
    @ObservedObject var processes: ProcessMonitorService
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
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var columns: Int { IslandGeometry.columns(forWidth: width) }
    private var columnWidth: CGFloat { IslandGeometry.columnWidth(forWidth: width, columns: columns) }

    private var usesGlass: Bool { preferences.islandAppearance != .pureBlack }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandGeometry.gap) {
            gridSurface
                .environment(\.islandUsesGlass, usesGlass)
            if store.isEditing {
                IslandWidgetLibrary(store: store)
                    .transition(.opacity)
            }
        }
    }

    /// Glass panes close together should read as one sheet with seams, not as
    /// separate windows stacked on a window. The container is what tells macOS
    /// they belong to each other, so their edges bend into one another instead
    /// of each card refracting on its own.
    @ViewBuilder private var gridSurface: some View {
        if usesGlass, #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: IslandGeometry.gap) { grid }
        } else {
            grid
        }
    }

    private var grid: some View {
        VStack(spacing: IslandGeometry.gap) {
            ForEach(Array(store.rows(columns: columns).enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: IslandGeometry.gap) {
                    ForEach(Array(row.widgets.enumerated()), id: \.element.id) { columnIndex, widget in
                        widgetCard(widget)
                            .modifier(EntranceEffect(isVisible: hasAppeared,
                                                     index: rowIndex * max(1, columns) + columnIndex,
                                                     isEnabled: !reduceMotion))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        // The panel is already sliding open when this appears, so the cards
        // arrive just behind it rather than with it.
        .onAppear { hasAppeared = true }
        .onDisappear { hasAppeared = false }
    }

    /// One card in the strip.
    ///
    /// Rearranging is attached only while editing. A SwiftUI drag gesture claims
    /// the press before any button inside the view can act on it, so a card that
    /// is always draggable is a card whose own controls never fire: play, pause
    /// and skip all looked dead for exactly this reason.
    @ViewBuilder private func widgetCard(_ widget: IslandWidget) -> some View {
        let card = widgetBody(widget)
            .environment(\.islandWidgetSpan, widget.size.columns)
            // While editing, the card is a thing being arranged rather than a
            // thing being used: its own button would otherwise swallow the size
            // and remove taps that sit on top of it.
            .allowsHitTesting(!store.isEditing)
            .frame(width: IslandGeometry.widgetWidth(columnWidth: columnWidth, span: widget.size.columns),
                   height: IslandGeometry.widgetHeight)
            .clipShape(RoundedRectangle(cornerRadius: MacBDesign.IslandToken.widgetRadius, style: .continuous))
            // Depth, applied in one place so every widget reads as the same
            // material: a light fall from the top edge and a rim that is bright
            // where light would land and dark where it would not.
            .overlay {
                RoundedRectangle(cornerRadius: MacBDesign.IslandToken.widgetRadius, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.07), .clear],
                                         startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: MacBDesign.IslandToken.widgetRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
            .overlay(editingOverlay(widget))
            .opacity(dragging == widget.id ? 0.4 : 1)
        if store.isEditing {
            card
                .onDrag {
                    dragging = widget.id
                    return NSItemProvider(object: widget.id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: WidgetDropDelegate(target: widget, store: store, dragging: $dragging))
        } else {
            card
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
        case .topProcesses: TopProcessesWidget(processes: processes)
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
/// Whether the island surface under the cards is glass rather than black.
///
/// A card painted with a flat white wash reads as a grey box on glass. When the
/// surface refracts, the cards have to as well or the strip looks pasted on.
private struct IslandGlassKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var islandUsesGlass: Bool {
        get { self[IslandGlassKey.self] }
        set { self[IslandGlassKey.self] = newValue }
    }

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
    @Environment(\.islandUsesGlass) private var usesGlass

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, span <= 1 ? 9 : 12)
            .padding(.vertical, 10)
            .background(cardSurface)
    }

    @ViewBuilder private var cardSurface: some View {
        if usesGlass, #available(macOS 26.0, *) {
            // Glass of its own, so the card lifts off the panel instead of
            // sitting on it as a lighter rectangle.
            Color.clear.glassEffect(
                .regular.tint(.white.opacity(isActive ? 0.10 : 0.05)),
                in: RoundedRectangle(cornerRadius: MacBDesign.IslandToken.widgetRadius, style: .continuous))
        } else {
            isActive ? MacBDesign.IslandToken.widgetActiveFill : MacBDesign.IslandToken.widgetFill
        }
    }
}

/// The card for whatever is playing.
///
/// Every style shows the cover, the track and a transport that works. The four
/// styles differ in how the cover is used — as the whole card, as a frosted
/// backdrop, as a tile or as a record — and never in whether the controls exist.
struct MediaWidget: View {
    @ObservedObject var media: MediaService
    let style: MediaWidgetStyle
    var notify: (String, String) -> Void
    @Environment(\.islandWidgetSpan) private var span

    private var isLive: Bool { media.isPlaying || media.isRunning }
    /// The browser exposes play and pause through the page, and nothing else:
    /// offering skip buttons that cannot work is worse than not offering them.
    private var hasSkip: Bool { media.source != .browser }
    /// The cover's colour when there is one, the island's own accent when not.
    private var tint: Color { media.tint ?? MacBDesign.IslandToken.accent }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // A cover scaled to fill is larger than the card, and a ZStack
                // sizes itself to its biggest child. Pinning both layers to the
                // measured card keeps the text where it was drawn instead of
                // centring it on the artwork and clipping it away.
                background
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                content(width: proxy.size.width)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    @ViewBuilder private func content(width: CGFloat) -> some View {
        if !isLive { idle }
        else if width < 210 { compact }
        else if style == .record { record }
        else { full }
    }

    // MARK: - Background

    @ViewBuilder private var background: some View {
        switch style {
        case .artwork:
            if let artwork = media.artwork, isLive {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                // The cover is the card, so the text needs its own ground: a
                // soft band at the top for the artist and a deeper one at the
                // bottom where the transport sits.
                LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0),
                                       .init(color: .black.opacity(0.15), location: 0.42),
                                       .init(color: .black.opacity(0.88), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                MacBDesign.IslandToken.widgetFill
            }
        case .glass:
            if let artwork = media.artwork, isLive {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    .blur(radius: 34, opaque: true)
                    .overlay(Color.black.opacity(0.42))
            } else {
                MacBDesign.IslandToken.widgetFill
            }
        case .compact, .record:
            MacBDesign.IslandToken.widgetFill
        }
    }

    // MARK: - Layouts

    /// One unit wide. The track on top, the transport under it.
    ///
    /// Side by side there is no room for three buttons next to a cover and two
    /// lines of text, and skip is the control people reach for most.
    private var compact: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                // With the cover already filling the card, a second copy of it
                // is just a smaller hole in the artwork.
                if style != .artwork { cover(size: 26, radius: 6) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(media.title.isEmpty ? media.source.title : media.title)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(media.artist.isEmpty ? media.source.title : media.artist)
                        .font(.system(size: 9))
                        .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 2)
            transport(glyph: 10, diameter: 24, spacing: 9)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                if style != .artwork { cover(size: 38, radius: 9) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(media.title.isEmpty ? media.source.title : media.title)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Text(media.artist.isEmpty ? media.source.title : media.artist)
                        .font(.system(size: 10))
                        .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: media.source.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 4)
            if media.duration > 0 { progress }
            transport(glyph: 12, diameter: 30, spacing: 20)
                .padding(.top, media.duration > 0 ? 5 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var record: some View {
        HStack(spacing: 12) {
            vinyl
            VStack(alignment: .leading, spacing: 3) {
                Text(media.title.isEmpty ? media.source.title : media.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.85)
                Text(media.artist.isEmpty ? media.source.title : media.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                transport(glyph: 11, diameter: 28, spacing: 16, alignment: .leading)
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 12)
    }

    private var idle: some View {
        WidgetEmptyState(symbol: "music.note", title: "Çalan bir şey yok",
                         hint: "Spotify, Müzik veya tarayıcı")
            .padding(10)
    }

    // MARK: - Pieces

    /// The cover, or a placeholder that still reads as a cover rather than a hole.
    @ViewBuilder private func cover(size: CGFloat, radius: CGFloat) -> some View {
        Group {
            if let artwork = media.artwork {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    MacBDesign.IslandToken.widgetActiveFill
                    Image(systemName: media.source.symbol)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        // The cover throws a little of its own colour onto the card behind it.
        .shadow(color: (media.tint ?? .black).opacity(0.45), radius: 6, y: 2)
        .accessibilityHidden(true)
    }

    /// The record style turns the cover into the label of a spinning disc. It
    /// only spins while something is actually playing, so a paused track reads
    /// as paused without looking at the button.
    private var vinyl: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !media.isPlaying)) { context in
            let angle = media.isPlaying
                ? Angle(degrees: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) * 60)
                : .zero
            ZStack {
                Circle().fill(Color.black)
                ForEach([0.74, 0.52], id: \.self) { scale in
                    Circle().stroke(.white.opacity(0.13), lineWidth: 1).scaleEffect(scale)
                }
                Group {
                    if let artwork = media.artwork {
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        MacBDesign.IslandToken.accent
                    }
                }
                .clipShape(Circle())
                .padding(20)
                .rotationEffect(angle)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func transport(glyph: CGFloat, diameter: CGFloat, spacing: CGFloat,
                           alignment: HorizontalAlignment = .center) -> some View {
        HStack(spacing: spacing) {
            if alignment == .center { Spacer(minLength: 0) }
            if hasSkip { control("backward.fill", "Önceki", size: glyph, action: media.previousTrack) }
            playButton(diameter: diameter, glyph: glyph + 1)
            if hasSkip { control("forward.fill", "Sonraki", size: glyph, action: media.nextTrack) }
            Spacer(minLength: 0)
        }
    }

    private func playButton(diameter: CGFloat, glyph: CGFloat) -> some View {
        Button(action: media.playPause) {
            Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: glyph, weight: .bold))
                .foregroundStyle(MacBDesign.IslandToken.primaryText)
                .frame(width: diameter, height: diameter)
                // The button sits on album art as often as on black, so it
                // carries its own contrast rather than borrowing the card's.
                .background(.black.opacity(0.34), in: Circle())
                .background(tint.opacity(media.isPlaying ? 0.55 : 0.30), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.24), lineWidth: 0.5))
                .animation(.easeOut(duration: 0.45), value: media.tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(media.isPlaying ? "Duraklat" : "Oynat")
    }

    /// The bar alone at narrow widths; the times join it once there is room,
    /// because a clipped timestamp is worse than no timestamp.
    private var progress: some View {
        VStack(spacing: 3) {
            if span >= 3 {
                HStack {
                    Text(TimerService.format(media.position))
                    Spacer(minLength: 6)
                    Text("-" + TimerService.format(max(0, media.duration - media.position)))
                }
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(MacBDesign.IslandToken.secondaryText)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(tint)
                        .frame(width: proxy.size.width * min(1, max(0, media.position / max(1, media.duration))))
                        .animation(.easeOut(duration: 0.3), value: media.position)
                }
            }
            .frame(height: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(TimerService.format(media.position)) geçti, \(TimerService.format(max(0, media.duration - media.position))) kaldı")
    }

    private func control(_ symbol: String, _ label: String, size: CGFloat,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(MacBDesign.IslandToken.primaryText)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .frame(width: size + 10, height: size + 10)
                .contentShape(Rectangle())
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
                    WidgetEmptyState(symbol: "sparkles", title: "Çalışan görev yok",
                                     hint: "Claude ve Codex burada görünür")
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
    @Environment(\.islandWidgetSpan) private var span

    var body: some View {
        WidgetCard {
            VStack(alignment: .leading, spacing: 5) {
                WidgetCaption("Sistem")
                row("CPU", "\(Int(monitor.snapshot.cpuUsage))%")
                Sparkline(values: monitor.cpuHistory, tint: MacBDesign.IslandToken.accent)
                    .frame(height: span >= 2 ? 16 : 12)
                row("RAM", ratio(monitor.snapshot.usedMemory, monitor.snapshot.totalMemory))
                if span >= 2 {
                    Sparkline(values: monitor.memoryHistory, tint: Color(nsColor: .systemTeal))
                        .frame(height: 16)
                }
                if let battery = monitor.snapshot.batteryPercent, span >= 2 {
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
                        WidgetEmptyState(symbol: "square.grid.2x2", title: "Uygulama ekle",
                                         hint: "Sık açtıklarını buraya sabitle")
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
                    WidgetEmptyState(symbol: "checklist", title: "Liste boş",
                                     hint: "Yapılacak eklemek için dokun")
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
                        WidgetEmptyState(symbol: "clock.arrow.circlepath", title: "Yeni dosya yok",
                                         hint: "Son dokunduklarım burada")
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

/// What is actually costing the machine something.
///
/// Helpers are folded back into their application, because "Chrome, 2,9 GB,
/// twenty processes" is a sentence somebody can act on and twenty rows of
/// "Google Chrome Helper" is not.
struct TopProcessesWidget: View {
    @ObservedObject var processes: ProcessMonitorService
    @Environment(\.islandWidgetSpan) private var span

    private var rows: Int { span >= 4 ? 4 : (span >= 2 ? 3 : 2) }

    var body: some View {
        WidgetCard {
            VStack(alignment: .leading, spacing: 0) {
                WidgetCaption("Kaynak", trailing: span >= 2 ? "RAM" : nil)
                Spacer(minLength: 3)
                if processes.byMemory.isEmpty {
                    Text("Ölçülüyor…")
                        .font(.system(size: 11))
                        .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                    Spacer(minLength: 0)
                } else {
                    VStack(spacing: 3) {
                        ForEach(processes.byMemory.prefix(rows)) { usage in
                            row(usage)
                        }
                    }
                }
            }
        }
        .accessibilityLabel("En çok bellek kullananlar")
    }

    private func row(_ usage: ProcessUsage) -> some View {
        HStack(spacing: 6) {
            if let icon = processes.icon(for: usage) {
                Image(nsImage: icon).resizable().frame(width: 13, height: 13)
            } else {
                Image(systemName: "gearshape")
                    .font(.system(size: 9))
                    .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                    .frame(width: 13)
            }
            Text(usage.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacBDesign.IslandToken.primaryText)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if span >= 4, usage.cpuPercent >= 1 {
                Text("\(Int(usage.cpuPercent))%")
                    .font(.system(size: 10)).monospacedDigit()
                    .foregroundStyle(MacBDesign.IslandToken.secondaryText)
            }
            Text(ByteCountFormatter.string(fromByteCount: Int64(usage.memoryBytes), countStyle: .memory))
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(MacBDesign.IslandToken.primaryText)
        }
    }
}

/// A running line of recent readings, filled underneath.
///
/// No axes, no grid and no numbers: the value is already printed next to it, so
/// the line only has to answer whether this is new or whether it has been like
/// this for a while.
struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let points = positions(in: proxy.size)
            ZStack {
                if points.count >= 2 {
                    // The fill first, so the stroke sits crisply on top of it.
                    path(points, closingIn: proxy.size)
                        .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)],
                                             startPoint: .top, endPoint: .bottom))
                    path(points, closingIn: nil)
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                } else {
                    Capsule().fill(.white.opacity(0.08)).frame(height: 1.4)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func positions(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2, size.width > 0, size.height > 0 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        // The line is always read against a full scale, so a quiet machine draws
        // a flat line near the bottom rather than a dramatic one rescaled to noise.
        return values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step,
                    y: size.height - CGFloat(min(1, max(0, value))) * size.height)
        }
    }

    private func path(_ points: [CGPoint], closingIn size: CGSize?) -> Path {
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        if let size {
            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
            path.addLine(to: CGPoint(x: points[0].x, y: size.height))
            path.closeSubpath()
        }
        return path
    }
}

/// Four bars that move while something is playing.
///
/// Not a real spectrum: reading the audio would mean recording it, which the
/// island has no business doing. These are four sine waves at different rates,
/// which is what a level meter looks like from across a room.
struct EqualizerBars: View {
    var tint: Color = MacBDesign.IslandToken.primaryText
    var isPlaying = true
    var height: CGFloat = 11

    private let rates: [Double] = [1.9, 2.7, 1.4, 2.2]
    private let phases: [Double] = [0, 0.8, 1.9, 2.6]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(rates.indices, id: \.self) { index in
                    Capsule()
                        .fill(tint)
                        .frame(width: 2, height: barHeight(index, time: time))
                }
            }
            .frame(height: height, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(_ index: Int, time: Double) -> CGFloat {
        guard isPlaying else { return height * 0.25 }
        let wave = (sin(time * rates[index] * .pi + phases[index]) + 1) / 2
        return height * (0.22 + 0.78 * wave)
    }
}

/// Cards arriving one after another instead of all at once.
///
/// Thirty milliseconds apart is enough to read as a sequence and short enough
/// that the last card is in place before anybody reaches for it. Turned off
/// entirely when the system asks for reduced motion.
private struct EntranceEffect: ViewModifier {
    let isVisible: Bool
    let index: Int
    let isEnabled: Bool

    func body(content: Content) -> some View {
        guard isEnabled else { return AnyView(content) }
        return AnyView(
            content
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(isVisible ? 1 : 0.94, anchor: .top)
                .offset(y: isVisible ? 0 : 8)
                .animation(.spring(response: 0.40, dampingFraction: 0.80)
                    .delay(min(0.24, Double(index) * 0.03)), value: isVisible)
        )
    }
}

/// What a widget shows before it has anything to show.
///
/// A grey sentence reads as a widget that failed. A glyph on its own disc reads
/// as a widget that is ready and waiting, which is the truth, and it gives the
/// empty card the same weight as a full one so the strip does not sag where
/// nothing is happening yet.
struct WidgetEmptyState: View {
    let symbol: String
    let title: String
    var hint: String?
    @Environment(\.islandWidgetSpan) private var span

    private var diameter: CGFloat { span >= 2 ? 34 : 28 }

    var body: some View {
        VStack(spacing: span >= 2 ? 7 : 5) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.13), .white.opacity(0.02)],
                                         center: .topLeading, startRadius: 1, endRadius: diameter))
                Circle().strokeBorder(.white.opacity(0.10), lineWidth: 0.8)
                Image(systemName: symbol)
                    .font(.system(size: span >= 2 ? 14 : 12, weight: .medium))
                    .foregroundStyle(MacBDesign.IslandToken.secondaryText)
            }
            .frame(width: diameter, height: diameter)
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: span >= 2 ? 11 : 10, weight: .medium))
                    .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                if let hint, span >= 2 {
                    Text(hint)
                        .font(.system(size: 9))
                        .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, hint].compactMap { $0 }.joined(separator: ", "))
    }
}
