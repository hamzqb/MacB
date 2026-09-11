import Foundation

/// Where a widget belongs in the library, so browsing fifteen cards is still a
/// short list rather than one long wall.
public enum IslandWidgetCategory: String, Codable, CaseIterable, Sendable {
    case essentials
    case work
    case system
    case life

    public var title: String {
        switch self {
        case .essentials: return "Öne çıkanlar"
        case .work: return "Çalışma"
        case .system: return "Sistem"
        case .life: return "Yaşam"
        }
    }

    public var symbol: String {
        switch self {
        case .essentials: return "star.fill"
        case .work: return "briefcase.fill"
        case .system: return "gauge.with.dots.needle.67percent"
        case .life: return "leaf.fill"
        }
    }
}

public enum IslandWidgetKind: String, Codable, CaseIterable, Sendable {
    case media
    case timer
    case clipboard
    case calendar
    case weather
    case assistantActivity
    case systemStats
    case quickLaunch
    case tasks
    case recentFiles
    case battery
    case storage
    case shelf
    case notes
    case worldClock

    /// The name the library, the settings list and VoiceOver all read from, so a
    /// widget cannot end up called three different things in three places.
    public var title: String {
        switch self {
        case .media: return "Medya"
        case .timer: return "Zamanlayıcı"
        case .clipboard: return "Pano"
        case .calendar: return "Takvim"
        case .weather: return "Hava"
        case .assistantActivity: return "Asistan"
        case .systemStats: return "Sistem"
        case .quickLaunch: return "Hızlı erişim"
        case .tasks: return "Yapılacaklar"
        case .recentFiles: return "Son dosyalar"
        case .battery: return "Pil"
        case .storage: return "Depolama"
        case .shelf: return "Raf"
        case .notes: return "Not"
        case .worldClock: return "Dünya saati"
        }
    }

    public var summary: String {
        switch self {
        case .media: return "Çalan parça ve kontroller"
        case .timer: return "Geri sayım kart kenarında"
        case .clipboard: return "Son kopyaladıklarına dön"
        case .calendar: return "Bugünün günü ve tarihi"
        case .weather: return "Seçtiğin şehrin havası"
        case .assistantActivity: return "Claude ve Codex oturumları"
        case .systemStats: return "CPU, bellek ve pil"
        case .quickLaunch: return "Sabitlediğin uygulamalar"
        case .tasks: return "Kısa yapılacaklar listesi"
        case .recentFiles: return "Son dokunduğun dosyalar"
        case .battery: return "Yüzde ve şarj durumu"
        case .storage: return "Diskte kalan boş alan"
        case .shelf: return "Sürükleyip bıraktıkların"
        case .notes: return "Aklına geleni hemen yaz"
        case .worldClock: return "İkinci bir şehrin saati"
        }
    }

    public var symbol: String {
        switch self {
        case .media: return "music.note"
        case .timer: return "timer"
        case .clipboard: return "doc.on.clipboard"
        case .calendar: return "calendar"
        case .weather: return "cloud.sun.fill"
        case .assistantActivity: return "sparkles"
        case .systemStats: return "gauge.with.dots.needle.67percent"
        case .quickLaunch: return "square.grid.2x2.fill"
        case .tasks: return "checklist"
        case .recentFiles: return "clock.arrow.circlepath"
        case .battery: return "battery.100"
        case .storage: return "internaldrive.fill"
        case .shelf: return "tray.full.fill"
        case .notes: return "note.text"
        case .worldClock: return "globe"
        }
    }

    public var category: IslandWidgetCategory {
        switch self {
        case .media, .timer, .clipboard: return .essentials
        case .assistantActivity, .quickLaunch, .tasks, .recentFiles, .shelf: return .work
        case .systemStats, .battery, .storage: return .system
        case .calendar, .weather, .notes, .worldClock: return .life
        }
    }

    /// The width a widget gets when the library adds it, so a text widget does
    /// not arrive one unit wide with its first word already truncated.
    public var defaultSize: IslandWidgetSize {
        switch self {
        case .media: return .wide
        case .timer, .clipboard, .assistantActivity, .calendar, .quickLaunch, .tasks, .shelf, .notes:
            return .medium
        case .systemStats, .weather, .recentFiles, .battery, .storage, .worldClock:
            return .small
        }
    }

    /// Widgets that cost nothing when the panel is closed can stay enabled by default.
    public var isDefault: Bool {
        switch self {
        case .media, .timer, .clipboard, .systemStats, .assistantActivity: return true
        case .calendar, .weather, .quickLaunch, .tasks, .recentFiles,
             .battery, .storage, .shelf, .notes, .worldClock: return false
        }
    }

    /// A widget whose data source must not run while the panel is hidden.
    public var pollsWhileVisible: Bool {
        switch self {
        case .weather, .calendar, .systemStats, .assistantActivity, .battery, .storage, .worldClock:
            return true
        case .media, .timer, .clipboard, .quickLaunch, .tasks, .recentFiles, .shelf, .notes:
            return false
        }
    }
}

public enum IslandWidgetSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case wide

    /// Width in grid units. Every widget shares one height, so size means width only.
    public var columns: Int {
        switch self {
        case .small: return 1
        case .medium: return 2
        case .wide: return 4
        }
    }
}

public struct IslandWidget: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var kind: IslandWidgetKind
    public var size: IslandWidgetSize
    public var isEnabled: Bool

    public init(id: UUID = UUID(), kind: IslandWidgetKind, size: IslandWidgetSize, isEnabled: Bool) {
        self.id = id
        self.kind = kind
        self.size = size
        self.isEnabled = isEnabled
    }
}

