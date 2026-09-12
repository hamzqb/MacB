import AppKit
import MacBCore
import Carbon
import Combine

enum SwitcherShortcut: String, CaseIterable, Identifiable {
    case commandTab, optionTab, controlOptionTab, controlOptionSpace
    var id: String { rawValue }
    var title: String {
        switch self {
        case .commandTab: return "⌘ Tab"
        case .optionTab: return "⌥ Tab"
        case .controlOptionTab: return "⌃ ⌥ Tab"
        case .controlOptionSpace: return "⌃ ⌥ Boşluk"
        }
    }
    var keyCode: UInt32 { self == .controlOptionSpace ? UInt32(kVK_Space) : UInt32(kVK_Tab) }
    var carbonModifiers: UInt32 {
        switch self {
        case .commandTab: return UInt32(cmdKey)
        case .optionTab: return UInt32(optionKey)
        case .controlOptionTab, .controlOptionSpace: return UInt32(optionKey) | UInt32(controlKey)
        }
    }
    var requiredFlags: NSEvent.ModifierFlags {
        switch self {
        case .commandTab: return [.command]
        case .optionTab: return [.option]
        case .controlOptionTab, .controlOptionSpace: return [.option, .control]
        }
    }
}

enum InterfaceDensity: String, CaseIterable, Identifiable {
    case compact, balanced, spacious
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: return "Kompakt"
        case .balanced: return "Dengeli"
        case .spacious: return "Geniş"
        }
    }
    var cardWidth: CGFloat {
        switch self {
        case .compact: return 196
        case .balanced: return 220
        case .spacious: return 244
        }
    }
    var cardHeight: CGFloat {
        switch self {
        case .compact: return 104
        case .balanced: return 118
        case .spacious: return 134
        }
    }
}

enum IslandAppearance: String, CaseIterable, Identifiable {
    case pureBlack, liquidGlass, blackGlass, customImage

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pureBlack: return "Siyah"
        case .liquidGlass: return "Liquid Glass"
        case .blackGlass: return "Siyah Cam"
        case .customImage: return "Görsel"
        }
    }

    var usesMaterial: Bool { self == .liquidGlass || self == .blackGlass }
}

enum MediaWidgetStyle: String, CaseIterable, Identifiable {
    case artwork, glass, compact, record
    var id: String { rawValue }
    var title: String {
        switch self {
        case .artwork: return "Kapak"
        case .glass: return "Cam"
        case .compact: return "Kompakt"
        case .record: return "Plak"
        }
    }
}

enum WeatherWidgetStyle: String, CaseIterable, Identifiable {
    case system, bold, color, horizon
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Sistem"
        case .bold: return "Büyük"
        case .color: return "Renkli"
        case .horizon: return "Ufuk"
        }
    }
}


