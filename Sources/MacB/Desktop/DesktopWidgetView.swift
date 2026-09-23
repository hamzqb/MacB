import MacBCore
import SwiftUI

/// One widget as it looks on the desktop.
///
/// Apple's own desktop widgets are a rounded card of material with the content
/// inside and nothing else: no title bar, no close button until you ask for
/// one. MacB's are the same shape, in the same three sizes, carrying the same
/// widgets the island does.
struct DesktopWidgetView: View {
    let widget: DesktopWidget
    @ObservedObject var store: DesktopWidgetStore
    let services: DesktopWidgetServices
    var remove: () -> Void
    var setSize: (DesktopWidget.Size) -> Void

    @State private var isHovering = false

    private var span: Int {
        switch widget.size {
        case .small: return 1
        case .medium: return 2
        case .large: return 3
        }
    }

    var body: some View {
        DesktopWidgetContent(kind: widget.kind, services: services)
            .environment(\.islandWidgetSpan, span)
            // The island's widgets are drawn for a hundred-point strip. On the
            // desktop they get a card several times that, so the content sits
            // in the middle of it rather than clinging to the top left.
            // The island's widgets pin themselves to the top left of whatever
            // they are given, so on the desktop they are given a strip of
            // their own height and that strip is centred in the card.
            .frame(height: widget.size == .large ? nil : 108)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(widget.size == .small ? 12 : 14)
            .frame(width: widget.size.size.width, height: widget.size.size.height)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            .overlay(alignment: .topTrailing) { removeButton }
            .preferredColorScheme(.dark)
            .foregroundStyle(.white)
            .onHover { isHovering = $0 }
            .contextMenu {
                ForEach(DesktopWidget.Size.allCases, id: \.self) { size in
                    Button(size.title) { setSize(size) }
                }
                Divider()
                Button("Masaüstünden kaldır", role: .destructive, action: remove)
            }
            .accessibilityLabel("\(widget.kind.title) widget'ı")
    }

    @ViewBuilder private var surface: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(.black.opacity(0.35)),
                                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.black.opacity(0.35)))
        }
    }

    /// Only under the pointer: a widget is something to read, not a row of
    /// buttons.
    @ViewBuilder private var removeButton: some View {
        if isHovering {
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.black.opacity(0.45)))
            }
            .buttonStyle(.plain)
            .padding(8)
            .transition(.opacity)
            .help("Masaüstünden kaldır")
            .accessibilityLabel("Masaüstünden kaldır")
        }
    }
}

/// The services every desktop widget might read from, in one place, so the
/// controller hands them over once.
@MainActor struct DesktopWidgetServices {
    let media: MediaService
    let timer: TimerService
    let clipboard: ClipboardShelfStore
    let aiActivity: AIActivityService
    let systemMonitor: SystemMonitorService
    let processes: ProcessMonitorService
    let watchers: WatchTaskStore
    let recentFiles: RecentFileStore
    let tasks: TaskStore
    let launcher: AppLauncherStore
    let weather: WeatherService
    let shelf: ShelfStore
    let note: QuickNoteStore
    let preferences: Preferences
    let openIsland: (NotchContent) -> Void
    let openSettings: () -> Void
    let notify: (String, String) -> Void
}

/// The same widget bodies the island strip draws.
struct DesktopWidgetContent: View {
    let kind: IslandWidgetKind
    let services: DesktopWidgetServices

    var body: some View {
        switch kind {
        case .media:
            MediaWidget(media: services.media, style: services.preferences.mediaWidgetStyle, notify: services.notify)
        case .timer:
            TimerWidget(timer: services.timer, open: { services.openIsland(.timer) })
        case .clipboard:
            ClipboardWidget(clipboard: services.clipboard, open: { services.openIsland(.clipboard) })
        case .calendar:
            CalendarWidget()
        case .weather:
            WeatherWidget(weather: services.weather, style: services.preferences.weatherWidgetStyle,
                          openSettings: services.openSettings)
        case .assistantActivity:
            AssistantWidget(activity: services.aiActivity)
        case .systemStats:
            SystemStatsWidget(monitor: services.systemMonitor)
        case .quickLaunch:
            QuickLaunchWidget(launcher: services.launcher, open: { services.openIsland(.apps) })
        case .tasks:
            TasksWidget(tasks: services.tasks)
        case .recentFiles:
            RecentFilesWidget(recentFiles: services.recentFiles, open: { services.openIsland(.files) })
        case .battery:
            BatteryWidget(monitor: services.systemMonitor)
        case .storage:
            StorageWidget(monitor: services.systemMonitor)
        case .shelf:
            ShelfWidget(shelf: services.shelf, open: { services.openIsland(.files) })
        case .notes:
            NotesWidget(note: services.note)
        case .worldClock:
            WorldClockWidget(preferences: services.preferences)
        case .topProcesses:
            TopProcessesWidget(processes: services.processes)
        case .watchers:
            WatchersWidget(watchers: services.watchers)
        }
    }
}
