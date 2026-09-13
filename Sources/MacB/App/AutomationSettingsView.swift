import AppKit
import MacBCore
import SwiftUI
import UniformTypeIdentifiers

/// The rules page.
///
/// A rule is one sentence: when this happens, do that. The editor is built the
/// same way, so what somebody fills in reads back to them in the list exactly
/// as they wrote it.
struct AutomationSettingsView: View {
    @ObservedObject var automation: AutomationService
    @ObservedObject var preferences: Preferences
    @State private var draft: AutomationRule?

    var body: some View {
        VStack(alignment: .leading, spacing: MacBDesign.contentSpacing) {
            SettingsCard(title: "Kurallar", symbol: "wand.and.rays") { header }
            if preferences.automationEnabled {
                if automation.rules.isEmpty, draft == nil {
                    emptyState
                } else {
                    ForEach(automation.rules) { rule in
                        ruleRow(rule)
                    }
                }
                if let draft {
                    AutomationRuleEditor(rule: draft,
                                         save: { saved in
                                             if automation.rules.contains(where: { $0.id == saved.id }) {
                                                 automation.update(saved)
                                             } else {
                                                 automation.add(saved)
                                             }
                                             self.draft = nil
                                         },
                                         cancel: { self.draft = nil })
                } else {
                    Button {
                        draft = AutomationRule(title: "", trigger: .chargerConnected, action: .pauseMedia)
                    } label: {
                        Label("Kural ekle", systemImage: "plus")
                            .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacBDesign.accent)
                }
                if let last = automation.lastRun {
                    Text("Son çalışan: \(last.title) · \(Self.time.string(from: last.at))")
                        .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                }
            }
        }
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var header: some View {
        Toggle(isOn: $preferences.automationEnabled) {
            VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
                Text("Kurallar çalışsın").font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
                Text("MacB'nin zaten izlediği olaylara bağlanır. Ek izin istemez, arka planda bir şey açmaz, hiçbir şey silmez.")
                    .font(.system(size: MacBDesign.TypeScale.body)).foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .accessibilityLabel("Kurallar çalışsın")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.tight) {
            Text("Henüz kural yok.").font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
            Text("Örnek: şarj takılınca 25 dakikalık zamanlayıcı başlasın. Ya da kapak kapanırken müzik dursun.")
                .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacBDesign.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func ruleRow(_ rule: AutomationRule) -> some View {
        HStack(alignment: .top, spacing: MacBDesign.Space.comfortable) {
            VStack(alignment: .leading, spacing: MacBDesign.Space.tight) {
                Text(rule.title.isEmpty ? AutomationText.title(rule.trigger) : rule.title)
                    .font(.system(size: MacBDesign.TypeScale.body, weight: .semibold))
                Text("\(AutomationText.title(rule.trigger)) → \(AutomationText.title(rule.action))")
                    .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !rule.action.isSafe {
                    Text("Bu eylem çalıştırılmaz, alanları eksik ya da güvenli değil.")
                        .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Button("Dene") { automation.test(rule) }
                .buttonStyle(.plain)
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
                .foregroundStyle(MacBDesign.accent)
                .disabled(!rule.action.isSafe)
            Button { draft = rule } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain).foregroundStyle(MacBDesign.muted)
                .help("Düzenle")
            Button { automation.remove(rule) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(MacBDesign.muted)
                .help("Kuralı sil")
            Toggle("", isOn: Binding(get: { rule.isEnabled },
                                     set: { automation.setEnabled(rule, $0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                .accessibilityLabel("\(rule.title) kuralı")
        }
        .padding(MacBDesign.Space.comfortable)
        .background(MacBDesign.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Turkish for every trigger and action, in one place.
enum AutomationText {
    static func title(_ trigger: AutomationTrigger) -> String {
        switch trigger {
        case .lidOpened: return "Kapak açılınca"
        case .lidClosing: return "Kapak kapanırken"
        case .chargerConnected: return "Şarj takılınca"
        case .chargerDisconnected: return "Şarj çıkınca"
        case .batteryBelow(let percent): return "Pil %\(percent) altına inince"
        case .mediaStarted: return "Müzik başlayınca"
        case .mediaStopped: return "Müzik durunca"
        case .timerFinished: return "Zamanlayıcı bitince"
        case .appLaunched(let identifier): return "\(appName(identifier)) açılınca"
        case .appQuit(let identifier): return "\(appName(identifier)) kapanınca"
        }
    }

    static func title(_ action: AutomationAction) -> String {
        switch action {
        case .openApplication(_, let name): return "\(name) uygulamasını aç"
        case .openLink(let link): return link.isEmpty ? "Bağlantı aç" : "\(link) adresini aç"
        case .showNotice(let text): return "Island'da \"\(text)\" göster"
        case .startTimer(let minutes): return "\(minutes) dakikalık zamanlayıcı başlat"
        case .pauseMedia: return "Çalanı durdur"
        case .runShortcut(let name): return "\"\(name)\" kısayolunu çalıştır"
        }
    }

    static func appName(_ identifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            return identifier
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Asks for an application and returns its identifier and display name.
    static func chooseApplication() -> (identifier: String, name: String)? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.application]
        panel.prompt = "Seç"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return nil }
        return (identifier, url.deletingPathExtension().lastPathComponent)
    }
}

/// Writes one rule.
///
/// The two halves are pickers plus whatever that choice needs, so nothing is
/// ever asked for that the chosen trigger or action does not use.
struct AutomationRuleEditor: View {
    @State var rule: AutomationRule
    var save: (AutomationRule) -> Void
    var cancel: () -> Void

    @State private var triggerKind: TriggerKind
    @State private var actionKind: ActionKind
    @State private var batteryPercent: Double
    @State private var triggerApp: (identifier: String, name: String)
    @State private var actionApp: (identifier: String, name: String)
    @State private var link: String
    @State private var notice: String
    @State private var minutes: Double
    @State private var shortcut: String

    init(rule: AutomationRule, save: @escaping (AutomationRule) -> Void, cancel: @escaping () -> Void) {
        _rule = State(initialValue: rule)
        self.save = save
        self.cancel = cancel
        _triggerKind = State(initialValue: TriggerKind(rule.trigger))
        _actionKind = State(initialValue: ActionKind(rule.action))
        if case .batteryBelow(let percent) = rule.trigger {
            _batteryPercent = State(initialValue: Double(percent))
        } else {
            _batteryPercent = State(initialValue: 20)
        }
        switch rule.trigger {
        case .appLaunched(let identifier), .appQuit(let identifier):
            _triggerApp = State(initialValue: (identifier, AutomationText.appName(identifier)))
        default:
            _triggerApp = State(initialValue: ("", ""))
        }
        if case .openApplication(let identifier, let name) = rule.action {
            _actionApp = State(initialValue: (identifier, name))
        } else {
            _actionApp = State(initialValue: ("", ""))
        }
        _link = State(initialValue: { if case .openLink(let value) = rule.action { return value } else { return "" } }())
        _notice = State(initialValue: { if case .showNotice(let value) = rule.action { return value } else { return "" } }())
        _minutes = State(initialValue: { if case .startTimer(let value) = rule.action { return Double(value) } else { return 25 } }())
        _shortcut = State(initialValue: { if case .runShortcut(let value) = rule.action { return value } else { return "" } }())
    }

    enum TriggerKind: String, CaseIterable, Identifiable {
        case lidOpened, lidClosing, chargerConnected, chargerDisconnected
        case batteryBelow, mediaStarted, mediaStopped, timerFinished, appLaunched, appQuit
        var id: String { rawValue }

        init(_ trigger: AutomationTrigger) {
            switch trigger {
            case .lidOpened: self = .lidOpened
            case .lidClosing: self = .lidClosing
            case .chargerConnected: self = .chargerConnected
            case .chargerDisconnected: self = .chargerDisconnected
            case .batteryBelow: self = .batteryBelow
            case .mediaStarted: self = .mediaStarted
            case .mediaStopped: self = .mediaStopped
            case .timerFinished: self = .timerFinished
            case .appLaunched: self = .appLaunched
            case .appQuit: self = .appQuit
            }
        }

        var title: String {
            switch self {
            case .lidOpened: return "Kapak açılınca"
            case .lidClosing: return "Kapak kapanırken"
            case .chargerConnected: return "Şarj takılınca"
            case .chargerDisconnected: return "Şarj çıkınca"
            case .batteryBelow: return "Pil belirli seviyenin altına inince"
            case .mediaStarted: return "Müzik başlayınca"
            case .mediaStopped: return "Müzik durunca"
            case .timerFinished: return "Zamanlayıcı bitince"
            case .appLaunched: return "Bir uygulama açılınca"
            case .appQuit: return "Bir uygulama kapanınca"
            }
        }
    }

    enum ActionKind: String, CaseIterable, Identifiable {
        case openApplication, openLink, showNotice, startTimer, pauseMedia, runShortcut
        var id: String { rawValue }

        init(_ action: AutomationAction) {
            switch action {
            case .openApplication: self = .openApplication
            case .openLink: self = .openLink
            case .showNotice: self = .showNotice
            case .startTimer: self = .startTimer
            case .pauseMedia: self = .pauseMedia
            case .runShortcut: self = .runShortcut
            }
        }

        var title: String {
            switch self {
            case .openApplication: return "Uygulama aç"
            case .openLink: return "Bağlantı aç"
            case .showNotice: return "Island'da yazı göster"
            case .startTimer: return "Zamanlayıcı başlat"
            case .pauseMedia: return "Çalanı durdur"
            case .runShortcut: return "Kısayol çalıştır"
            }
        }
    }

    private var trigger: AutomationTrigger {
        switch triggerKind {
        case .lidOpened: return .lidOpened
        case .lidClosing: return .lidClosing
        case .chargerConnected: return .chargerConnected
        case .chargerDisconnected: return .chargerDisconnected
        case .batteryBelow: return .batteryBelow(percent: Int(batteryPercent))
        case .mediaStarted: return .mediaStarted
        case .mediaStopped: return .mediaStopped
        case .timerFinished: return .timerFinished
        case .appLaunched: return .appLaunched(bundleIdentifier: triggerApp.identifier)
        case .appQuit: return .appQuit(bundleIdentifier: triggerApp.identifier)
        }
    }

    private var action: AutomationAction {
        switch actionKind {
        case .openApplication: return .openApplication(bundleIdentifier: actionApp.identifier, name: actionApp.name)
        case .openLink: return .openLink(link)
        case .showNotice: return .showNotice(notice)
        case .startTimer: return .startTimer(minutes: Int(minutes))
        case .pauseMedia: return .pauseMedia
        case .runShortcut: return .runShortcut(name: shortcut)
        }
    }

    private var canSave: Bool {
        guard action.isSafe else { return false }
        switch triggerKind {
        case .appLaunched, .appQuit: return !triggerApp.identifier.isEmpty
        default: return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.comfortable) {
            TextField("Kural adı", text: $rule.title)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            labelled("Ne olunca") {
                Picker("", selection: $triggerKind) {
                    ForEach(TriggerKind.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(maxWidth: 280)
            }
            if triggerKind == .batteryBelow {
                labelled("Eşik") {
                    HStack(spacing: MacBDesign.Space.regular) {
                        Slider(value: $batteryPercent,
                               in: Double(AutomationTrigger.batteryRange.lowerBound)...Double(AutomationTrigger.batteryRange.upperBound),
                               step: 5)
                            .frame(maxWidth: 200)
                        Text("%\(Int(batteryPercent))").font(.system(size: MacBDesign.TypeScale.body, weight: .semibold)).monospacedDigit()
                    }
                }
            }
            if triggerKind == .appLaunched || triggerKind == .appQuit {
                labelled("Uygulama") { appButton(triggerApp.name) { triggerApp = $0 } }
            }

            labelled("Ne yapsın") {
                Picker("", selection: $actionKind) {
                    ForEach(ActionKind.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(maxWidth: 280)
            }
            switch actionKind {
            case .openApplication:
                labelled("Uygulama") { appButton(actionApp.name) { actionApp = $0 } }
            case .openLink:
                labelled("Adres") {
                    TextField("https://", text: $link)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                }
            case .showNotice:
                labelled("Yazı") {
                    TextField("Kahve molası", text: Binding(
                        get: { notice },
                        set: { notice = String($0.prefix(AutomationAction.noticeLimit)) }))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                }
            case .startTimer:
                labelled("Süre") {
                    HStack(spacing: MacBDesign.Space.regular) {
                        Slider(value: $minutes,
                               in: Double(AutomationAction.timerRange.lowerBound)...Double(AutomationAction.timerRange.upperBound),
                               step: 1)
                            .frame(maxWidth: 200)
                        Text("\(Int(minutes)) dk").font(.system(size: MacBDesign.TypeScale.body, weight: .semibold)).monospacedDigit()
                    }
                }
            case .runShortcut:
                labelled("Kısayol adı") {
                    TextField("Kısayollar'daki ad", text: $shortcut)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                }
            case .pauseMedia:
                EmptyView()
            }

            if actionKind == .openLink {
                Text("Yalnızca http, https ve bu Mac'teki dosyalar açılır.")
                    .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
            }

            HStack(spacing: MacBDesign.Space.comfortable) {
                Button("Kaydet") {
                    var saved = rule
                    saved.trigger = trigger
                    saved.action = action
                    if saved.title.trimmingCharacters(in: .whitespaces).isEmpty {
                        saved.title = AutomationText.title(trigger)
                    }
                    save(saved)
                }
                .disabled(!canSave)
                Button("Vazgeç", action: cancel)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacBDesign.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: MacBDesign.Space.regular) {
            Text(title)
                .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                .frame(width: 92, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func appButton(_ name: String,
                           set: @escaping ((identifier: String, name: String)) -> Void) -> some View {
        Button(name.isEmpty ? "Uygulama seç…" : name) {
            if let chosen = AutomationText.chooseApplication() { set(chosen) }
        }
        .frame(maxWidth: 280, alignment: .leading)
    }
}