@MainActor final class Preferences: ObservableObject {
    @Published var dockEnabled: Bool { didSet { defaults.set(dockEnabled, forKey: "dockEnabled") } }
    @Published var notchEnabled: Bool { didSet { defaults.set(notchEnabled, forKey: "notchEnabled") } }
    @Published var switcherEnabled: Bool { didSet { defaults.set(switcherEnabled, forKey: "switcherEnabled") } }
    @Published var windowManagementEnabled: Bool { didSet { defaults.set(windowManagementEnabled, forKey: "windowManagementEnabled") } }
    @Published var compactIndicators: Bool { didSet { defaults.set(compactIndicators, forKey: "compactIndicators") } }
    @Published var animationsEnabled: Bool { didSet { defaults.set(animationsEnabled, forKey: "animationsEnabled") } }
    @Published var smartNotchEnabled: Bool { didSet { defaults.set(smartNotchEnabled, forKey: "smartNotchEnabled") } }
    @Published var favoriteWindowsEnabled: Bool { didSet { defaults.set(favoriteWindowsEnabled, forKey: "favoriteWindowsEnabled") } }
    @Published var recentFilesEnabled: Bool { didSet { defaults.set(recentFilesEnabled, forKey: "recentFilesEnabled") } }
    @Published var peekEnabled: Bool { didSet { defaults.set(peekEnabled, forKey: "peekEnabled") } }
    @Published var groupedWindowsEnabled: Bool { didSet { defaults.set(groupedWindowsEnabled, forKey: "groupedWindowsEnabled") } }
    @Published var clipboardShelfEnabled: Bool { didSet { defaults.set(clipboardShelfEnabled, forKey: "clipboardShelfEnabled") } }
    @Published var focusModeEnabled: Bool { didSet { defaults.set(focusModeEnabled, forKey: "focusModeEnabled") } }
    @Published var fileActivityEnabled: Bool { didSet { defaults.set(fileActivityEnabled, forKey: "fileActivityEnabled") } }
    @Published var protectPrivateTools: Bool { didSet { defaults.set(protectPrivateTools, forKey: "protectPrivateTools") } }
    @Published var interfaceDensity: InterfaceDensity { didSet { defaults.set(interfaceDensity.rawValue, forKey: "interfaceDensity") } }
    @Published var islandAppearance: IslandAppearance { didSet { defaults.set(islandAppearance.rawValue, forKey: "islandAppearance") } }
    @Published var islandEventsEnabled: Bool { didSet { defaults.set(islandEventsEnabled, forKey: "islandEventsEnabled") } }
    @Published var lidHingeEnabled: Bool { didSet { defaults.set(lidHingeEnabled, forKey: "lidHingeEnabled") } }
    /// The hinge angle at which the fold starts, in degrees.
    @Published var lidHingeAngle: Double {
        didSet { defaults.set(LidFold.clampOpenAngle(lidHingeAngle), forKey: "lidHingeAngle") }
    }
    /// Whether the whole screen blurs with the fold, or only the island.
    @Published var lidScreenBlur: Bool { didSet { defaults.set(lidScreenBlur, forKey: "lidScreenBlur") } }
    /// Whether the user's rules are allowed to run.
    @Published var automationEnabled: Bool { didSet { defaults.set(automationEnabled, forKey: "automationEnabled") } }
    /// What the island says when the lid opens. Empty means the greeting that
    /// fits the time of day.
    @Published var lidWelcomeText: String {
        didSet { defaults.set(lidWelcomeText, forKey: "lidWelcomeText") }
    }
    /// What it says as the lid goes down. Empty means the time-of-day farewell.
    @Published var lidFarewellText: String {
        didSet { defaults.set(lidFarewellText, forKey: "lidFarewellText") }
    }
    @Published var hidesSystemVolumeHUD: Bool { didSet { defaults.set(hidesSystemVolumeHUD, forKey: "hidesSystemVolumeHUD") } }
    @Published var mediaWidgetStyle: MediaWidgetStyle { didSet { defaults.set(mediaWidgetStyle.rawValue, forKey: "mediaWidgetStyle") } }
    @Published var weatherWidgetStyle: WeatherWidgetStyle { didSet { defaults.set(weatherWidgetStyle.rawValue, forKey: "weatherWidgetStyle") } }
    /// The city the world-clock widget shows next to local time. An identifier
    /// rather than an offset, so the widget follows daylight saving on its own.
    @Published var secondaryTimeZone: String { didSet { defaults.set(secondaryTimeZone, forKey: "secondaryTimeZone") } }
    @Published var shortcut: SwitcherShortcut { didSet { defaults.set(shortcut.rawValue, forKey: "shortcut") } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["dockEnabled": true, "notchEnabled": true, "switcherEnabled": true,
                                    "windowManagementEnabled": false,
                                    "compactIndicators": true, "animationsEnabled": true,
                                    "smartNotchEnabled": true, "favoriteWindowsEnabled": true,
                                    "recentFilesEnabled": false, "peekEnabled": true,
                                    "groupedWindowsEnabled": true,
                                    "clipboardShelfEnabled": true, "focusModeEnabled": false,
                                    "fileActivityEnabled": false,
                                    "protectPrivateTools": false,
                                    "interfaceDensity": InterfaceDensity.balanced.rawValue,
                                    "islandAppearance": IslandAppearance.pureBlack.rawValue,
                                    "islandEventsEnabled": true,
                                    "lidHingeEnabled": true,
                                    "lidHingeAngle": LidFold.defaultOpenAngle,
                                    "lidScreenBlur": true,
                                    "automationEnabled": false,
                                    "hidesSystemVolumeHUD": false,
                                    "secondaryTimeZone": "America/New_York"])
        dockEnabled = defaults.bool(forKey: "dockEnabled")
        notchEnabled = defaults.bool(forKey: "notchEnabled")
        switcherEnabled = defaults.bool(forKey: "switcherEnabled")
        windowManagementEnabled = defaults.bool(forKey: "windowManagementEnabled")
        compactIndicators = defaults.bool(forKey: "compactIndicators")
        animationsEnabled = defaults.bool(forKey: "animationsEnabled")
        smartNotchEnabled = defaults.bool(forKey: "smartNotchEnabled")
        favoriteWindowsEnabled = defaults.bool(forKey: "favoriteWindowsEnabled")
        recentFilesEnabled = defaults.bool(forKey: "recentFilesEnabled")
        peekEnabled = defaults.bool(forKey: "peekEnabled")
        groupedWindowsEnabled = defaults.bool(forKey: "groupedWindowsEnabled")
        clipboardShelfEnabled = defaults.bool(forKey: "clipboardShelfEnabled")
        focusModeEnabled = defaults.bool(forKey: "focusModeEnabled")
        fileActivityEnabled = defaults.bool(forKey: "fileActivityEnabled")
        protectPrivateTools = defaults.bool(forKey: "protectPrivateTools")
        interfaceDensity = InterfaceDensity(rawValue: defaults.string(forKey: "interfaceDensity") ?? "") ?? .balanced
        islandAppearance = IslandAppearance(rawValue: defaults.string(forKey: "islandAppearance") ?? "") ?? .pureBlack
        islandEventsEnabled = defaults.bool(forKey: "islandEventsEnabled")
        lidHingeEnabled = defaults.bool(forKey: "lidHingeEnabled")
        lidHingeAngle = LidFold.clampOpenAngle(defaults.double(forKey: "lidHingeAngle"))
        lidScreenBlur = defaults.bool(forKey: "lidScreenBlur")
        automationEnabled = defaults.bool(forKey: "automationEnabled")
        lidWelcomeText = defaults.string(forKey: "lidWelcomeText") ?? ""
        lidFarewellText = defaults.string(forKey: "lidFarewellText") ?? ""
        hidesSystemVolumeHUD = defaults.bool(forKey: "hidesSystemVolumeHUD")
        let storedZone = defaults.string(forKey: "secondaryTimeZone") ?? "America/New_York"
        secondaryTimeZone = TimeZone(identifier: storedZone) == nil ? "America/New_York" : storedZone
        mediaWidgetStyle = MediaWidgetStyle(rawValue: defaults.string(forKey: "mediaWidgetStyle") ?? "") ?? .artwork
        weatherWidgetStyle = WeatherWidgetStyle(rawValue: defaults.string(forKey: "weatherWidgetStyle") ?? "") ?? .system
        let storedShortcut = SwitcherShortcut(rawValue: defaults.string(forKey: "shortcut") ?? "") ?? .commandTab
        let shouldPreferCommandTab = !defaults.bool(forKey: "didPreferCommandTabForSwitcher") && storedShortcut == .optionTab
        shortcut = shouldPreferCommandTab ? .commandTab : storedShortcut
        defaults.set(shortcut.rawValue, forKey: "shortcut")
        defaults.set(true, forKey: "didPreferCommandTabForSwitcher")
    }
}
