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
    /// Whether the clipboard history survives a restart. Off unless chosen.
    @Published var clipboardKeepsHistory: Bool { didSet { defaults.set(clipboardKeepsHistory, forKey: "clipboardKeepsHistory") } }
    /// How many clipboard entries are kept, favourites aside.
    @Published var clipboardHistoryLimit: Int {
        didSet {
            let clamped = Self.clipboardHistoryLimits.contains(clipboardHistoryLimit) ? clipboardHistoryLimit : 30
            if clamped != clipboardHistoryLimit { clipboardHistoryLimit = clamped; return }
            defaults.set(clamped, forKey: "clipboardHistoryLimit")
        }
    }
    static let clipboardHistoryLimits = [30, 100, 250]
    /// Whether new screenshots are put on the shelf as they are taken.
    @Published var screenshotShelfEnabled: Bool { didSet { defaults.set(screenshotShelfEnabled, forKey: "screenshotShelfEnabled") } }
    /// The voice Jarvis speaks with.
    @Published var jarvisVoice: String { didSet { defaults.set(jarvisVoice, forKey: "jarvisVoice") } }
    /// The Realtime model behind Jarvis.
    /// Which voice engine a conversation uses: the good billed one, the free
    /// one, or whichever is available.
    /// Which Turkish voice reads the briefing. Empty means the best one
    /// installed, which is right until somebody prefers a different one.
    /// Whether MacB may ask Apple Mail what is unread. Off until somebody
    /// turns it on: the first read raises macOS's Automation prompt, and
    /// nothing should raise that on its own.
    @Published var mailEnabled: Bool { didSet { defaults.set(mailEnabled, forKey: "mailEnabled") } }
    /// A card when the user comes back after a while: new mail, the next
    /// meeting. Nothing to say, no card.
    @Published var returnSummaryEnabled: Bool {
        didSet { defaults.set(returnSummaryEnabled, forKey: "returnSummaryEnabled") }
    }
    /// A line in the island for important new mail and a meeting ten minutes away.
    @Published var headsUpEnabled: Bool { didSet { defaults.set(headsUpEnabled, forKey: "headsUpEnabled") } }
    /// Senders the user calls important, one per line in Settings.
    @Published var importantSenders: [String] {
        didSet { defaults.set(importantSenders, forKey: "importantSenders") }
    }

    @Published var briefingVoice: String {
        didSet { defaults.set(briefingVoice, forKey: "briefingVoice") }
    }

    @Published var jarvisEngine: String {
        didSet { defaults.set(jarvisEngine, forKey: "jarvisEngine") }
    }

    /// Lets the free engine read the screen's text and controls. Off: the
    /// words would go to a free provider that may train on them.
    @Published var freeEngineReadsScreen: Bool {
        didSet { defaults.set(freeEngineReadsScreen, forKey: "freeEngineReadsScreen") }
    }

    /// The free engine thinks with the downloaded local model first, when
    /// there is one. On by default: it is free, private and needs no internet.
    @Published var localModelEnabled: Bool { didSet { defaults.set(localModelEnabled, forKey: "localModelEnabled") } }

    @Published var jarvisModel: String {
        didSet {
            let trimmed = jarvisModel.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed.isEmpty ? JarvisProtocol.defaultModel : trimmed, forKey: "jarvisModel")
        }
    }
    /// ⌃⌥Space opens and closes Jarvis.
    @Published var jarvisHotKeyEnabled: Bool { didSet { defaults.set(jarvisHotKeyEnabled, forKey: "jarvisHotKeyEnabled") } }
    /// How MacB talks: manner only, never what it is allowed to do.
    @Published var jarvisPersona: String { didSet { defaults.set(jarvisPersona, forKey: "jarvisPersona") } }
    /// The morning briefing: one greeting a day with the weather and what is on.
    @Published var briefingEnabled: Bool { didSet { defaults.set(briefingEnabled, forKey: "briefingEnabled") } }
    /// The earliest hour it may be given.
    @Published var briefingHour: Int { didSet { defaults.set(briefingHour, forKey: "briefingHour") } }
    /// Whether it is read aloud, by macOS's own voice.
    @Published var briefingSpeaks: Bool { didSet { defaults.set(briefingSpeaks, forKey: "briefingSpeaks") } }
    /// Whether the island shows what is being said. Off: a spoken conversation
    /// does not need subtitles unless the user wants them.
    @Published var assistantCaptions: Bool { didSet { defaults.set(assistantCaptions, forKey: "assistantCaptions") } }
    /// The language a selection is translated into (unless it is already in it).
    @Published var translationTarget: String { didSet { defaults.set(translationTarget, forKey: "translationTarget") } }
    /// How long "stay awake" lasts when started from the ring, in minutes; 0 for no end.
    @Published var keepAwakeMinutes: Int { didSet { defaults.set(keepAwakeMinutes, forKey: "keepAwakeMinutes") } }
    @Published var peekEnabled: Bool { didSet { defaults.set(peekEnabled, forKey: "peekEnabled") } }
    @Published var groupedWindowsEnabled: Bool { didSet { defaults.set(groupedWindowsEnabled, forKey: "groupedWindowsEnabled") } }
    @Published var clipboardShelfEnabled: Bool { didSet { defaults.set(clipboardShelfEnabled, forKey: "clipboardShelfEnabled") } }
    @Published var focusModeEnabled: Bool { didSet { defaults.set(focusModeEnabled, forKey: "focusModeEnabled") } }
    @Published var fileActivityEnabled: Bool { didSet { defaults.set(fileActivityEnabled, forKey: "fileActivityEnabled") } }
    @Published var protectPrivateTools: Bool { didSet { defaults.set(protectPrivateTools, forKey: "protectPrivateTools") } }
    @Published var interfaceDensity: InterfaceDensity { didSet { defaults.set(interfaceDensity.rawValue, forKey: "interfaceDensity") } }
    @Published var islandAppearance: IslandAppearance { didSet { defaults.set(islandAppearance.rawValue, forKey: "islandAppearance") } }
    /// How much of the desktop shows through the glass island, 0 to 1.
    ///
    /// A single number rather than three named presets, because the right
    /// amount depends entirely on the wallpaper underneath: a dark photograph
    /// takes far more transparency than a white one before the widgets stop
    /// being readable, and only the person looking at it knows which they have.
    @Published var islandTranslucency: Double {
        didSet { defaults.set(min(1, max(0, islandTranslucency)), forKey: "islandTranslucency") }
    }
    @Published var islandEventsEnabled: Bool { didSet { defaults.set(islandEventsEnabled, forKey: "islandEventsEnabled") } }
    @Published var lidHingeEnabled: Bool { didSet { defaults.set(lidHingeEnabled, forKey: "lidHingeEnabled") } }
    /// The hinge angle at which the fold starts, in degrees.
    @Published var lidHingeAngle: Double {
        didSet { defaults.set(LidFold.clampOpenAngle(lidHingeAngle), forKey: "lidHingeAngle") }
    }
    /// Whether the island spills light onto the desktop behind it.
    @Published var islandGlow: Bool { didSet { defaults.set(islandGlow, forKey: "islandGlow") } }
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
    @Published var mediaWidgetStyle: MediaWidgetStyle { didSet { defaults.set(mediaWidgetStyle.rawValue, forKey: "mediaWidgetStyle") } }
    @Published var weatherWidgetStyle: WeatherWidgetStyle { didSet { defaults.set(weatherWidgetStyle.rawValue, forKey: "weatherWidgetStyle") } }
    /// The city the world-clock widget shows next to local time. An identifier
    /// rather than an offset, so the widget follows daylight saving on its own.
    @Published var secondaryTimeZone: String { didSet { defaults.set(secondaryTimeZone, forKey: "secondaryTimeZone") } }
    @Published var shortcut: SwitcherShortcut { didSet { defaults.set(shortcut.rawValue, forKey: "shortcut") } }
    /// Whether Fn + a two-finger click opens the ring of shortcuts.
    @Published var radialMenuEnabled: Bool {
        didSet { defaults.set(radialMenuEnabled, forKey: "radialMenuEnabled") }
    }
    /// How much of the screen the ring lets through, 0 to 1.
    @Published var radialMenuTranslucency: Double {
        didSet {
            let clamped = min(1, max(0, radialMenuTranslucency))
            if clamped != radialMenuTranslucency { radialMenuTranslucency = clamped; return }
            defaults.set(clamped, forKey: "radialMenuTranslucency")
        }
    }
    /// How big the ring is drawn, as a multiplier on its natural size.
    @Published var radialMenuScale: Double {
        didSet {
            let clamped = min(RadialMenuMetrics.maximumScale,
                              max(RadialMenuMetrics.minimumScale, radialMenuScale))
            if clamped != radialMenuScale { radialMenuScale = clamped; return }
            defaults.set(clamped, forKey: "radialMenuScale")
        }
    }
    /// Whether a three-finger tap opens the ring, with no Fn and no click.
    @Published var radialMenuThreeFinger: Bool {
        didSet { defaults.set(radialMenuThreeFinger, forKey: "radialMenuThreeFinger") }
    }
    /// Which OpenAI model answers. A name rather than a choice from a fixed
    /// list, because the list changes more often than MacB does.
    @Published var aiModel: String {
        didSet {
            let trimmed = aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed.isEmpty ? Self.defaultAIModel : trimmed, forKey: "aiModel")
        }
    }
    static let defaultAIModel = "gpt-6-astra"
    /// Which provider answers: a stored raw value, or empty for "whichever has
    /// a key, free ones first".
    @Published var aiProvider: String { didSet { defaults.set(aiProvider, forKey: "aiProvider") } }
    /// The chosen provider, when it is one MacB knows.
    var preferredProvider: AIProvider? { AIProvider(rawValue: aiProvider) }

    /// The model for one provider. Each keeps its own: switching from Groq to
    /// Gemini must not carry a model name that only one of them has.
    func model(for provider: AIProvider) -> String {
        if provider == .openAI { return aiModel }
        let stored = defaults.string(forKey: "aiModel." + provider.account) ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultModel : trimmed
    }

    func setModel(_ name: String, for provider: AIProvider) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .openAI {
            aiModel = trimmed.isEmpty ? Self.defaultAIModel : trimmed
        } else {
            defaults.set(trimmed.isEmpty ? provider.defaultModel : trimmed,
                         forKey: "aiModel." + provider.account)
            objectWillChange.send()
        }
    }

    /// Whether MacB has a Dock icon and appears in the ⌘Tab switcher.
    ///
    /// On by default. It was off, which is what a notch utility normally
    /// wants — it lives in the island and the menu bar, and an extra Dock icon
    /// is clutter. But macOS gives no way to be in ⌘Tab without being in the
    /// Dock, and somebody going to ⌘Tab to find MacB and not finding it is a
    /// worse outcome than one more icon. Off is still one switch away.
    @Published var showInDock: Bool { didSet { defaults.set(showInDock, forKey: "showInDock") } }
    /// Rings for particular applications, by bundle identifier. Anything not
    /// in here gets `radialMenuLayout`.
    @Published var radialMenuAppLayouts: [String: RadialMenuLayout] {
        didSet {
            guard let data = try? JSONEncoder().encode(radialMenuAppLayouts) else { return }
            defaults.set(data, forKey: "radialMenuAppLayouts")
        }
    }
    /// What sits on the ring, clockwise from the top.
    @Published var radialMenuLayout: RadialMenuLayout {
        didSet {
            guard let data = try? JSONEncoder().encode(radialMenuLayout) else { return }
            defaults.set(data, forKey: "radialMenuLayout")
        }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["dockEnabled": true, "notchEnabled": true, "switcherEnabled": true,
                                    "windowManagementEnabled": false,
                                    "compactIndicators": true, "animationsEnabled": true,
                                    "smartNotchEnabled": true, "favoriteWindowsEnabled": true,
                                    "recentFilesEnabled": false, "peekEnabled": true,
                                    "screenshotShelfEnabled": false,
                                    "translationTarget": "tr",
                                    "jarvisVoice": JarvisVoice.marin.rawValue,
                                    "jarvisModel": JarvisProtocol.defaultModel,
                                    "jarvisEngine": JarvisEngineChoice.automatic.rawValue,
                                    "jarvisHotKeyEnabled": true,
                                    "jarvisPersona": JarvisPersona.defaultPersona.rawValue,
                                    "briefingEnabled": false, "briefingHour": 8, "briefingSpeaks": true,
                                    "assistantCaptions": false,
                                    "keepAwakeMinutes": 60,
                                    "clipboardKeepsHistory": false, "clipboardHistoryLimit": 30,
                                    "groupedWindowsEnabled": true,
                                    "clipboardShelfEnabled": true, "focusModeEnabled": false,
                                    "fileActivityEnabled": false,
                                    "protectPrivateTools": false,
                                    "interfaceDensity": InterfaceDensity.balanced.rawValue,
                                    "islandAppearance": IslandAppearance.pureBlack.rawValue,
                                    "islandTranslucency": 0.55,
                                    "islandEventsEnabled": true,
                                    "lidHingeEnabled": true,
                                    "lidHingeAngle": LidFold.defaultOpenAngle,
                                    "islandGlow": true,
                                    "lidScreenBlur": true,
                                    "automationEnabled": false,
                                    "radialMenuEnabled": true,
                                    "radialMenuTranslucency": 0.55,
                                    "radialMenuScale": 0.85,
                                    "radialMenuThreeFinger": false,
                                    "aiModel": Preferences.defaultAIModel,
                                    "aiProvider": "",
                                    "showInDock": true,
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
        screenshotShelfEnabled = defaults.bool(forKey: "screenshotShelfEnabled")
        translationTarget = defaults.string(forKey: "translationTarget") ?? "tr"
        jarvisVoice = defaults.string(forKey: "jarvisVoice") ?? JarvisVoice.marin.rawValue
        let storedJarvisModel = defaults.string(forKey: "jarvisModel") ?? JarvisProtocol.defaultModel
        if JarvisProtocol.retiredModels.contains(storedJarvisModel) {
            jarvisModel = JarvisProtocol.defaultModel
            defaults.set(JarvisProtocol.defaultModel, forKey: "jarvisModel")
        } else {
            jarvisModel = storedJarvisModel
        }
        jarvisEngine = defaults.string(forKey: "jarvisEngine") ?? JarvisEngineChoice.automatic.rawValue
        freeEngineReadsScreen = defaults.bool(forKey: "freeEngineReadsScreen")
        localModelEnabled = defaults.object(forKey: "localModelEnabled") as? Bool ?? true
        briefingVoice = defaults.string(forKey: "briefingVoice") ?? ""
        mailEnabled = defaults.bool(forKey: "mailEnabled")
        returnSummaryEnabled = defaults.object(forKey: "returnSummaryEnabled") as? Bool ?? true
        headsUpEnabled = defaults.object(forKey: "headsUpEnabled") as? Bool ?? true
        importantSenders = defaults.stringArray(forKey: "importantSenders") ?? []
        jarvisHotKeyEnabled = defaults.bool(forKey: "jarvisHotKeyEnabled")
        let personaMigrationKey = "jarvisPersonaKankaDefaultMigrated"
        let storedPersona = defaults.string(forKey: "jarvisPersona")
        if storedPersona == nil || (!defaults.bool(forKey: personaMigrationKey) && storedPersona == JarvisPersona.mirror.rawValue) {
            jarvisPersona = JarvisPersona.defaultPersona.rawValue
            defaults.set(JarvisPersona.defaultPersona.rawValue, forKey: "jarvisPersona")
            defaults.set(true, forKey: personaMigrationKey)
        } else {
            jarvisPersona = storedPersona ?? JarvisPersona.defaultPersona.rawValue
            defaults.set(true, forKey: personaMigrationKey)
        }
        briefingEnabled = defaults.bool(forKey: "briefingEnabled")
        briefingHour = defaults.integer(forKey: "briefingHour")
        briefingSpeaks = defaults.bool(forKey: "briefingSpeaks")
        assistantCaptions = defaults.bool(forKey: "assistantCaptions")
        keepAwakeMinutes = defaults.integer(forKey: "keepAwakeMinutes")
        clipboardKeepsHistory = defaults.bool(forKey: "clipboardKeepsHistory")
        let storedLimit = defaults.integer(forKey: "clipboardHistoryLimit")
        clipboardHistoryLimit = Preferences.clipboardHistoryLimits.contains(storedLimit) ? storedLimit : 30
        peekEnabled = defaults.bool(forKey: "peekEnabled")
        groupedWindowsEnabled = defaults.bool(forKey: "groupedWindowsEnabled")
        clipboardShelfEnabled = defaults.bool(forKey: "clipboardShelfEnabled")
        focusModeEnabled = defaults.bool(forKey: "focusModeEnabled")
        fileActivityEnabled = defaults.bool(forKey: "fileActivityEnabled")
        protectPrivateTools = defaults.bool(forKey: "protectPrivateTools")
        interfaceDensity = InterfaceDensity(rawValue: defaults.string(forKey: "interfaceDensity") ?? "") ?? .balanced
        islandAppearance = IslandAppearance(rawValue: defaults.string(forKey: "islandAppearance") ?? "") ?? .pureBlack
        islandTranslucency = min(1, max(0, defaults.double(forKey: "islandTranslucency")))
        islandEventsEnabled = defaults.bool(forKey: "islandEventsEnabled")
        lidHingeEnabled = defaults.bool(forKey: "lidHingeEnabled")
        lidHingeAngle = LidFold.clampOpenAngle(defaults.double(forKey: "lidHingeAngle"))
        islandGlow = defaults.bool(forKey: "islandGlow")
        lidScreenBlur = defaults.bool(forKey: "lidScreenBlur")
        automationEnabled = defaults.bool(forKey: "automationEnabled")
        radialMenuEnabled = defaults.bool(forKey: "radialMenuEnabled")
        radialMenuTranslucency = min(1, max(0, defaults.double(forKey: "radialMenuTranslucency")))
        radialMenuScale = min(RadialMenuMetrics.maximumScale,
                              max(RadialMenuMetrics.minimumScale, defaults.double(forKey: "radialMenuScale")))
        radialMenuThreeFinger = defaults.bool(forKey: "radialMenuThreeFinger")
        aiModel = defaults.string(forKey: "aiModel") ?? Preferences.defaultAIModel
        aiProvider = defaults.string(forKey: "aiProvider") ?? ""
        showInDock = defaults.bool(forKey: "showInDock")
        // A ring that cannot be decoded is a ring with the default slices, not
        // an app that refuses to start.
        radialMenuAppLayouts = defaults.data(forKey: "radialMenuAppLayouts")
            .flatMap { try? JSONDecoder().decode([String: RadialMenuLayout].self, from: $0) } ?? [:]
        radialMenuLayout = defaults.data(forKey: "radialMenuLayout")
            .flatMap { try? JSONDecoder().decode(RadialMenuLayout.self, from: $0) }
            ?? .default
        lidWelcomeText = defaults.string(forKey: "lidWelcomeText") ?? ""
        lidFarewellText = defaults.string(forKey: "lidFarewellText") ?? ""
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
