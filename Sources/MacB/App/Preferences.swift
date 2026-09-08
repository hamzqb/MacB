import AppKit
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

@MainActor final class Preferences: ObservableObject {
    @Published var dockEnabled: Bool { didSet { defaults.set(dockEnabled, forKey: "dockEnabled") } }
    @Published var notchEnabled: Bool { didSet { defaults.set(notchEnabled, forKey: "notchEnabled") } }
    @Published var switcherEnabled: Bool { didSet { defaults.set(switcherEnabled, forKey: "switcherEnabled") } }
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
    @Published var shortcut: SwitcherShortcut { didSet { defaults.set(shortcut.rawValue, forKey: "shortcut") } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["dockEnabled": true, "notchEnabled": true, "switcherEnabled": true,
                                    "compactIndicators": true, "animationsEnabled": true,
                                    "smartNotchEnabled": true, "favoriteWindowsEnabled": true,
                                    "recentFilesEnabled": false, "peekEnabled": true,
                                    "groupedWindowsEnabled": true,
                                    "clipboardShelfEnabled": true, "focusModeEnabled": false,
                                    "fileActivityEnabled": false,
                                    "protectPrivateTools": false,
                                    "interfaceDensity": InterfaceDensity.balanced.rawValue])
        dockEnabled = defaults.bool(forKey: "dockEnabled")
        notchEnabled = defaults.bool(forKey: "notchEnabled")
        switcherEnabled = defaults.bool(forKey: "switcherEnabled")
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
        let storedShortcut = SwitcherShortcut(rawValue: defaults.string(forKey: "shortcut") ?? "") ?? .commandTab
        let shouldPreferCommandTab = !defaults.bool(forKey: "didPreferCommandTabForSwitcher") && storedShortcut == .optionTab
        shortcut = shouldPreferCommandTab ? .commandTab : storedShortcut
        defaults.set(shortcut.rawValue, forKey: "shortcut")
        defaults.set(true, forKey: "didPreferCommandTabForSwitcher")
    }
}