public struct IslandWidgetRow: Equatable, Sendable {
    public let widgets: [IslandWidget]

    public init(widgets: [IslandWidget]) {
        self.widgets = widgets
    }

    public var usedColumns: Int { widgets.reduce(0) { $0 + $1.size.columns } }
}

/// Ordering, sizing and row packing for the home grid.
///
/// The layout is pure data so that "a widget is never clipped on a narrower display"
/// is a property the test runner can prove without rendering anything.
public struct IslandWidgetLayout: Codable, Equatable, Sendable {
    public private(set) var widgets: [IslandWidget]

    public init(widgets: [IslandWidget]) {
        self.widgets = widgets
    }

    public static var standard: IslandWidgetLayout {
        IslandWidgetLayout(widgets: IslandWidgetKind.allCases.map {
            IslandWidget(kind: $0, size: $0.defaultSize, isEnabled: $0.isDefault)
        })
    }

    public var enabledWidgets: [IslandWidget] { widgets.filter(\.isEnabled) }

    public var activeKinds: Set<IslandWidgetKind> { Set(enabledWidgets.map(\.kind)) }

    public mutating func move(from source: Int, to destination: Int) {
        guard widgets.indices.contains(source) else { return }
        let clamped = max(0, min(widgets.count - 1, destination))
        guard clamped != source else { return }
        let widget = widgets.remove(at: source)
        widgets.insert(widget, at: clamped)
    }

    public mutating func move(id: UUID, to destination: Int) {
        guard let source = widgets.firstIndex(where: { $0.id == id }) else { return }
        move(from: source, to: destination)
    }

    public mutating func resize(id: UUID, to size: IslandWidgetSize) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[index].size = size
    }

    /// Moves a visible widget past its visible neighbour, stepping over the
    /// hidden ones in between. Settings shows only the strip, so an arrow there
    /// has to move the card the user can actually see.
    public mutating func moveVisible(id: UUID, by offset: Int) {
        let visible = widgets.indices.filter { widgets[$0].isEnabled }
        guard let position = visible.firstIndex(where: { widgets[$0].id == id }) else { return }
        let target = position + offset
        guard visible.indices.contains(target) else { return }
        let widget = widgets.remove(at: visible[position])
        widgets.insert(widget, at: visible[target])
    }

    /// Turns a widget on and slides it to the end of the visible run.
    ///
    /// Without the move, a widget added from the library lands wherever the
    /// catalog happens to keep it, which can be behind six disabled ones, and
    /// the strip appears not to have changed at all.
    public mutating func add(id: UUID) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[index].isEnabled = true
        widgets[index].size = widgets[index].kind.defaultSize
        let lastEnabled = widgets.lastIndex { $0.isEnabled && $0.id != id }
        let destination = lastEnabled.map { $0 + 1 } ?? 0
        if index > destination { move(from: index, to: destination) }
    }

    /// The library, grouped the way it is browsed. Empty categories are dropped
    /// so adding a kind is the only thing needed to make it appear.
    public var groups: [IslandWidgetGroup] {
        IslandWidgetCategory.allCases.compactMap { category in
            let members = widgets.filter { $0.kind.category == category }
            return members.isEmpty ? nil : IslandWidgetGroup(category: category, widgets: members)
        }
    }

    public mutating func setEnabled(id: UUID, _ isEnabled: Bool) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[index].isEnabled = isEnabled
    }

    /// Packs enabled widgets into rows of at most `columns` units, preserving order.
    ///
    /// A widget wider than the available column count is narrowed to fit rather than
    /// overflowing the panel, so a narrow display degrades instead of clipping.
    public func rows(columns: Int) -> [IslandWidgetRow] {
        let available = max(1, columns)
        var rows: [IslandWidgetRow] = []
        var current: [IslandWidget] = []
        var used = 0

        func flush() {
            guard !current.isEmpty else { return }
            rows.append(IslandWidgetRow(widgets: current))
            current = []
            used = 0
        }

        for widget in enabledWidgets {
            var fitted = widget
            if fitted.size.columns > available {
                fitted.size = IslandWidgetSize.allCases
                    .filter { $0.columns <= available }
                    .max(by: { $0.columns < $1.columns }) ?? .small
            }
            if used + fitted.size.columns > available { flush() }
            current.append(fitted)
            used += fitted.size.columns
        }
        flush()
        return rows
    }

    /// Restores a decoded layout to the full widget catalog, so a build that adds a
    /// widget kind does not silently hide it from someone with a saved layout.
    public func merging(catalog: IslandWidgetLayout = .standard) -> IslandWidgetLayout {
        var merged = widgets.filter { widget in catalog.widgets.contains { $0.kind == widget.kind } }
        var seen = Set(merged.map(\.kind))
        for widget in catalog.widgets where !seen.contains(widget.kind) {
            merged.append(widget)
            seen.insert(widget.kind)
        }
        return IslandWidgetLayout(widgets: merged)
    }
}

/// One category's worth of the library.
public struct IslandWidgetGroup: Equatable, Identifiable, Sendable {
    public let category: IslandWidgetCategory
    public let widgets: [IslandWidget]

    public var id: String { category.rawValue }

    public init(category: IslandWidgetCategory, widgets: [IslandWidget]) {
        self.category = category
        self.widgets = widgets
    }
}
