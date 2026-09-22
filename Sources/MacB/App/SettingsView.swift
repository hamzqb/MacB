import AppKit
import MacBCore
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "Genel", windows = "Pencereler", widgets = "Widget'lar", tools = "Araçlar", watchers = "MacB AI", automation = "Otomasyon", appearance = "Görünüm", privacy = "Gizlilik", permissions = "İzinler", doctor = "Doğrulama"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .windows: return "rectangle.split.2x1"
        case .widgets: return "square.grid.2x2"
        case .tools: return "wrench.and.screwdriver"
        case .watchers: return "scope"
        case .automation: return "wand.and.rays"
        case .appearance: return "circle.lefthalf.filled"
        case .privacy: return "faceid"
        case .permissions: return "hand.raised"
        case .doctor: return "stethoscope"
        }
    }
    var subtitle: String {
        switch self {
        case .general: return "MacB, çalışma şekline uyum sağlasın."
        case .windows: return "Pencerelerini daha az uğraşla yerleştir."
        case .widgets: return "Island'da ne göründüğüne ve hangi sırada durduğuna sen karar ver."
        case .tools: return "Günlük işlerin için güvenli, yerel yardımcılar."
        case .watchers: return "Konuşarak takip, web işleri ve yerel otomasyon kur."
        case .automation: return "Bir şey olunca MacB senin yerine yapsın."
        case .appearance: return "Küçük ayrıntılar, daha sakin bir masaüstü."
        case .privacy: return "Özel alanlarını neyin açacağına sen karar ver."
        case .permissions: return "Hangi özelliklerin erişimi olacağı senin elinde."
        case .doctor: return "MacB'nin çalışan damarlarını tek ekranda kontrol et."
        }
    }
}

private enum ToolsArea: String, CaseIterable, Identifiable {
    case assistant, daily, system, cleanup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assistant: return "Kanka AI"
        case .daily: return "Günlük"
        case .system: return "Sistem"
        case .cleanup: return "Temizlik"
        }
    }

    var detail: String {
        switch self {
        case .assistant: return "Anahtar, ses, metin"
        case .daily: return "Mail, brifing, senaryo"
        case .system: return "Mac araçları"
        case .cleanup: return "Silme ve bakım"
        }
    }

    var symbol: String {
        switch self {
        case .assistant: return "sparkles"
        case .daily: return "sun.horizon"
        case .system: return "macwindow"
        case .cleanup: return "trash"
        }
    }
}

struct SettingsView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// What is being typed into the key field. Cleared as soon as it is stored.
    @State private var aiKeyDraft = ""
    /// What has been typed into each provider's field, by raw value. Cleared
    /// the moment a key is stored, so no key sits in a view for the session.
    @State private var keyDrafts: [String: String] = [:]
    /// Which ring the settings are editing: nil for the general one, or an
    /// application's bundle identifier.
    @State private var ringProfile: String?
    @ObservedObject var preferences: Preferences
    @ObservedObject var permissions: PermissionStore
    @ObservedObject var spotify: SpotifyService
    @ObservedObject var appleMusic: AppleMusicService
    @ObservedObject var browserMedia: BrowserMediaService
    @ObservedObject var camera: CameraPreviewService
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var hotKey: HotKeyController
    @ObservedObject var utilities: UtilityCoordinator
    @ObservedObject var aiActivity: AIActivityService
    @ObservedObject var systemMonitor: SystemMonitorService
    @ObservedObject var processes: ProcessMonitorService
    @ObservedObject var lid: LidAngleService
    @ObservedObject var keyboardCleaning: KeyboardCleaningService
    @ObservedObject var updates: UpdateService
    @ObservedObject var widgets: IslandLayoutStore
    @ObservedObject var background: IslandBackgroundStore
    @ObservedObject var weather: WeatherService
    @ObservedObject var faceUnlock: FaceUnlockService
    @ObservedObject var launcher: AppLauncherStore
    @ObservedObject var automation: AutomationService
    @ObservedObject var loginItem: LoginItemService
    @ObservedObject var aiKey: AIKeyStore
    @ObservedObject var aiCost: AICostMeter
    @ObservedObject var mail: MailService
    @ObservedObject var briefing: BriefingService
    @ObservedObject var scenarios: ScenarioStore
    @ObservedObject var assistant: AIAssistantService
    @ObservedObject var arrangements: WindowArrangementService
    @ObservedObject var keepAwake: KeepAwakeService
    @ObservedObject var watchers: WatchTaskStore
    @ObservedObject var agentCursor: AgentCursorOverlay
    @ObservedObject var autoQuit: AutoQuitOnCloseService
    @ObservedObject private var voiceStudio = VoiceStudio.shared
    @ObservedObject private var localModel = LocalModelStore.shared
    var jarvisHotKeyFailed = false
    @ObservedObject var jarvisMemory: JarvisMemoryStore
    var openPanel: () -> Void
    /// The name typed for the next saved window arrangement.
    @State private var arrangementName = ""
    /// The name typed for the next scenario.
    @State private var scenarioName = ""
    @AppStorage("settingsPage") private var selectedPage: SettingsPage = .general
    @State private var showRemovalConfirmation = false
    @State private var showCacheConfirmation = false
    @State private var processSort: ProcessSort = .memory
    @State private var selectedAIKeyProvider: AIProvider = .gemini
    @State private var selectedToolsArea: ToolsArea = .assistant
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: MacBDesign.contentSpacing) {
                    VStack(alignment: .leading, spacing: MacBDesign.Space.close) {
                        Text(selectedPage.rawValue)
                            .font(.system(size: MacBDesign.TypeScale.display, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text(selectedPage.subtitle)
                            .font(.system(size: MacBDesign.TypeScale.body))
                            .foregroundStyle(MacBDesign.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    switch selectedPage {
                    case .general: generalPage
                    case .windows: windowsPage
                    case .widgets: widgetsPage
                    case .tools: toolsPage
                    case .watchers: WatchersSettingsView(store: watchers, cursor: agentCursor)
                    case .automation: AutomationSettingsView(automation: automation, preferences: preferences)
                    case .appearance: appearancePage
                    case .privacy: PrivacySettingsView(faceUnlock: faceUnlock)
                    case .permissions: permissionsPage
                    case .doctor: doctorPage
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, MacBDesign.contentSpacing)
                .padding(.top, 30)
                .padding(.bottom, selectedPage == .watchers ? 58 : 28)
                .frame(maxWidth: 630, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.top)
            .onAppear {
                // Set by a launch argument that opens the window at one section.
                // Cleared straight away so the next launch starts at the top.
                let defaults = UserDefaults.standard
                guard let anchor = defaults.string(forKey: "settingsAnchor") else { return }
                defaults.removeObject(forKey: "settingsAnchor")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation { proxy.scrollTo(anchor, anchor: .top) }
                }
            }
            .onChange(of: utilities.removalCandidates.count) { _, count in
                // A scan fills a list that usually starts below the fold, so the
                // page moves to it rather than leaving the window looking unchanged.
                guard count > 0 else { return }
                withAnimation { proxy.scrollTo(Self.removalAnchor, anchor: .top) }
            }
            .onChange(of: utilities.cacheItems.count) { _, count in
                guard count > 0 else { return }
                withAnimation { proxy.scrollTo(Self.cacheAnchor, anchor: .top) }
            }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(MacBDesign.surface)
        .tint(MacBDesign.accent)
        .alert("Seçilen öğeler Çöp Sepeti’ne taşınsın mı?", isPresented: $showRemovalConfirmation) {
            Button("Vazgeç", role: .cancel) {}
            Button("Çöp Sepeti’ne Taşı", role: .destructive, action: utilities.removeInspectedApplication)
        } message: {
            Text("\(utilities.selectedApplicationName) için seçtiğin \(utilities.selectedRemovalCandidates.count) öğe Çöp Sepeti'ne taşınacak. Silinmez, istediğin an geri koyabilirsin.")
        }
        .alert("Seçilen önbellekler Çöp Sepeti’ne taşınsın mı?", isPresented: $showCacheConfirmation) {
            Button("Vazgeç", role: .cancel) {}
            Button("Çöp Sepeti’ne Taşı", role: .destructive, action: utilities.sweepCaches)
        } message: {
            Text("\(utilities.selectedCacheItems.count) klasör Çöp Sepeti'ne taşınacak, \(ByteCountFormatter.string(fromByteCount: utilities.cacheSize, countStyle: .file)) yer açılacak. Uygulamalar bu verileri gerektiğinde yeniden oluşturur.")
        }
    }

    private var windowsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Pencere yönetimi", "macwindow") {
                settingToggle("Pencere kısayolları", detail: "Etkin pencereyi ekranın yarısına, köşesine veya başka ekrana taşı.",
                              isOn: $preferences.windowManagementEnabled)
                if preferences.windowManagementEnabled {
                    message("Erişilebilirlik izni gerekir. Kısayollar her uygulamadaki etkin pencere üzerinde çalışır.")
                }
            }
            section("Son pencere kapanınca çık", "xmark.app") {
                settingToggle("Seçili uygulamaları Dock'ta açık bırakma",
                              detail: "Listendeki uygulamanın son penceresi kapanınca MacB onu nazikçe kapatır. Kaydedilmemiş iş varsa macOS yine sorar.",
                              isOn: $preferences.quitAppsWhenLastWindowCloses)
                HStack(spacing: MacBDesign.Space.regular) {
                    Menu("Uygulama ekle") {
                        let candidates = autoQuit.candidates
                        if candidates.isEmpty { Text("Eklenebilecek açık uygulama yok") }
                        ForEach(candidates) { app in
                            Button(app.name) { autoQuit.add(bundleIdentifier: app.bundleIdentifier, name: app.name) }
                        }
                    }
                    .fixedSize()
                    .disabled(!permissions.accessibility)
                    if !permissions.accessibility { Text("Erişilebilirlik izni gerekir.").foregroundStyle(MacBDesign.muted) }
                    Spacer(minLength: 8)
                }
                if autoQuit.trackedApps.isEmpty {
                    message("Henüz uygulama yok. Otomatik kapansın istediğin uygulamayı açıp buradan ekle.")
                } else {
                    VStack(spacing: MacBDesign.Space.snug) {
                        ForEach(autoQuit.trackedApps) { app in
                            HStack(spacing: MacBDesign.Space.regular) {
                                if let icon = app.icon {
                                    Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                                } else {
                                    Image(systemName: "app").frame(width: 24, height: 24)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name).font(.system(size: MacBDesign.TypeScale.body, weight: .semibold))
                                    Text(app.bundleIdentifier).font(.system(size: MacBDesign.TypeScale.micro, design: .monospaced)).foregroundStyle(MacBDesign.muted)
                                }
                                Spacer(minLength: 8)
                                Button("Çıkar") { autoQuit.remove(app) }
                            }
                            .padding(.vertical, MacBDesign.Space.hair)
                        }
                    }
                }
                if let note = autoQuit.lastMessage { message(note) }
            }
            if preferences.windowManagementEnabled {
                    section("Temel yerleşimler", "rectangle.split.2x1") {
                    shortcutRow("Sol yarı", symbol: "rectangle.lefthalf.filled", keys: "⌃⌥←")
                    rowDivider
                    shortcutRow("Sağ yarı", symbol: "rectangle.righthalf.filled", keys: "⌃⌥→")
                    rowDivider
                    shortcutRow("Üst yarı", symbol: "rectangle.tophalf.filled", keys: "⌃⌥↑")
                    rowDivider
                    shortcutRow("Alt yarı", symbol: "rectangle.bottomhalf.filled", keys: "⌃⌥↓")
                    rowDivider
                    shortcutRow("Büyüt", symbol: "rectangle.inset.filled", keys: "⌃⌥↩")
                    rowDivider
                    shortcutRow("Ortala", symbol: "rectangle.center.inset.filled", keys: "⌃⌥C")
                }
                    section("Köşeler ve ekranlar", "rectangle.split.2x2") {
                    shortcutRow("Sol üst / Sağ üst", symbol: "rectangle.split.2x1", keys: "⌃⌥U  /  ⌃⌥I")
                    rowDivider
                    shortcutRow("Sol alt / Sağ alt", symbol: "rectangle.split.2x1", keys: "⌃⌥J  /  ⌃⌥K")
                    rowDivider
                    shortcutRow("Önceki boyut", symbol: "arrow.uturn.backward", keys: "⌃⌥⌫")
                    rowDivider
                    shortcutRow("Sonraki ekran", symbol: "display.2", keys: "⌃⌥⌘→")
                }
            }
            section("Pencere düzenleri", "rectangle.3.group") {
                intro("Açık pencerelerin yerini kaydet, sonra tek hareketle geri getir. Sadece çalışan uygulamaların pencereleri taşınır; hiçbir şey açılmaz ya da kapanmaz.")
                if !permissions.accessibility {
                    message("Erişilebilirlik izni gerekir.", warning: true)
                }
                ForEach(arrangements.arrangements) { arrangement in
                    arrangementRow(arrangement)
                    rowDivider
                }
                HStack(spacing: MacBDesign.Space.regular) {
                    TextField("Ad (ör. Masa, Sunum)", text: $arrangementName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Düzen adı")
                    Button("Şimdiki düzeni kaydet") {
                        if arrangements.saveCurrent(named: arrangementName) != nil { arrangementName = "" }
                    }
                    .disabled(!permissions.accessibility)
                }
                if let note = arrangements.lastMessage { message(note) }
                Text("\u{201C}Ekran değişince\u{201D} açık olan düzen, aynı ekran düzeni geri geldiğinde (monitör takılınca, çıkarılınca) kendiliğinden uygulanır. Halkadaki Pencere düzeni dilimi bu ekrana ait düzeni, yoksa en yenisini uygular.")
                    .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func arrangementRow(_ arrangement: WindowArrangement) -> some View {
        HStack(spacing: MacBDesign.Space.regular) {
            Image(systemName: "rectangle.3.group").foregroundStyle(MacBDesign.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
                Text(arrangement.name).font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
                Text("\(arrangement.windows.count) pencere · \(arrangement.displays.summary)")
                    .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
            }
            Spacer(minLength: 8)
            Toggle("Ekran değişince", isOn: Binding(
                get: { arrangement.restoresAutomatically },
                set: { arrangements.setAutomatic(arrangement.id, $0) }))
                .toggleStyle(.checkbox)
                .help("Bu ekran düzeni geri geldiğinde kendiliğinden uygula")
            Button("Uygula") { arrangements.apply(arrangement) }
                .disabled(!permissions.accessibility)
            Menu {
                Button("Şimdiki pencerelerle güncelle") { arrangements.update(arrangement.id) }
                Button("Listeden çıkar") { arrangements.forget(arrangement.id) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("\(arrangement.name) seçenekleri")
        }
    }

    private var toolsAreaPicker: some View {
        HStack(spacing: MacBDesign.Space.snug) {
            ForEach(ToolsArea.allCases) { area in
                toolsAreaButton(area)
            }
        }
    }

    private func toolsAreaButton(_ area: ToolsArea) -> some View {
        let selected = selectedToolsArea == area
        return Button {
            selectedToolsArea = area
        } label: {
            HStack(spacing: MacBDesign.Space.close) {
                Image(systemName: area.symbol)
                    .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                    .foregroundStyle(selected ? MacBDesign.accent : MacBDesign.muted)
                    .frame(width: 24, height: 24)
                    .background(selected ? MacBDesign.accent.opacity(0.14) : Color.primary.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(area.title)
                        .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(area.detail)
                        .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
                        .foregroundStyle(MacBDesign.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MacBDesign.Space.regular)
            .padding(.vertical, MacBDesign.Space.snug)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(selected ? MacBDesign.accent.opacity(0.105) : Color.primary.opacity(0.028),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? MacBDesign.accent.opacity(0.45) : MacBDesign.cardStroke,
                              lineWidth: selected ? 1.1 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel("Araç kategorisi: \(area.title)")
    }

    private var toolsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            toolsAreaPicker
            if selectedToolsArea == .assistant {
            section("Claude ve Codex", "sparkles") {
                if aiActivity.statuses.isEmpty {
                    message("Açık masaüstü veya terminal oturumu bulunmadı.")
                } else {
                    ForEach(aiActivity.statuses.prefix(5)) { status in
                        HStack(spacing: MacBDesign.Space.regular) {
                            Image(systemName: status.kind.symbol).foregroundStyle(MacBDesign.accent).frame(width: 22)
                            VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
                                Text(status.kind.rawValue).font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
                                // The badge already says it is running, so the line
                                // below carries only what the badge cannot: where it
                                // is running and how much allowance is left.
                                Text([status.source, status.usage?.compactText].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                            }
                            Spacer(minLength: 8)
                            if status.isRunning { runningBadge }
                        }
                    }
                }
            }
            }
            if selectedToolsArea == .assistant {
            section("Yapay zekâ anahtarları", "key.horizontal") {
                intro("Halkadaki Yapay zekâ dilimi, menüdeki “Yapay zekâya sor” ve seçili metin işleri bu anahtarlarla çalışır. Anahtarlar Keychain'e yazılır, ekranda tekrar gösterilmez ve yalnız ait olduğu servise gider.")
                aiProviderHeader
                aiProviderStrip
                rowDivider
                providerRow(selectedAIKeyProvider)
                    .id(selectedAIKeyProvider.rawValue)
                if let error = aiKey.errorMessage { message(error, warning: true) }
                message("Anahtarını bir yere yapıştırdıysan onu iptal et ve yenisini üret. Sızmış bir anahtar senin faturana çalışır.", warning: true)
            }
            .onAppear(perform: chooseUsefulAIProvider)
            }
            if selectedToolsArea == .daily {
            section("Sesli senaryolar", "wand.and.stars") {
                intro("Birkaç işi tek isme bağla: \u{201C}toplantı moduna geç\u{201D} dediğinde pencereler düzene girsin, Mac uyanık kalsın, müzik dursun. Adımları burada sen yazarsın; MacB yalnız var olan bir senaryoyu çalıştırabilir, yenisini yazamaz.")
                HStack(spacing: MacBDesign.Space.regular) {
                    TextField("Yeni senaryo adı", text: $scenarioName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addScenario() }
                    Button("Ekle", action: addScenario)
                        .disabled(scenarioName.trimmingCharacters(in: .whitespaces).isEmpty
                                  || scenarios.scenarios.count >= ScenarioMatching.maximum)
                }
                if scenarios.scenarios.isEmpty {
                    message("Henüz senaryo yok. \u{201C}Toplantı modu\u{201D} iyi bir başlangıç.")
                } else {
                    ForEach(scenarios.scenarios) { scenario in
                        rowDivider
                        scenarioRow(scenario)
                    }
                }
                message("Kısayol adımı, Kısayollar uygulamasındaki kendi kısayolunu çalıştırır. MacB'nin kendi başına yapamadığı bir şeyi böyle ekleyebilirsin.")
            }
            }
            if selectedToolsArea == .system {
            section("Dock ve ⌘Tab", "dock.rectangle") {
                settingToggle("Dock'ta ve ⌘Tab'da görün",
                              detail: "Kapalıyken MacB yalnız island'da ve menü çubuğunda durur; ⌘Tab listesinde çıkmaz.",
                              isOn: $preferences.showInDock)
            }
            }
            if selectedToolsArea == .daily {
            section("Günaydın brifingi", "sun.horizon") {
                settingToggle("Brifingi göster",
                              detail: "Sabah Mac uyandığında island'da selam, hava, bugünkü ilk iş ve pil. Günde bir kez.",
                              isOn: $preferences.briefingEnabled)
                HStack(spacing: MacBDesign.Space.regular) {
                    Text("En erken saat").font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                    Spacer(minLength: 8)
                    Picker("Saat", selection: $preferences.briefingHour) {
                        ForEach(Briefing.hourChoices, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    .disabled(!preferences.briefingEnabled)
                }
                settingToggle("Sesli oku", detail: "Mac'in kendi Türkçe sesiyle ya da seçersen daha canlı bir Gemini sesiyle. İkisi de ücretsiz.",
                              isOn: $preferences.briefingSpeaks)
                    .disabled(!preferences.briefingEnabled)
                settingToggle("Dönünce özet",
                              detail: "10 dakikadan uzun ayrılıp dönünce: yeni mail, sıradaki toplantı. Söylenecek bir şey yoksa kart çıkmaz.",
                              isOn: $preferences.returnSummaryEnabled)
                settingToggle("Önemli şeyleri haber ver",
                              detail: "Önemli yeni mail ve 10 dakika sonra başlayacak toplantı island'da kısa bir satırla görünür.",
                              isOn: $preferences.headsUpEnabled)
                HStack(spacing: MacBDesign.Space.regular) {
                    Text("Ses").font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                    Spacer(minLength: 8)
                    Picker("Ses", selection: $preferences.briefingVoice) {
                        Text("En iyisi (otomatik)").tag("")
                        Section("Mac sesleri — ücretsiz, internetsiz") {
                            ForEach(TurkishSpeaker.installedTurkishVoices(), id: \.identifier) { voice in
                                Text(TurkishSpeaker.title(for: voice)).tag(voice.identifier)
                            }
                        }
                        Section("Gemini sesleri — ücretsiz, daha canlı") {
                            ForEach(GeminiSpeech.voices) { voice in Text(voice.title).tag(voice.tag) }
                        }
                    }
                    .labelsHidden().fixedSize()
                    .disabled(!preferences.briefingSpeaks)
                    previewButton(tag: briefingPreviewTag) { previewBriefingVoice() }
                        .disabled(!preferences.briefingSpeaks)
                }
                if GeminiSpeech.voice(forTag: preferences.briefingVoice) != nil {
                    message(aiKey.has(.gemini)
                            ? "Gemini sesinde brifing metni (hava, takvim başlıkları, mail gönderenleri) sese çevrilmek için Google'a gider; ücretsiz katmanda Google bunu eğitimde kullanabilir. Cevap gelmezse Mac'in kendi sesi okur."
                            : "Gemini sesi için Araçlar'dan bir Gemini anahtarı gir; o olmadan Mac'in kendi sesi okur.",
                            warning: !aiKey.has(.gemini))
                }
                HStack(spacing: MacBDesign.Space.close) {
                    Button("Sesi dene") { briefing.speak() }
                        .disabled(!briefing.isVisible)
                    Button("Daha iyi ses indir") {
                        SystemActions.openSettings(.spokenContent)
                    }
                    Spacer()
                }
                message(TurkishSpeaker.hasOnlyBasicVoices
                        ? "Bu Mac'te yalnız basit Türkçe ses var; o yüzden robot gibi okuyor. Sistem Ayarları \u{203A} Erişilebilirlik \u{203A} Sözlü İçerik'ten Cem ya da Yelda'nın \u{201C}Gelişmiş\u{201D} sürümünü indir — ücretsiz ve tek seferlik."
                        : "Daha doğal bir ton için Sözlü İçerik'ten \u{201C}Gelişmiş\u{201D} ya da \u{201C}Premium\u{201D} Türkçe sesi indirebilirsin; MacB en iyisini kendi seçer.",
                        warning: TurkishSpeaker.hasOnlyBasicVoices)
                HStack(spacing: MacBDesign.Space.close) {
                    Button("Şimdi dene") { briefing.give() }
                    if briefing.isVisible { Button("Kapat") { briefing.dismiss() } }
                    Spacer()
                }
                message("Her şey bu Mac'ten okunur, hiçbir yere gitmez, anahtar gerekmez. Takvim ve hatırlatıcılar yalnız izin verdiysen okunur.")
            }
            }
            if selectedToolsArea == .daily {
            section("Mail", "envelope") {
                settingToggle("Mail'e bakabilsin",
                              detail: "Brifing ve MacB, Apple Mail'de okunmamış maillerin kimden ve ne konuda olduğunu görebilir.",
                              isOn: $preferences.mailEnabled)
                intro("Yalnız gönderen, konu, saat ve bayrak okunur — mailin içeriği asla. Hiçbir şey kaydedilmez, hiçbir yere gönderilmez; MacB Mail'e sorar, Mail zaten senin Mac'inde. İlk açtığında macOS \u{201C}MacB, Mail'i kontrol etsin mi?\u{201D} diye sorar, istediğinde Sistem Ayarları \u{203A} Gizlilik ve Güvenlik \u{203A} Otomasyon'dan geri alabilirsin.")
                VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
                    Text("Önemli gönderenler")
                        .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
                    Text("Her satıra bir isim ya da adres. Bunlardan gelen ve bayrakladığın mailler \u{201C}önemli\u{201D} sayılır; gerisi sayılmaz.")
                        .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: Binding(
                        get: { preferences.importantSenders.joined(separator: "\n") },
                        set: { text in
                            preferences.importantSenders = text
                                .split(separator: "\n", omittingEmptySubsequences: true)
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }))
                        .font(.system(size: MacBDesign.TypeScale.body, design: .monospaced))
                        .frame(height: 76)
                        .padding(MacBDesign.Space.snug)
                        .background(MacBDesign.controlBackground,
                                    in: RoundedRectangle(cornerRadius: MacBDesign.Radius.control, style: .continuous))
                        .disabled(!preferences.mailEnabled)
                        .accessibilityLabel("Önemli gönderenler")
                }
                HStack(spacing: MacBDesign.Space.close) {
                    Button("Şimdi bak") { Task { await mail.refresh(force: true) } }
                        .disabled(!preferences.mailEnabled || mail.isReading)
                    Spacer()
                }
                if mail.summary.isUnavailable, let note = mail.summary.note {
                    message(note, warning: true)
                } else if mail.summary.unread > 0 {
                    message("\(mail.summary.unread) okunmamış mail · \(mail.important.count) önemli")
                }
            }
            }
            if selectedToolsArea == .assistant {
            section("Maliyet", "turkishlirasign.circle") {
                HStack(spacing: MacBDesign.Space.comfortable) {
                    costBox("Bugün", aiCost.todayText, "\(aiCost.today.requests) istek")
                    costBox("Bu ay", aiCost.monthText, "\(aiCost.spending.days.count) gün")
                    Spacer(minLength: 8)
                    Button("Sayacı sıfırla", role: .destructive) { aiCost.reset() }
                }
                HStack(spacing: MacBDesign.Space.regular) {
                    Text("Günlük sınır").font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                    Spacer(minLength: 8)
                    Picker("Günlük sınır", selection: $aiCost.dailyLimit) {
                        ForEach(AIBudget.choices, id: \.self) { Text(AIBudget.title($0)).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                if aiCost.dailyLimit > 0 {
                    budgetBar
                }
                message(aiCost.isOverDailyLimit
                        ? "Sınır doldu: sesli asistan ve ücretli sorular bugünlük kapalı. Ücretsiz sağlayıcılar çalışmaya devam eder."
                        : "Sınıra ulaşınca MacB ücretli isteği başlatmaz — para harcandıktan sonra değil, önce durur.",
                        warning: aiCost.isOverDailyLimit)
                message("Yalnız OpenAI'ye ödenen tahmini tutar sayılır; ücretsiz sağlayıcılar sıfır yazar. Sadece sayılar tutulur, hangi soruyu sorduğun değil. Kesin rakam OpenAI'nin panosundadır.")
            }
            }
            if selectedToolsArea == .assistant {
            section("Sesli asistan", "person.wave.2") {
                intro("MacB (okunuşu \u{201C}Mek bi\u{201D}) canlı sesli asistanın: konuşursun, konuşarak cevap verir, lafını bölebilirsin. İnternette araştırır, uygulama açar, müziği ve sesi yönetir, zamanlayıcı kurar, takvimine bakar, istersen ekranına bakıp okur.")
                settingToggle("\(JarvisHotKey.displayKeys) ile aç", detail: "Halkadaki \u{201C}MacB ile konuş\u{201D} dilimi ve menüdeki aynı adlı komut her zaman çalışır.",
                              isOn: $preferences.jarvisHotKeyEnabled)
                if jarvisHotKeyFailed {
                    message("\(JarvisHotKey.displayKeys) başka bir uygulama tarafından kullanılıyor.", warning: true)
                }
                HStack(spacing: MacBDesign.Space.regular) {
                    Text("Ses").font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                    Spacer(minLength: 8)
                    Picker("Ses", selection: $preferences.jarvisVoice) {
                        ForEach(JarvisVoice.ordered) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden().fixedSize()
                    previewButton(tag: "openai:" + preferences.jarvisVoice) {
                        VoiceStudio.shared.previewOpenAI(JarvisVoice(rawValue: preferences.jarvisVoice) ?? .marin)
                    }
                    .disabled(!aiKey.has(.openAI))
                }
                message("▶︎ her sesi bir kez OpenAI'den alır (yaklaşık $0.001) ve saklar; sonra dinlemek ücretsiz."
                        + (voiceStudio.errorMessage.map { " " + $0 } ?? ""))
                HStack(spacing: MacBDesign.Space.regular) {
                    Text("Karakter").font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                    Spacer(minLength: 8)
                    Picker("Karakter", selection: $preferences.jarvisPersona) {
                        ForEach(JarvisPersona.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden().fixedSize()
                }
                message((JarvisPersona(rawValue: preferences.jarvisPersona) ?? JarvisPersona.defaultPersona).note)
                HStack(spacing: MacBDesign.Space.regular) {
                    Text("Motor").font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                    Spacer(minLength: 8)
                    Picker("Motor", selection: $preferences.jarvisEngine) {
                        ForEach(JarvisEngineChoice.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden().fixedSize()
                }
                message((JarvisEngineChoice(rawValue: preferences.jarvisEngine) ?? .automatic).note)
                Toggle("Ücretsiz motor ekranı okuyabilsin", isOn: $preferences.freeEngineReadsScreen)
                    .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                message("Ekrandaki yazı ve düğme adları bu Mac'te okunur, ama cevap için ücretsiz sağlayıcıya (Gemini, Groq) gider; onlar ücretsiz katmanda bu metni eğitimde kullanabilir. Kapalıyken ekranı yalnız canlı motor okur. Yerel model kullanılırken bu ayar gerekmez: yazı Mac'ten çıkmaz.")
                rowDivider
                localModelRows
                rowDivider
                HStack(spacing: MacBDesign.Space.regular) {
                    Text("Canlı model").font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                    Spacer(minLength: 8)
                    Picker("Model", selection: $preferences.jarvisModel) {
                        ForEach(JarvisProtocol.models, id: \.self) {
                            Text("\($0) — \(JarvisProtocol.priceNote(for: $0))").tag($0)
                        }
                        if !JarvisProtocol.models.contains(preferences.jarvisModel) {
                            Text(preferences.jarvisModel).tag(preferences.jarvisModel)
                        }
                    }
                    .labelsHidden().fixedSize()
                }
                message("MacB her zaman Türkçe konuşur; ona başka dilde yazsan da Türkçe cevap verir.")
                message("Sesli asistan açıkken mikrofon sesi canlı olarak OpenAI'ye gider (Sesle sor'dan farkı bu). Kaydedilmez; panel kapanınca, 30 saniye sessiz kalınca ya da 6 dakika dolunca bağlantı kapanır.")
                message("Canlı ses ücretlidir ve sessizlik de sayılır. Ucuz tutmanın yolu: \u{201C}mini\u{201D} modeli, kısa konuşma, Maliyet'teki günlük sınır.", warning: true)
                message("Ekrandan, seçimden ya da internetten bir şey okuduktan sonra MacB bir şey açmak, panoya koymak ya da not almak isterse önce sana sorar. Böylece bir sayfadaki yazı onu yönlendiremez.")
                rowDivider
                HStack {
                    Text("Hafıza (\(jarvisMemory.facts.count))").font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                    Spacer()
                    Button("Dosyayı göster") {
                        NSWorkspace.shared.activateFileViewerSelecting([jarvisMemory.fileURL])
                    }
                    .disabled(jarvisMemory.facts.isEmpty)
                    Button("Hepsini unut", role: .destructive) { jarvisMemory.removeAll() }
                        .disabled(jarvisMemory.facts.isEmpty)
                }
                if jarvisMemory.facts.isEmpty {
                    message("MacB'ye \u{201C}bunu aklında tut\u{201D} dediğin şeyler burada durur ve her konuşmada ona hatırlatılır.")
                } else {
                    ForEach(Array(jarvisMemory.facts.enumerated()), id: \.offset) { index, fact in
                        HStack(alignment: .top, spacing: MacBDesign.Space.regular) {
                            Text(fact).font(.system(size: MacBDesign.TypeScale.caption))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Button { jarvisMemory.remove(at: index) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).foregroundStyle(MacBDesign.muted)
                                .accessibilityLabel("Bunu unut: \(fact)")
                        }
                    }
                }
            }
            }
            if selectedToolsArea == .assistant {
            section("Seçili metin ve ses", "text.line.3.summary") {
                intro("Halkaya Seçimi özetle, Seçimi düzelt, Seçimi çevir ve Sesle sor dilimlerini ekleyebilirsin. Sonuç panele gelir ve panoya kopyalanır; uygulama izin veriyorsa seçimin yerine de konabilir.")
                HStack(spacing: MacBDesign.Space.regular) {
                    Text("Çeviri dili").font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                    Spacer(minLength: 8)
                    Picker("Çeviri dili", selection: $preferences.translationTarget) {
                        ForEach(TranslationDirection.choices, id: \.code) { Text($0.title).tag($0.code) }
                    }
                    .labelsHidden().fixedSize()
                }
                Text("Çeviri tamamen bu Mac'te yapılır, anahtar gerekmez ve metin hiçbir yere gitmez. Metin zaten bu dildeyse İngilizceye çevrilir (İngilizce seçiliyse Türkçeye). Dil paketi yoksa macOS Ayarlar'ından indirilir.")
                    .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
                rowDivider
                Text("Özetleme ve düzeltme OpenAI anahtarıyla çalışır: yalnız o an seçtiğin metin gönderilir, en fazla \(AITextTask.maximumLength) karakter. Parola alanları okunmaz.")
                    .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Sesle sor: konuşma bu Mac'te yazıya çevrilir, ses kaydedilmez ve gönderilmez; OpenAI'ye yalnız yazı gider. İlk kullanımda mikrofon ve konuşma tanıma izni istenir.")
                    .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
            if selectedToolsArea == .daily {
            section("Uyanık tut", "cup.and.heat.waves") {
                HStack(spacing: MacBDesign.Space.regular) {
                    VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
                        Text(keepAwake.isActive ? "Açık" : "Kapalı")
                            .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
                        Text(keepAwake.isActive
                             ? (keepAwake.endDate == nil ? "Sen kapatana kadar ekran uyumaz." : "\(keepAwake.remainingText) sonra kapanır.")
                             : "Ekran ve Mac, süre bitene kadar uykuya geçmez. Kapak kapanınca Mac yine uyur.")
                            .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                    }
                    Spacer(minLength: 8)
                    Button(keepAwake.isActive ? "Kapat" : "Başlat") {
                        keepAwake.toggle(minutes: preferences.keepAwakeMinutes)
                    }
                }
                HStack(spacing: MacBDesign.Space.regular) {
                    Text("Halkadan başlatınca").font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                    Spacer(minLength: 8)
                    Picker("Süre", selection: $preferences.keepAwakeMinutes) {
                        ForEach(KeepAwakeDuration.choices, id: \.self) { Text(KeepAwakeDuration.title(minutes: $0)).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            }
            if selectedToolsArea == .system {
            section("Sistem", "gauge.with.dots.needle.67percent") {
                HStack(spacing: MacBDesign.Space.regular) {
                    systemMetric("CPU", "\(Int(systemMonitor.snapshot.cpuUsage))%",
                                 fraction: systemMonitor.snapshot.cpuUsage / 100)
                    systemMetric("RAM", percentage(systemMonitor.snapshot.usedMemory, systemMonitor.snapshot.totalMemory),
                                 fraction: fraction(systemMonitor.snapshot.usedMemory, systemMonitor.snapshot.totalMemory))
                    systemMetric("Disk", percentage(UInt64(max(0, systemMonitor.snapshot.totalDisk - systemMonitor.snapshot.availableDisk)), UInt64(max(0, systemMonitor.snapshot.totalDisk))),
                                 fraction: fraction(UInt64(max(0, systemMonitor.snapshot.totalDisk - systemMonitor.snapshot.availableDisk)), UInt64(max(0, systemMonitor.snapshot.totalDisk))))
                    systemMetric("Pil", systemMonitor.snapshot.batteryPercent.map { "\(Int($0))%" } ?? "—",
                                 fraction: systemMonitor.snapshot.batteryPercent.map { $0 / 100 })
                }
                Label(thermalText, systemImage: "thermometer.medium")
                    .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
            }
            }
            if selectedToolsArea == .system {
            section("Klavye temizleme", "keyboard") {
                Text("Klavye girişini geçici olarak durdurur. Fare çalışır; üç kez Esc acil çıkıştır.")
                    .font(.system(size: MacBDesign.TypeScale.body)).foregroundStyle(MacBDesign.muted)
                HStack(spacing: MacBDesign.Space.regular) {
                    if keyboardCleaning.isActive {
                        Button("Kilidi aç", action: keyboardCleaning.stop)
                        Text("\(keyboardCleaning.remainingSeconds) sn").font(.system(size: MacBDesign.TypeScale.caption, design: .monospaced)).foregroundStyle(MacBDesign.muted)
                    } else {
                        Button("30 saniye") { keyboardCleaning.start(duration: 30) }
                        Button("1 dakika") { keyboardCleaning.start(duration: 60) }
                        Button("2 dakika") { keyboardCleaning.start(duration: 120) }
                    }
                }
                if let error = keyboardCleaning.errorMessage { message(error, warning: true) }
            }
            }
            if selectedToolsArea == .system {
            section("Arşiv", "doc.zipper") {
                Text("Dosyaları MacB içinde ZIP olarak sıkıştır veya güvenli biçimde çıkar.")
                    .font(.system(size: MacBDesign.TypeScale.body)).foregroundStyle(MacBDesign.muted)
                HStack(spacing: MacBDesign.Space.regular) {
                    Button("ZIP oluştur…", action: utilities.createArchive)
                    Button("ZIP çıkar…", action: utilities.extractArchive)
                }
            }
            }
            if selectedToolsArea == .cleanup {
            section("Uygulama kaldırma", "trash") {
                Color.clear.frame(height: 0).id(Self.removalAnchor)
                intro("Uygulamayı, yardımcılarını ve kullanıcı kalıntılarını arar. Hiçbir şey silinmez, hepsi Çöp Sepeti'ne taşınır.")
                Button("Uygulama seç…") {
                    Task {
                        if faceUnlock.settings.guards(.uninstaller) && !faceUnlock.isUnlocked(.uninstaller) {
                            guard await faceUnlock.requestAccess(to: .uninstaller) else { return }
                        }
                        utilities.inspectApplication()
                    }
                }
                if !utilities.removalCandidates.isEmpty {
                    VStack(alignment: .leading, spacing: MacBDesign.Space.comfortable) {
                        removalHeader
                        if utilities.inspectedIsRunning { removalRunningNotice }
                        ForEach(utilities.removalGroups, id: \.confidence) { group in
                            removalGroup(group.confidence, group.candidates)
                        }
                        Button("Seçilenleri Çöp Sepeti’ne taşı", role: .destructive) { showRemovalConfirmation = true }
                            .disabled(utilities.selectedRemovalCandidates.isEmpty)
                    }
                    .padding(MacBDesign.Space.comfortable)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            }
            if selectedToolsArea == .cleanup {
            section("Kaynak kullanımı", "chart.bar.xaxis") {
                intro("Belleği ve işlemciyi en çok kim kullanıyor. Yardımcı süreçler kendi uygulamalarının altında toplanır.")
                Picker("", selection: $processSort) {
                    Text("Bellek").tag(ProcessSort.memory)
                    Text("İşlemci").tag(ProcessSort.cpu)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                VStack(spacing: 0) {
                    ForEach(processSort == .memory ? processes.byMemory : processes.byCPU) { usage in
                        processRow(usage)
                    }
                }
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: MacBDesign.Space.regular) {
                    Button("Yenile", action: processes.refresh)
                    Text("Her 6 saniyede bir kendiliğinden yenilenir.")
                        .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                }
            }
            }
            if selectedToolsArea == .cleanup {
            section("Önbellek temizliği", "sparkles.rectangle.stack") {
                Color.clear.frame(height: 0).id(Self.cacheAnchor)
                intro("Uygulamaların yeniden oluşturabildiği geçici klasörleri arar. Belgeler, ayarlar ve uygulama verileri hiç taranmaz.")
                Button(utilities.hasScannedCaches ? "Yeniden tara" : "Önbellekleri tara", action: utilities.scanCaches)
                if !utilities.cacheItems.isEmpty {
                    VStack(alignment: .leading, spacing: MacBDesign.Space.comfortable) {
                        cacheHeader
                        ForEach(utilities.cacheGroups, id: \.group) { group in
                            cacheGroupView(group.group, group.items)
                        }
                        Button("Seçilenleri Çöp Sepeti’ne taşı", role: .destructive) { showCacheConfirmation = true }
                            .disabled(utilities.selectedCacheItems.isEmpty)
                    }
                    .padding(MacBDesign.Space.comfortable)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            }
            if selectedToolsArea == .system {
            section("MacWhisper", "waveform") {
                Text(utilities.macWhisperInstalled ? "Ses veya video dosyasını MacWhisper’a gönder." : "MacWhisper kurulu değil.")
                    .font(.system(size: MacBDesign.TypeScale.body)).foregroundStyle(MacBDesign.muted)
                Button("Dosya gönder…", action: utilities.sendAudioToMacWhisper).disabled(!utilities.macWhisperInstalled)
            }
            }
            if utilities.isWorking { ProgressView().controlSize(.small) }
            if let status = utilities.statusMessage { message(status, warning: false) }
            undoRow
        }
        .onAppear { systemMonitor.refresh() }
    }

    /// The offer to put the last batch back.
    ///
    /// macOS tells us where each item landed in the Trash, so "geri almak için
    /// Çöp Sepeti'nden çıkar" was MacB handing the user a job it could do
    /// itself. The offer stands until the next sweep, and it refuses any item
    /// whose old path has been taken back in the meantime rather than
    /// overwriting it.
    @ViewBuilder private var undoRow: some View {
        if utilities.canUndoTrashMove, let title = utilities.undoableTitle {
            HStack(spacing: MacBDesign.Space.regular) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: MacBDesign.TypeScale.body, weight: .semibold))
                    .foregroundStyle(MacBDesign.accent)
                intro("\(title) Çöp Sepeti'nde. Eski yerine geri konabilir.")
                Spacer(minLength: MacBDesign.Space.close)
                Button("Geri al", action: utilities.undoLastTrashMove)
                Button("Kapat", action: utilities.forgetTrashMove)
                    .buttonStyle(.plain)
                    .foregroundStyle(MacBDesign.muted)
            }
            .padding(MacBDesign.Space.comfortable)
            .background(MacBDesign.cardFill, in: RoundedRectangle(cornerRadius: MacBDesign.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MacBDesign.Radius.card, style: .continuous)
                .strokeBorder(MacBDesign.cardStroke, lineWidth: 0.5))
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: MacBDesign.Space.regular) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .font(.system(size: MacBDesign.TypeScale.heading, weight: .medium))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 36, height: 36)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                Text("MacB").font(.system(size: MacBDesign.TypeScale.heading, weight: .semibold))
            }
            .padding(.horizontal, MacBDesign.Space.regular)
            VStack(spacing: MacBDesign.Space.snug) {
                ForEach(SettingsPage.allCases) { page in
                    Button { selectedPage = page } label: {
                        HStack(spacing: MacBDesign.Space.regular) {
                            Image(systemName: page.icon)
                                .font(.system(size: MacBDesign.TypeScale.title, weight: .medium))
                                .foregroundStyle(selectedPage == page ? MacBDesign.accent : MacBDesign.muted)
                                .frame(width: 19)
                                .accessibilityHidden(true)
                            Text(page.rawValue).font(.system(size: MacBDesign.TypeScale.emphasis, weight: selectedPage == page ? .medium : .regular))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, MacBDesign.Space.comfortable)
                        .padding(.vertical, MacBDesign.Space.regular)
                        .contentShape(Rectangle())
                        .background(selectedPage == page ? MacBDesign.accent.opacity(0.11) : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedPage == page ? [.isSelected] : [])
                }
            }
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
                Text("Ücretsiz ve açık kaynak").font(.system(size: MacBDesign.TypeScale.micro))
                Text("Sürüm \(AppVersion.current)").font(.system(size: MacBDesign.TypeScale.micro, design: .monospaced))
            }
            .foregroundStyle(MacBDesign.muted)
            .padding(.horizontal, MacBDesign.Space.regular)
        }
        .padding(.horizontal, MacBDesign.Space.comfortable)
        .padding(.top, 29)
        .padding(.bottom, MacBDesign.Space.wide)
        .frame(width: MacBDesign.sidebarWidth)
        .background(Color.primary.opacity(0.025))
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Açılış", "power") {
                settingToggle("Mac açılınca MacB de açılsın",
                              detail: "Giriş öğesi olarak macOS'a kaydedilir. Sistem Ayarları'ndaki Giriş Öğeleri listesinden MacB'ye sormadan kapatabilirsin.",
                              isOn: Binding(get: { loginItem.isEnabled },
                                            set: { loginItem.setEnabled($0) }))
                if loginItem.needsApproval {
                    message("macOS bu girişi bekletiyor. Sistem Ayarları'ndan izin vermen gerekiyor.", warning: true)
                    Button("Giriş Öğeleri'ni aç") { loginItem.openSystemSettings() }
                        .buttonStyle(.link)
                }
                if let error = loginItem.errorMessage { message(error, warning: true) }
            }
            section("Çalışma alanı", "square.stack.3d.up") {
                settingToggle("Dock önizlemeleri", detail: "Bir simgenin üzerinde bekle, istediğin pencereye geç.", isOn: $preferences.dockEnabled)
                rowDivider
                settingToggle("Notch paneli", detail: "Medya, dosya, pano ve işlerini ekranın üst kenarından aç.", isOn: $preferences.notchEnabled)
                rowDivider
                settingToggle("Pencere seçici", detail: "Kısayolu basılı tut, Tab ile ilerle, bırakarak seç.", isOn: $preferences.switcherEnabled)
                if preferences.switcherEnabled {
                    HStack(spacing: MacBDesign.Space.comfortable) {
                        Text("Klavye kısayolu").font(.system(size: MacBDesign.TypeScale.body)).foregroundStyle(MacBDesign.muted)
                        Spacer(minLength: 4)
                        Picker("Klavye kısayolu", selection: $preferences.shortcut) {
                            ForEach(SwitcherShortcut.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 144)
                    }
                    .padding(.top, MacBDesign.Space.hair)
                }
                if let shortcutError = hotKey.registrationError { message(shortcutError, warning: true) }
            }
            section("Akıllı akış", "wand.and.stars") {
                settingToggle("Akıllı Notch", detail: "Panel açılırken müzik, raf ve indirme durumuna göre doğru bölümü öne çıkar.", isOn: $preferences.smartNotchEnabled)
                rowDivider
                settingToggle("Favori pencereler", detail: "Yıldızladığın pencereleri Dock ve pencere seçicide üstte tut.", isOn: $preferences.favoriteWindowsEnabled)
                rowDivider
                settingToggle("Uygulama grupları", detail: "Pencere seçicide aynı uygulamanın pencerelerini birlikte göster.", isOn: $preferences.groupedWindowsEnabled)
                rowDivider
                settingToggle("Odak modu", detail: "Seçtiğin pencere öne gelirken diğer uygulamaları gizle.", isOn: $preferences.focusModeEnabled)
            }
            section("Dosya rafı", "tray.full") {
                VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
                    Text(shelf.items.isEmpty ? "Dosyaların için küçük bir yer." : "\(shelf.items.count) öğe elinin altında.")
                        .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
                    intro("Dosyalar yerinde kalır. Raftan kaldırmak dosyayı silmez.")
                }
                HStack(spacing: MacBDesign.Space.regular) {
                    Button("Dosya ekle…", action: shelf.chooseFiles)
                    Button("Paneli aç", action: openPanel).disabled(!preferences.notchEnabled)
                }
                .controlSize(.regular)
                if !preferences.notchEnabled {
                    message("Paneli açmak için Notch panelini etkinleştir.")
                }
                if let error = shelf.errorMessage { message(error, warning: true) }
            }
            section("Güncellemeler", "arrow.triangle.2.circlepath") {
                HStack(spacing: MacBDesign.Space.regular) {
                    VStack(alignment: .leading, spacing: MacBDesign.Space.tight) {
                        Text(updateTitle).font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
                        Text(updateDetail).font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                    }
                    Spacer()
                    if case .checking = updates.state { ProgressView().controlSize(.small) }
                    else if case .available = updates.state { Button("İndir", action: updates.openReleases) }
                    else { Button("Denetle") { updates.check() } }
                }
            }
        }
    }

    private var updateTitle: String {
        switch updates.state {
        case .available(let version): return "MacB \(version) hazır"
        case .current: return "MacB güncel"
        case .checking: return "Güncellemeler denetleniyor"
        case .failed: return "Güncelleme denetlenemedi"
        case .idle: return "Yeni sürümleri denetle"
        }
    }

    private var updateDetail: String {
        switch updates.state {
        case .available: return "Yeni sürümü doğrulanmış GitHub Releases sayfasından indirebilirsin."
        case .current: return "Şu anda \(AppVersion.current) sürümünü kullanıyorsun."
        case .checking: return "GitHub Releases kontrol ediliyor."
        case .failed(let message): return message
        case .idle: return "MacB günde en fazla bir kez yeni sürüm kontrolü yapar."
        }
    }

    private var widgetsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Şeritte (\(widgets.layout.enabledWidgets.count))", "rectangle.grid.1x2") {
                if widgets.layout.enabledWidgets.isEmpty {
                    Text("Şerit boş. Aşağıdaki kütüphaneden widget ekle.")
                        .font(.system(size: MacBDesign.TypeScale.body)).foregroundStyle(MacBDesign.muted)
                } else {
                    ForEach(Array(widgets.layout.enabledWidgets.enumerated()), id: \.element.id) { index, widget in
                        if index > 0 { rowDivider }
                        activeWidgetRow(widget, index: index,
                                        count: widgets.layout.enabledWidgets.count)
                    }
                }
            }
            ForEach(libraryGroups) { group in
                section("\(group.category.title) kütüphanesi", group.category.symbol) {
                    ForEach(Array(group.widgets.enumerated()), id: \.element.id) { index, widget in
                        if index > 0 { rowDivider }
                        libraryWidgetRow(widget)
                    }
                }
            }
            if widgets.isActive(.worldClock) {
                section("Dünya saati", "globe") {
                    Picker("Şehir", selection: $preferences.secondaryTimeZone) {
                        ForEach(WorldClockWidget.choices, id: \.identifier) { choice in
                            Text(choice.name).tag(choice.identifier)
                        }
                    }
                    .frame(maxWidth: 320)
                    Text("Widget yerel saatin yanında bu şehri gösterir. Kartın üstünde sağ tıklayarak da değiştirebilirsin.")
                        .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            section("Hava durumu", "cloud.sun") {
                Picker("Kart stili", selection: $preferences.weatherWidgetStyle) {
                    ForEach(WeatherWidgetStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                settingToggle("Şehir yoksa konumumu kullan",
                              detail: "MacB yalnız bir kez yaklaşık konum ister; takip etmez ve koordinatı diske yazmaz.",
                              isOn: $weather.usesCurrentLocation)
                HStack(spacing: MacBDesign.Space.regular) {
                    TextField(weather.usesCurrentLocation ? "Boş bırak: konumdan bul" : "Şehir", text: Binding(
                        get: { weather.placeQuery },
                        set: { weather.placeQuery = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .accessibilityLabel("Hava durumu şehri")
                    if weather.isLoading { ProgressView().controlSize(.small) }
                    Button("Şimdi dene") { weather.refresh(force: true) }
                    Spacer()
                }
                Text("Şehir yazarsan Open-Meteo şehir adıyla çalışır. Boş bırakırsan konum izniyle lat/lon üzerinden hızlı bakar.")
                    .font(.system(size: MacBDesign.TypeScale.caption))
                    .foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let snapshot = weather.snapshot {
                    Label("\(snapshot.place) · \(snapshot.temperature)° · \(snapshot.condition)", systemImage: snapshot.symbol)
                        .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
                        .foregroundStyle(MacBDesign.accent)
                }
                if let error = weather.errorMessage {
                    Text(error).font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(.orange)
                }
            }
            section("Medya görünümü", "music.note") {
                Picker("Kart stili", selection: $preferences.mediaWidgetStyle) {
                    ForEach(MediaWidgetStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Text("Şeride sığmayan widget'lar alt satıra iner, hiçbiri kırpılmaz.")
                    .font(.system(size: MacBDesign.TypeScale.body)).foregroundStyle(MacBDesign.muted)
                Spacer()
                Button("Varsayılana dön", action: widgets.reset)
            }
        }
    }

    /// A widget already on the strip: order, width and a way off the strip.
    private func activeWidgetRow(_ widget: IslandWidget, index: Int, count: Int) -> some View {
        HStack(spacing: MacBDesign.Space.comfortable) {
            widgetGlyph(widget.kind, isActive: true)
            VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
                Text(widget.kind.title).font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
                Text(widget.kind.summary).font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { widget.size },
                set: { widgets.resize(id: widget.id, to: $0) }
            )) {
                ForEach(IslandWidgetSize.allCases, id: \.rawValue) { size in
                    Text(sizeTitle(size)).tag(size)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)
            .accessibilityLabel("\(widget.kind.title) boyutu")
            VStack(spacing: MacBDesign.Space.hair) {
                stepButton("chevron.up", label: "Yukarı taşı", enabled: index > 0) {
                    widgets.moveVisible(id: widget.id, by: -1)
                }
                stepButton("chevron.down", label: "Aşağı taşı", enabled: index < count - 1) {
                    widgets.moveVisible(id: widget.id, by: 1)
                }
            }
            Button("Çıkar") { widgets.setEnabled(id: widget.id, false) }
                .accessibilityLabel("\(widget.kind.title) widget'ını çıkar")
        }
        .padding(.vertical, MacBDesign.Space.tight)
    }

    /// A widget the strip does not have yet. One button, and it lands at the end.
    private func libraryWidgetRow(_ widget: IslandWidget) -> some View {
        HStack(spacing: MacBDesign.Space.comfortable) {
            widgetGlyph(widget.kind, isActive: widget.isEnabled)
            VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
                Text(widget.kind.title).font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
                Text(widget.kind.summary).font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
            }
            Spacer()
            if widget.isEnabled {
                Label("Şeritte", systemImage: "checkmark")
                    .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
                    .foregroundStyle(MacBDesign.accent)
            } else {
                Button("Ekle") { widgets.add(id: widget.id) }
                    .accessibilityLabel("\(widget.kind.title) widget'ını ekle")
            }
        }
        .padding(.vertical, MacBDesign.Space.tight)
    }

    private func widgetGlyph(_ kind: IslandWidgetKind, isActive: Bool) -> some View {
        Image(systemName: kind.symbol)
            .font(.system(size: MacBDesign.TypeScale.body, weight: .semibold))
            .foregroundStyle(isActive ? MacBDesign.accent : MacBDesign.muted)
            .frame(width: 26, height: 26)
            .background(MacBDesign.cardFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var libraryGroups: [IslandWidgetGroup] { widgets.layout.groups }

    private static let removalAnchor = "removal-review"
    /// Named so a launch argument can open the window straight at the hinge
    /// settings instead of leaving somebody to scroll for them.
    static let hingeAnchor = "lid-hinge"

    private var removalHeader: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
            Text(utilities.selectedApplicationName).font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold))
            Text("\(utilities.removalCandidates.count) öğe bulundu · \(utilities.selectedRemovalCandidates.count) seçili · \(ByteCountFormatter.string(fromByteCount: utilities.removalSize, countStyle: .file))")
                .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
        }
    }

    private var removalRunningNotice: some View {
        HStack(spacing: MacBDesign.Space.regular) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Uygulama açık. Kapatılmadan kendi paketi taşınamaz.")
                .font(.system(size: MacBDesign.TypeScale.caption))
            Spacer()
            Button("Kapat", action: utilities.quitInspectedApplication)
        }
        .padding(MacBDesign.Space.regular)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder
    private func removalGroup(_ confidence: AppLeftoverConfidence,
                              _ candidates: [AppRemovalCandidate]) -> some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
            HStack(spacing: MacBDesign.Space.snug) {
                Text(confidence.title).font(.system(size: MacBDesign.TypeScale.body, weight: .semibold))
                Text("\(candidates.count)")
                    .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                    .padding(.horizontal, MacBDesign.Space.snug).padding(.vertical, MacBDesign.Space.hair)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                Spacer()
            }
            Text(confidence.detail).font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
            ForEach(candidates) { candidate in removalRow(candidate) }
        }
    }

    private func removalRow(_ candidate: AppRemovalCandidate) -> some View {
        HStack(alignment: .top, spacing: MacBDesign.Space.close) {
            Toggle(isOn: Binding(get: { utilities.isSelected(candidate) },
                                 set: { _ in utilities.toggleRemoval(candidate) })) {
                VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
                    HStack(spacing: MacBDesign.Space.snug) {
                        Text(candidate.kind.title).font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
                        Text(candidate.sizeText)
                            .font(.system(size: MacBDesign.TypeScale.micro)).foregroundStyle(MacBDesign.muted)
                        if candidate.requiresAdministrator {
                            Text("yönetici gerekir")
                                .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
                                .padding(.horizontal, MacBDesign.Space.snug).padding(.vertical, MacBDesign.Space.hair)
                                .background(Color.orange.opacity(0.18), in: Capsule())
                        }
                    }
                    Text(candidate.displayPath)
                        .font(.system(size: MacBDesign.TypeScale.micro, design: .monospaced))
                        .foregroundStyle(MacBDesign.muted)
                        .lineLimit(2)
                        .help(candidate.url.path)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(candidate.requiresAdministrator)
            Spacer(minLength: 0)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
            } label: {
                Image(systemName: "folder").font(.system(size: MacBDesign.TypeScale.micro))
            }
            .buttonStyle(.borderless)
            .help("Finder'da göster")
            .accessibilityLabel("Finder'da göster")
        }
    }

    private static let cacheAnchor = "cache-review"

    private func processRow(_ usage: ProcessUsage) -> some View {
        HStack(spacing: MacBDesign.Space.regular) {
            if let icon = processes.icon(for: usage) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "gearshape").font(.system(size: MacBDesign.TypeScale.body))
                    .foregroundStyle(MacBDesign.muted).frame(width: 18)
            }
            VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
                Text(usage.name).font(.system(size: MacBDesign.TypeScale.body, weight: .medium)).lineLimit(1)
                if usage.processCount > 1 {
                    Text("\(usage.processCount) süreç")
                        .font(.system(size: MacBDesign.TypeScale.micro)).foregroundStyle(MacBDesign.muted)
                }
            }
            Spacer(minLength: 8)
            Text("\(usage.cpuPercent, specifier: "%.1f")%")
                .font(.system(size: MacBDesign.TypeScale.caption)).monospacedDigit()
                .foregroundStyle(MacBDesign.muted)
                .frame(width: 52, alignment: .trailing)
            Text(ByteCountFormatter.string(fromByteCount: Int64(usage.memoryBytes), countStyle: .memory))
                .font(.system(size: MacBDesign.TypeScale.body, weight: .semibold)).monospacedDigit()
                .frame(width: 76, alignment: .trailing)
            // Only a real application is ever asked to quit, and it is asked the
            // way the Dock asks: unsaved work still gets to object.
            Button("Kapat") { processes.quit(usage) }
                .disabled(!processes.canQuit(usage))
        }
        .padding(.horizontal, MacBDesign.Space.comfortable)
        .padding(.vertical, MacBDesign.Space.close)
    }

    private var cacheHeader: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
            Text("Geri kazanılabilir alan").font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold))
            Text("\(utilities.cacheItems.count) klasör · \(utilities.selectedCacheItems.count) seçili · \(ByteCountFormatter.string(fromByteCount: utilities.cacheSize, countStyle: .file))")
                .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
        }
    }

    @ViewBuilder
    private func cacheGroupView(_ group: CacheSweepGroup, _ items: [CacheSweepItem]) -> some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
            HStack(spacing: MacBDesign.Space.snug) {
                Image(systemName: group.symbol).font(.system(size: MacBDesign.TypeScale.caption))
                Text(group.title).font(.system(size: MacBDesign.TypeScale.body, weight: .semibold))
                Text("\(items.count)")
                    .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                    .padding(.horizontal, MacBDesign.Space.snug).padding(.vertical, MacBDesign.Space.hair)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                Spacer()
            }
            Text(group.summary).font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(items) { item in cacheRow(item) }
        }
    }

    private func cacheRow(_ item: CacheSweepItem) -> some View {
        HStack(alignment: .top, spacing: MacBDesign.Space.close) {
            Toggle(isOn: Binding(get: { utilities.isSelected(item) },
                                 set: { _ in utilities.toggleCache(item) })) {
                VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
                    HStack(spacing: MacBDesign.Space.snug) {
                        Text(item.owner).font(.system(size: MacBDesign.TypeScale.caption, weight: .medium)).lineLimit(1)
                        Text(item.sizeText)
                            .font(.system(size: MacBDesign.TypeScale.micro)).foregroundStyle(MacBDesign.muted)
                        if item.isInUse {
                            Text("uygulama açık")
                                .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
                                .padding(.horizontal, MacBDesign.Space.snug).padding(.vertical, MacBDesign.Space.hair)
                                .background(Color.orange.opacity(0.18), in: Capsule())
                        }
                    }
                    Text(item.displayPath)
                        .font(.system(size: MacBDesign.TypeScale.micro, design: .monospaced))
                        .foregroundStyle(MacBDesign.muted)
                        .lineLimit(1)
                        // The end of the path is the folder name, which is the
                        // part worth reading, so a long one loses its middle.
                        .truncationMode(.middle)
                        .help(item.url.path)
                }
            }
            .toggleStyle(.checkbox)
            Spacer(minLength: 0)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "folder").font(.system(size: MacBDesign.TypeScale.micro))
            }
            .buttonStyle(.borderless)
            .help("Finder'da göster")
            .accessibilityLabel("Finder'da göster")
        }
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: MacBDesign.TypeScale.micro, weight: .bold)) }
            .buttonStyle(.borderless)
            .disabled(!enabled)
            .help(label)
            .accessibilityLabel(label)
    }

    private func sizeTitle(_ size: IslandWidgetSize) -> String {
        switch size {
        case .small: return "Küçük"
        case .medium: return "Orta"
        case .wide: return "Geniş"
        }
    }

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Anlık bildirimler", "bell.badge") {
                settingToggle("Sistem değişikliklerini göster",
                              detail: "Şarkı geçince ya da şarj takılınca island kısa süre açılıp gösterir.",
                              isOn: $preferences.islandEventsEnabled)
            }
            section("Island yüzeyi", "rectangle.topthird.inset.filled") {
                settingToggle("Island ışığı",
                              detail: "Island açıkken altındaki masaüstüne yumuşak bir ışık düşürür, çalan parçanın rengini alır. Kapalıyken hiçbir şey çizilmez.",
                              isOn: $preferences.islandGlow)
                rowDivider
                Picker("Island yüzeyi", selection: $preferences.islandAppearance) {
                    ForEach(IslandAppearance.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Island yüzeyi")
                if preferences.islandAppearance.usesMaterial {
                    VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
                        HStack {
                            Text("Saydamlık")
                                .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                            Spacer()
                            Text("%\(Int((preferences.islandTranslucency * 100).rounded()))")
                                .font(.system(size: MacBDesign.TypeScale.caption).monospacedDigit())
                                .foregroundStyle(MacBDesign.muted)
                        }
                        Slider(value: $preferences.islandTranslucency, in: 0...1)
                            .accessibilityLabel("Island saydamlığı")
                        Text("Masaüstünün ne kadarının panelden geçeceği. Doğru değer duvar kağıdına bağlı: koyu bir arka plan yüksek saydamlığı kaldırır, açık bir arka planda yazılar çabuk okunmaz olur.")
                            .font(.system(size: MacBDesign.TypeScale.caption))
                            .foregroundStyle(MacBDesign.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if reduceTransparency {
                            Label("Sistemde “Saydamlığı Azalt” açık. Island düz siyah çiziliyor, bu ayarın şu an bir etkisi yok.",
                                  systemImage: "info.circle")
                                .font(.system(size: MacBDesign.TypeScale.caption))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, MacBDesign.Space.close)
                }
                if preferences.islandAppearance == .customImage {
                    HStack(spacing: MacBDesign.Space.regular) {
                        Text(background.name ?? "Henüz bir görsel seçilmedi.")
                            .font(.system(size: MacBDesign.TypeScale.body))
                            .foregroundStyle(MacBDesign.muted)
                            .lineLimit(1)
                        Spacer()
                        Button("Görsel seç…", action: background.choose)
                        if background.hasImage {
                            Button("Kaldır", role: .destructive, action: background.clear)
                        }
                    }
                    .padding(.top, MacBDesign.Space.close)
                    if let error = background.errorMessage {
                        Text(error).font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(.orange)
                    }
                }
            }
            Color.clear.frame(height: 0).id(Self.hingeAnchor)
            section("Menteşe", "laptopcomputer") {
                settingToggle("Kapakla katlanma",
                              detail: "Kapağı kapatırken island menteşeyle birlikte yatar, açtığında karşılama satırıyla geri açılır.",
                              isOn: $preferences.lidHingeEnabled)
                if lid.isAvailable && preferences.lidHingeEnabled {
                    settingToggle("Tüm ekran bulanıklaşsın",
                                  detail: "Kapak inerken masaüstü de island ile birlikte bulanıklaşır. Ekran görüntüsü alınmaz, ekran kaydı izni istenmez. Harici ekran bağlıysa yalnızca MacBook ekranı bulanıklaşır.",
                                  isOn: $preferences.lidScreenBlur)
                    VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
                        HStack {
                            Text("Katlanma açısı")
                                .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                            Spacer(minLength: 8)
                            Text("\(Int(preferences.lidHingeAngle))°")
                                .font(.system(size: MacBDesign.TypeScale.body, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(MacBDesign.accent)
                        }
                        Slider(value: $preferences.lidHingeAngle,
                               in: LidFold.minimumOpenAngle...LidFold.maximumOpenAngle, step: 5)
                            .onChange(of: preferences.lidHingeAngle) { _, value in
                                lid.setOpenAngle(value)
                            }
                        Text("Kapak bu açının altına inince katlanma ve bulanıklık başlar, her derecede eşit miktarda artar.")
                            .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    lidLine("Açılış yazısı", text: $preferences.lidWelcomeText,
                            placeholder: "Boş — hiçbir şey çıkmaz",
                            label: "Kapak açılınca görünen yazı")
                    Text("Boş bırakırsan kapağı açtığında ekranda hiçbir şey çıkmaz.")
                        .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    lidLine("Kapanış yazısı", text: $preferences.lidFarewellText,
                            placeholder: "Boş — hiçbir şey çıkmaz",
                            label: "Kapak kapanırken görünen yazı")
                    Text("İkisi de boşken island hiç görünmez, katlanma animasyonu da olmaz. Ekranın bulanıklaşması devam eder. En fazla \(IslandEvent.customTitleLimit) karakter.")
                        .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(lid.isAvailable
                     ? "\(lid.diagnostic)\(lid.angle.map { String(format: "  Şu an %.0f°.", $0) } ?? "")"
                     : lid.diagnostic)
                    .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                if !lid.isAvailable {
                    message("Menteşe açısı sensörü yalnızca Apple silikon MacBook'larda bulunur ve her modelde okunamaz.")
                }
            }
            section("Panel davranışı", "hand.point.up.left") {
                settingToggle("Küçük göstergeler", detail: "Panel kapalıyken oynatma durumunu ve raftaki öğe sayısını göster.", isOn: $preferences.compactIndicators)
                rowDivider
                settingToggle("Yumuşak geçişler", detail: "Paneller açılırken ve kapanırken kısa animasyonlar kullan.", isOn: $preferences.animationsEnabled)
                rowDivider
                settingToggle("Pencere peek modu", detail: "Kartta bekleyince pencerenin ekrandaki yerini hafifçe vurgula.", isOn: $preferences.peekEnabled)
            }
            section("Kısayol halkası", "circle.circle") {
                settingToggle("Fn + iki parmak tıklaması",
                              detail: "İmlecin etrafında bir halka açılır. Tutup istediğin dilime doğru kaydır ve bırak; ya da tıklayıp bırak, halka açık kalsın, sonra dilime tıkla. Escape kapatır.",
                              isOn: $preferences.radialMenuEnabled)
                if preferences.radialMenuEnabled {
                    if !permissions.accessibility {
                        message("Halka, tıklamayı yakalamak için Erişilebilirlik izni istiyor. İzin verilene kadar açılmaz.", warning: true)
                    }
                    rowDivider
                    HStack(spacing: MacBDesign.Space.regular) {
                        Text("Halka")
                            .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                        Picker("", selection: $ringProfile) {
                            Text("Her yerde").tag(String?.none)
                            ForEach(preferences.radialMenuAppLayouts.keys.sorted(), id: \.self) { bundleID in
                                Text(Self.appName(for: bundleID)).tag(String?.some(bundleID))
                            }
                        }
                        .labelsHidden()
                        Button("Uygulama için…", action: addRingProfile)
                            .help("Seçtiğin uygulama öndeyken bu halka açılır")
                        if let profile = ringProfile {
                            Button {
                                preferences.radialMenuAppLayouts[profile] = nil
                                ringProfile = nil
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                            .help("Bu uygulamanın halkasını sil; genel halka kullanılır")
                        }
                    }
                    Text(ringProfile == nil
                         ? "Kendi halkası olmayan her uygulamada bu açılır. Dilimler saat yönünde, yukarıdan başlayarak."
                         : "\(Self.appName(for: ringProfile ?? "")) öndeyken yalnızca bu halka açılır.")
                        .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(editedRing.slots.enumerated()), id: \.offset) { index, slot in
                        HStack(spacing: MacBDesign.Space.regular) {
                            slotIcon(slot)
                            switch slot {
                            case .action:
                                Picker("", selection: radialSlice(at: index)) {
                                    ForEach(RadialAction.allCases, id: \.self) { candidate in
                                        Text(candidate.title).tag(candidate)
                                    }
                                }
                                .labelsHidden()
                                .accessibilityLabel("\(index + 1). dilim")
                            case .open(let path):
                                Text(slot.title)
                                    .font(.system(size: MacBDesign.TypeScale.body))
                                    .lineLimit(1)
                                    .help(path)
                                Spacer(minLength: 0)
                            }
                            Button {
                                editRing { slots in slots.remove(at: index) }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .disabled(editedRing.slots.count <= RadialMenuGeometry.minimumSlices)
                            .help("Bu dilimi çıkar")
                        }
                    }
                    HStack(spacing: MacBDesign.Space.regular) {
                        Button("Eylem ekle", action: addRadialSlice)
                            .disabled(editedRing.slots.count >= RadialMenuGeometry.maximumSlices)
                        Button("Uygulama ya da dosya…", action: addOpenSlice)
                            .disabled(editedRing.slots.count >= RadialMenuGeometry.maximumSlices)
                        Button("Varsayılana dön") { editRing { $0 = RadialMenuLayout.default.slots } }
                        Spacer()
                        Text("\(editedRing.slots.count) dilim")
                            .font(.system(size: MacBDesign.TypeScale.caption))
                            .foregroundStyle(MacBDesign.muted)
                    }
                    Text("Tek dilim de olur: o zaman hangi yöne kaydırırsan kaydır aynı şey çalışır.")
                        .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    rowDivider
                    settingToggle("Üç parmakla dokunma",
                                  detail: "Fn ve tıklama olmadan, trackpad'e üç parmakla kısa bir dokunuş da halkayı açar. Üç parmakla kaydırma (Mission Control, masaüstleri) etkilenmez — halka yalnızca dokunuşta açılır. macOS'ta \u{201C}üç parmakla dokunup ara\u{201D} açıksa ikisi birden çalışır.",
                                  isOn: $preferences.radialMenuThreeFinger)
                    if preferences.radialMenuThreeFinger && !TrackpadContacts.isSupported {
                        message("Bu macOS sürümünde trackpad parmak sayısı okunamıyor. Fn + iki parmak çalışmaya devam ediyor.", warning: true)
                    }
                    rowDivider
                    HStack {
                        Text("Boyut")
                            .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                        Spacer(minLength: 8)
                        Text("%\(Int((preferences.radialMenuScale * 100).rounded()))")
                            .font(.system(size: MacBDesign.TypeScale.body, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(MacBDesign.accent)
                    }
                    Slider(value: $preferences.radialMenuScale,
                           in: RadialMenuMetrics.minimumScale...RadialMenuMetrics.maximumScale)
                    Text("Halka imlecin üstünde açılır, yani her fazladan piksel senin işinin üstünü örter. Yeni boyut bir sonraki açılışta geçerli olur.")
                        .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    rowDivider
                    HStack {
                        Text("Saydamlık")
                            .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                        Spacer(minLength: 8)
                        Text("%\(Int((preferences.radialMenuTranslucency * 100).rounded()))")
                            .font(.system(size: MacBDesign.TypeScale.body, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(MacBDesign.accent)
                    }
                    Slider(value: $preferences.radialMenuTranslucency, in: 0...1)
                        .disabled(reduceTransparency)
                    Text(reduceTransparency
                         ? "Sistemde \u{201C}Saydamlığı azalt\u{201D} açık, halka düz çiziliyor."
                         : "Island'daki gibi: sağa gittikçe buz incelir, arkadaki ekran daha çok görünür.")
                        .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            section("Hızlı erişim", "square.grid.2x2") {
                intro("Island'daki Uygulamalar bölümünde yalnızca buraya eklediklerin görünür. MacB kurulu uygulamaları taramaz.")
                HStack(spacing: MacBDesign.Space.regular) {
                    Button("Uygulama veya klasör ekle…", action: launcher.choose)
                    Spacer()
                    Text("\(launcher.items.count) öğe")
                        .font(.system(size: MacBDesign.TypeScale.caption))
                        .foregroundStyle(MacBDesign.muted)
                }
            }
            section("Raf yardımcıları", "tray") {
                settingToggle("Son dosyalar", detail: "Downloads, Desktop ve Documents içinden son dosyaları öner. macOS klasör erişimi isteyebilir.", isOn: $preferences.recentFilesEnabled)
                rowDivider
                settingToggle("Ekran görüntüleri rafa", detail: "Aldığın her ekran görüntüsü rafa düşer, oradan sürükleyip istediğin yere bırakırsın. Dosya yerinde kalır; MacB kopyalamaz, taşımaz. macOS klasör erişimi isteyebilir.", isOn: $preferences.screenshotShelfEnabled)
                rowDivider
                settingToggle("Mini pano rafı", detail: "Son kopyaladığın metinleri Pano görünümünde tut.", isOn: $preferences.clipboardShelfEnabled)
                if preferences.clipboardShelfEnabled {
                    HStack {
                        Text("Geçmiş uzunluğu")
                            .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                        Spacer()
                        Picker("", selection: $preferences.clipboardHistoryLimit) {
                            ForEach(Preferences.clipboardHistoryLimits, id: \.self) { Text("\($0) öğe").tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    settingToggle("Geçmişi yeniden başlatınca da tut",
                                  detail: "Kapalıyken yalnızca yıldızladıkların kalır. Açıkken metin, bağlantı, renk ve dosya kayıtları diske yazılır — görseller hiçbir zaman. Şifre yöneticilerinden kopyalananlar zaten hiç tutulmaz. Kapatınca kayıtlı geçmiş boşaltılır.",
                                  isOn: $preferences.clipboardKeepsHistory)
                }
                rowDivider
                settingToggle("İndirme göstergesi", detail: "Downloads klasöründeki yeni dosyaları göster. macOS klasör erişimi isteyebilir.", isOn: $preferences.fileActivityEnabled)
            }
            section("Gizlilik", "lock.shield") {
                settingToggle("Özel araçları kilitle", detail: "Pano ve kamera açılırken Touch ID, Apple Watch veya Mac parolanla doğrula.", isOn: $preferences.protectPrivateTools)
            }
            section("Yoğunluk", "arrow.up.and.down.text.horizontal") {
                Picker("Görünüm yoğunluğu", selection: $preferences.interfaceDensity) {
                    ForEach(InterfaceDensity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Görünüm yoğunluğu")
            }
            HStack(alignment: .top, spacing: MacBDesign.Space.regular) {
                Image(systemName: "accessibility").font(.system(size: MacBDesign.TypeScale.title)).accessibilityHidden(true)
                Text(reduceMotion
                     ? "macOS’ta Hareketi Azalt açık. MacB bu tercihe uyar ve animasyonları kapalı tutar."
                     : "macOS’ta Hareketi Azalt açıldığında, MacB animasyonları otomatik olarak kapatır.")
                    .font(.system(size: MacBDesign.TypeScale.body)).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(MacBDesign.muted)
            .padding(MacBDesign.Space.loose)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            permissionRow("Erişilebilirlik", detail: "Dock’u algılamak ve seçtiğin pencereyi yönetmek için.",
                          granted: permissions.accessibility, action: permissions.requestAccessibility)
            rowDivider
            permissionRow("Ekran kaydı", detail: "Açık önizlemelerde pencere görüntülerini göstermek için. Görüntüler diske kaydedilmez.",
                          granted: permissions.screenCapture, action: permissions.requestScreenCapture)
            rowDivider
            permissionRow("Giriş izleme", detail: "⌘ Tab pencere seçicisini çalıştırmak için.",
                          granted: permissions.inputMonitoring, action: permissions.requestInputMonitoring)
            rowDivider
            permissionRow("Medya denetimi", detail: mediaPermissionDetail,
                          granted: mediaPermissionGranted,
                          actionTitle: "Bağlantıları hazırla", action: prepareMediaAccess)
            if let error = [spotify.errorMessage, appleMusic.errorMessage, browserMedia.errorMessage].compactMap({ $0 }).first {
                message(error, warning: true)
            }
            rowDivider
            permissionRow("Kamera", detail: "Canlı önizleme yalnız sen kamera düğmesine bastığında çalışır.",
                          granted: camera.isAuthorized, actionTitle: "İzin ver", action: camera.requestAuthorization)
            rowDivider
            permissionRow("Konum", detail: "Hava durumu kartında şehir yazmadığında yaklaşık konumu bir kez almak için.",
                          granted: permissions.location, actionTitle: "İzin ver", action: permissions.requestLocation)
            if let error = camera.errorMessage { message(error, warning: true) }
            Text("Bir izin kapalıyken diğer özellikler çalışmaya devam eder. macOS yeniden başlatma isterse MacB’yi kapatıp aç.")
                .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, MacBDesign.Space.tight)
        }
    }

    private var doctorPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Sistem sağlığı", "stethoscope") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MacBDesign.Space.regular) {
                    doctorTile("Pencere kontrolü", permissions.accessibility ? "Hazır" : "İzin bekliyor", "rectangle.3.group", good: permissions.accessibility)
                    doctorTile("Önizlemeler", permissions.screenCapture ? "Hazır" : "Ekran kaydı yok", "rectangle.on.rectangle", good: permissions.screenCapture)
                    doctorTile("Medya", mediaPermissionGranted ? "Tek kart hazır" : "Kaynak izni bekliyor", "music.note", good: mediaPermissionGranted)
                    doctorTile("Konumlu hava", permissions.location || !weather.placeQuery.isEmpty ? "Hazır" : "Konum veya şehir yok", "cloud.sun", good: permissions.location || !weather.placeQuery.isEmpty)
                }
                HStack(spacing: MacBDesign.Space.regular) {
                    Button("İzinleri yenile") { permissions.refresh() }
                    Button("Medyayı hazırla", action: prepareMediaAccess)
                    Button("Havayı dene") { weather.refresh(force: true) }
                }
            }
            section("Canlı servisler", "waveform.path.ecg") {
                statusLine("Hava", weatherStatus, symbol: weather.snapshot?.symbol ?? "cloud")
                rowDivider
                statusLine("Mail", mailStatus, symbol: "envelope")
                rowDivider
                statusLine("Güncelleme", updateTitle + " — " + updateDetail, symbol: "arrow.triangle.2.circlepath")
                rowDivider
                statusLine("Yüz kilidi", faceUnlock.settings.isEnabled ? "Ürün içi özel alanlar için açık." : "Kapalı veya kayıt bekliyor.", symbol: "faceid")
            }
            section("Güvenli probe'lar", "terminal") {
                Text("Terminalden çalıştır: --mail-probe özel konu/sender basmadan Mail sayımlarını verir; --measure-assistant izin kartının sığıp sığmadığını ölçer.")
                    .font(.system(size: MacBDesign.TypeScale.caption))
                    .foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var weatherStatus: String {
        if weather.isLoading { return "Kontrol ediliyor…" }
        if let snapshot = weather.snapshot { return "\(snapshot.place), \(snapshot.temperature)°, \(snapshot.condition)" }
        return weather.errorMessage ?? "Henüz veri yok."
    }

    private var mailStatus: String {
        if mail.isReading { return "Mail okunuyor…" }
        if mail.summary.isUnavailable { return mail.summary.note ?? "Mail kullanılamıyor." }
        return mail.summary.unread == 0 ? "Okunmamış önemli mail görünmüyor." : "\(mail.summary.unread) okunmamış mail görüldü."
    }

    private func doctorTile(_ title: String, _ detail: String, _ symbol: String, good: Bool) -> some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.close) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: MacBDesign.TypeScale.title, weight: .semibold))
                    .foregroundStyle(good ? MacBDesign.accent : Color.orange)
                Spacer()
                Circle().fill(good ? Color.green : Color.orange).frame(width: 7, height: 7)
            }
            Text(title).font(.system(size: MacBDesign.TypeScale.body, weight: .semibold))
            Text(detail).font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
        }
        .padding(MacBDesign.Space.comfortable)
        .background(LinearGradient(colors: [Color.primary.opacity(0.055), Color.primary.opacity(0.025)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }

    private func statusLine(_ title: String, _ detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: MacBDesign.Space.regular) {
            Image(systemName: symbol).foregroundStyle(MacBDesign.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
                Text(title).font(.system(size: MacBDesign.TypeScale.body, weight: .semibold))
                Text(detail).font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The AI key card used to build every provider's text field, model menu and
    /// buttons at once. On the tools page that meant five secure fields and five
    /// pickers were measured every time SwiftUI laid out the scroll view. The
    /// strip keeps the overview visible, and the detail panel mounts only one
    /// provider, which makes the page feel calm instead of heavy.
    private var aiProviderHeader: some View {
        HStack(alignment: .center, spacing: MacBDesign.Space.regular) {
            VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
                Text("Soruları cevaplayan")
                    .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                Text(aiProviderStatusText)
                    .font(.system(size: MacBDesign.TypeScale.caption))
                    .foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Picker("Sağlayıcı", selection: $preferences.aiProvider) {
                Text("Otomatik").tag("")
                ForEach(AIProvider.textOrder) { provider in
                    Text(provider.title).tag(provider.rawValue)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var aiProviderStatusText: String {
        if let active = assistant.provider {
            return "Şu an \(active.title) cevaplıyor" + (active.canSearchWeb ? "." : "; web araması yok.")
        }
        return "Henüz anahtar yok. Ücretsiz ve güçlü başlangıç için Gemini iyi seçim."
    }

    private var aiProviderStrip: some View {
        HStack(spacing: MacBDesign.Space.snug) {
            ForEach(AIProvider.textOrder) { provider in
                aiProviderPill(provider)
            }
        }
    }

    private func aiProviderPill(_ provider: AIProvider) -> some View {
        let selected = provider == selectedAIKeyProvider
        let hasKey = aiKey.has(provider)
        return Button {
            selectedAIKeyProvider = provider
        } label: {
            VStack(alignment: .leading, spacing: MacBDesign.Space.tight) {
                HStack(spacing: MacBDesign.Space.tight) {
                    Image(systemName: hasKey ? "checkmark.seal.fill" : provider.isFree ? "sparkles" : "creditcard")
                        .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                        .foregroundStyle(hasKey ? MacBDesign.accent : MacBDesign.muted)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: MacBDesign.TypeScale.micro, weight: .bold))
                            .foregroundStyle(MacBDesign.accent)
                    }
                }
                Text(provider.title)
                    .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                    .lineLimit(1)
                Text(hasKey ? "Hazır" : (provider.isFree ? "Ücretsiz" : "Ses + web"))
                    .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
                    .foregroundStyle(MacBDesign.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .padding(.horizontal, MacBDesign.Space.regular)
            .padding(.vertical, MacBDesign.Space.snug)
            .background(selected ? MacBDesign.accent.opacity(0.12) : Color.primary.opacity(0.032),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? MacBDesign.accent.opacity(0.55) : MacBDesign.cardStroke,
                              lineWidth: selected ? 1.2 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(provider.title) sağlayıcısını düzenle")
    }

    private func chooseUsefulAIProvider() {
        if aiKey.has(selectedAIKeyProvider) { return }
        if let selected = AIProvider(rawValue: preferences.aiProvider), aiKey.has(selected) {
            selectedAIKeyProvider = selected
        } else if let active = assistant.provider {
            selectedAIKeyProvider = active
        } else if let stored = AIProvider.textOrder.first(where: { aiKey.has($0) }) {
            selectedAIKeyProvider = stored
        }
    }

    /// One provider: whether it has a key, the field to put one in, and which
    /// model it should use.
    @ViewBuilder
    private func providerRow(_ provider: AIProvider) -> some View {
        let draft = Binding<String>(get: { keyDrafts[provider.rawValue] ?? "" },
                                    set: { keyDrafts[provider.rawValue] = $0 })
        VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
            HStack(spacing: MacBDesign.Space.regular) {
                Image(systemName: aiKey.has(provider) ? "checkmark.seal.fill" : "circle.dashed")
                    .foregroundStyle(aiKey.has(provider) ? MacBDesign.accent : MacBDesign.muted)
                Text(provider.title)
                    .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
                if provider.isFree {
                    Text("ücretsiz")
                        .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(MacBDesign.accent.opacity(0.18), in: Capsule())
                }
                Spacer(minLength: 8)
                if aiKey.has(provider) {
                    Button("Doğrula") { Task { await aiKey.verify(provider) } }
                        .disabled(aiKey.status(of: provider) == .checking)
                    Button("Sil", role: .destructive) { aiKey.remove(provider) }
                } else {
                    Button("Anahtar al") { NSWorkspace.shared.open(provider.signUpURL) }
                }
            }
            Text(provider.note)
                .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: MacBDesign.Space.regular) {
                SecureField(aiKey.has(provider) ? "Yeni anahtarla değiştir" : (provider.keyPrefix ?? "") + "…",
                            text: draft)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(provider.title) anahtarı")
                Button("Kaydet") {
                    if aiKey.save(draft.wrappedValue, for: provider) {
                        keyDrafts[provider.rawValue] = ""
                        Task { await aiKey.verify(provider) }
                    }
                }
                .disabled(!AIKeyFormat.looksLikeKey(draft.wrappedValue, for: provider))
            }
            HStack(spacing: MacBDesign.Space.regular) {
                Text("Model").font(.system(size: MacBDesign.TypeScale.caption))
                    .foregroundStyle(MacBDesign.muted)
                Spacer(minLength: 8)
                Picker("Model", selection: Binding(
                    get: { preferences.model(for: provider) },
                    set: { preferences.setModel($0, for: provider) })) {
                    let choices = aiKey.modelChoices(for: provider)
                    ForEach(choices, id: \.self) { Text($0).tag($0) }
                    let current = preferences.model(for: provider)
                    if !choices.contains(current) { Text(current).tag(current) }
                }
                .labelsHidden().frame(maxWidth: 260)
                Button("Modelleri yenile") { Task { await aiKey.loadModels(provider) } }
                    .controlSize(.small)
                    .disabled(!aiKey.has(provider) || aiKey.isLoadingModels == provider)
            }
            switch aiKey.status(of: provider) {
            case .idle: EmptyView()
            case .checking: message("\(provider.title)'ye soruluyor…")
            case .valid(let text): message(text)
            case .invalid(let text): message(text, warning: true)
            }
        }
    }

    private func addScenario() {
        if scenarios.add(name: scenarioName) != nil { scenarioName = "" }
    }

    /// One scenario: its name, what it does, and a way to try it.
    @ViewBuilder
    private func scenarioRow(_ scenario: Scenario) -> some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
            HStack(spacing: MacBDesign.Space.regular) {
                Text(scenario.name)
                    .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
                Spacer(minLength: 8)
                Button("Çalıştır") { Task { await scenarios.run(scenario) } }
                    .disabled(!scenario.isRunnable)
                Menu("Adım ekle") {
                    ForEach(ScenarioStep.choices) { choice in
                        Button(choice.kindTitle) { scenarios.addStep(choice, to: scenario.id) }
                    }
                }
                .fixedSize()
                Button("Sil", role: .destructive) { scenarios.remove(scenario.id) }
            }
            ForEach(Array(scenario.steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: MacBDesign.Space.regular) {
                    Image(systemName: step.symbol)
                        .font(.system(size: MacBDesign.TypeScale.caption))
                        .foregroundStyle(step.isComplete ? MacBDesign.accent : MacBDesign.muted)
                        .frame(width: 18)
                    scenarioStepEditor(step, at: index, in: scenario)
                    Spacer(minLength: 8)
                    Button { scenarios.removeStep(at: index, in: scenario.id) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain).foregroundStyle(MacBDesign.muted)
                    .accessibilityLabel("Adımı sil: \(step.title)")
                }
            }
            if scenario.steps.isEmpty {
                message("Bu senaryoda henüz adım yok.")
            }
        }
    }

    /// The one control a step needs: a name, an address or a number.
    @ViewBuilder
    private func scenarioStepEditor(_ step: ScenarioStep, at index: Int, in scenario: Scenario) -> some View {
        switch step {
        case .arrangement(let name):
            Picker("Düzen", selection: Binding(
                get: { name },
                set: { scenarios.replaceStep(at: index, in: scenario.id, with: .arrangement(name: $0)) })) {
                Text("Seç…").tag("")
                ForEach(arrangements.arrangements) { Text($0.name).tag($0.name) }
            }
            .labelsHidden().fixedSize()
        case .openApplication(let name):
            TextField("Uygulama adı", text: Binding(
                get: { name },
                set: { scenarios.replaceStep(at: index, in: scenario.id, with: .openApplication(name: $0)) }))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
        case .openWebsite(let url):
            TextField("adres.com", text: Binding(
                get: { url },
                set: { scenarios.replaceStep(at: index, in: scenario.id, with: .openWebsite(url: $0)) }))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
        case .shortcut(let name):
            TextField("Kısayol adı", text: Binding(
                get: { name },
                set: { scenarios.replaceStep(at: index, in: scenario.id, with: .shortcut(name: $0)) }))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
        case .media(let play):
            Picker("Müzik", selection: Binding(
                get: { play },
                set: { scenarios.replaceStep(at: index, in: scenario.id, with: .media(play: $0)) })) {
                Text("Duraklat").tag(false)
                Text("Başlat").tag(true)
            }
            .labelsHidden().fixedSize()
        case .keepAwake(let minutes):
            Picker("Süre", selection: Binding(
                get: { minutes },
                set: { scenarios.replaceStep(at: index, in: scenario.id, with: .keepAwake(minutes: $0)) })) {
                ForEach(KeepAwakeDuration.choices, id: \.self) { Text(KeepAwakeDuration.title(minutes: $0)).tag($0) }
            }
            .labelsHidden().fixedSize()
        case .volume(let percent):
            Picker("Ses", selection: Binding(
                get: { percent },
                set: { scenarios.replaceStep(at: index, in: scenario.id, with: .volume(percent: $0)) })) {
                ForEach([0, 10, 20, 30, 50, 70, 100], id: \.self) { Text("%\($0)").tag($0) }
            }
            .labelsHidden().fixedSize()
        case .timer(let minutes):
            Picker("Dakika", selection: Binding(
                get: { minutes },
                set: { scenarios.replaceStep(at: index, in: scenario.id, with: .timer(minutes: $0)) })) {
                ForEach([5, 10, 15, 25, 45, 60], id: \.self) { Text("\($0) dk").tag($0) }
            }
            .labelsHidden().fixedSize()
        }
    }

    private func costBox(_ title: String, _ amount: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: MacBDesign.TypeScale.caption))
                .foregroundStyle(MacBDesign.muted)
            Text(amount).font(.system(size: MacBDesign.TypeScale.title, weight: .semibold))
                .monospacedDigit()
            Text(detail).font(.system(size: MacBDesign.TypeScale.micro))
                .foregroundStyle(MacBDesign.muted)
        }
        .frame(minWidth: 96, alignment: .leading)
    }

    /// How much of today's allowance is gone. A number on its own does not
    /// answer "am I close?"; a bar does, without being read.
    private var budgetBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(MacBDesign.cardStroke)
                Capsule()
                    .fill(aiCost.isOverDailyLimit ? Color(nsColor: .systemRed) : MacBDesign.accent)
                    .frame(width: max(2, proxy.size.width * aiCost.limitFraction))
            }
        }
        .frame(height: 5)
        .motion(MacBDesign.Motion.progress, value: aiCost.limitFraction)
        .accessibilityLabel("Günlük sınırın \(Int(aiCost.limitFraction * 100)) yüzdesi kullanıldı")
    }

    private var rowDivider: some View { Divider().opacity(0.45) }

    /// The ring being edited: the general one, or one application's.
    private var editedRing: RadialMenuLayout {
        if let ringProfile, let specific = preferences.radialMenuAppLayouts[ringProfile] { return specific }
        return preferences.radialMenuLayout
    }

    /// Changes the ring being edited. The layout validates itself on the way
    /// in, so this always hands it a whole new list.
    private func editRing(_ change: (inout [RadialSlot]) -> Void) {
        var slots = editedRing.slots
        change(&slots)
        let updated = RadialMenuLayout(slots: slots)
        if let ringProfile {
            preferences.radialMenuAppLayouts[ringProfile] = updated
        } else {
            preferences.radialMenuLayout = updated
        }
    }

    /// One action slice, as something a Picker can drive.
    private func radialSlice(at index: Int) -> Binding<RadialAction> {
        Binding(
            get: {
                let slots = editedRing.slots
                guard slots.indices.contains(index), case .action(let action) = slots[index] else { return .island }
                return action
            },
            set: { value in
                editRing { slots in
                    guard slots.indices.contains(index) else { return }
                    slots[index] = .action(value)
                }
            })
    }

    private func addRadialSlice() {
        editRing { slots in
            // The first action not already on the ring, so adding twice does
            // not produce two of the same.
            let used = Set(slots)
            let next = RadialAction.allCases.first { !used.contains(.action($0)) } ?? .island
            slots.append(.action(next))
        }
    }

    /// Puts an application, folder or file of the user's choosing on the ring.
    private func addOpenSlice() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Halkaya ekle"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        editRing { slots in
            let slot = RadialSlot.open(path: url.path)
            guard !slots.contains(slot) else { return }
            slots.append(slot)
        }
    }

    /// Starts a ring for one application, copied from the general one so the
    /// user edits from something rather than from nothing.
    private func addRingProfile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Bu uygulama için"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        if preferences.radialMenuAppLayouts[bundleID] == nil {
            preferences.radialMenuAppLayouts[bundleID] = preferences.radialMenuLayout
        }
        ringProfile = bundleID
    }

    @ViewBuilder private func slotIcon(_ slot: RadialSlot) -> some View {
        switch slot {
        case .action(let action):
            Image(systemName: action.symbol)
                .font(.system(size: MacBDesign.TypeScale.body))
                .foregroundStyle(MacBDesign.accent)
                .frame(width: 20)
        case .open(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 20, height: 20)
        }
    }

    /// An application's name from its bundle identifier, or the identifier
    /// itself if the application has since been removed.
    static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private var runningBadge: some View {
        Text("çalışıyor")
            .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
            .foregroundStyle(Color(nsColor: .systemGreen))
            .padding(.horizontal, MacBDesign.Space.close)
            .padding(.vertical, MacBDesign.Space.tight)
            .background(Color(nsColor: .systemGreen).opacity(0.14), in: Capsule())
            .accessibilityLabel("Çalışıyor")
    }

    /// A number alone says little. The bar gives it a scale, and the colour
    /// turns only when the resource is genuinely nearly spent.
    private func systemMetric(_ title: String, _ value: String, fraction: Double?) -> some View {
        let level = fraction ?? 0
        let tint: Color = level >= 0.85 ? Color(nsColor: .systemRed) : MacBDesign.accent
        return VStack(spacing: MacBDesign.Space.snug) {
            Text(value)
                .font(.system(size: MacBDesign.TypeScale.title, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: MacBDesign.TypeScale.micro))
                .foregroundStyle(MacBDesign.muted)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(tint)
                        .frame(width: proxy.size.width * min(1, max(0, level)))
                }
            }
            .frame(height: 3)
            .opacity(fraction == nil ? 0 : 1)
        }
        .padding(.horizontal, MacBDesign.Space.regular)
        .padding(.vertical, MacBDesign.Space.regular)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private func percentage(_ used: UInt64, _ total: UInt64) -> String {
        total > 0 ? "\(Int(Double(used) / Double(total) * 100))%" : "—"
    }

    private func fraction(_ used: UInt64, _ total: UInt64) -> Double? {
        total > 0 ? Double(used) / Double(total) : nil
    }

    private var thermalText: String {
        switch systemMonitor.snapshot.thermalState {
        case .nominal: return "Termal durum normal"
        case .fair: return "Termal yük hafif yükseldi"
        case .serious: return "Termal yük yüksek"
        case .critical: return "Termal yük kritik"
        @unknown default: return "Termal durum bilinmiyor"
        }
    }

    private func openDefaultBrowser() {
        guard let url = URL(string: "https://www.youtube.com") else { return }
        NSWorkspace.shared.open(url)
    }

    private var mediaPermissionGranted: Bool {
        (!spotify.isRunning || spotify.isAuthorized) &&
        (!appleMusic.isRunning || appleMusic.isAuthorized) &&
        (!browserMedia.isRunning || browserMedia.isAuthorized)
    }

    private var mediaPermissionDetail: String {
        "Spotify, Apple Music ve tarayıcıdaki etkin oynatıcıyı tek medya alanında gösterir. macOS yalnız kullandığın kaynak için kendi onayını gösterebilir."
    }

    private func prepareMediaAccess() {
        if spotify.isRunning && !spotify.isAuthorized { spotify.requestAuthorization() }
        if appleMusic.isRunning && !appleMusic.isAuthorized { appleMusic.requestAuthorization() }
        if browserMedia.isRunning && !browserMedia.isAuthorized { browserMedia.requestAuthorization() }
        if !spotify.isRunning && !appleMusic.isRunning && !browserMedia.isRunning { openDefaultBrowser() }
    }

    private var currentHour: Int { Calendar.current.component(.hour, from: Date()) }

    /// One of the two lines the island says around a lid movement.
    ///
    /// The placeholder is what the user would get right now if they leave the
    /// field empty, so it shows the default rather than describing it.
    private func lidLine(_ title: String, text: Binding<String>,
                         placeholder: String, label: String) -> some View {
        HStack(spacing: MacBDesign.Space.regular) {
            Text(title)
                .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                .frame(width: 104, alignment: .leading)
            TextField(placeholder, text: Binding(
                get: { text.wrappedValue },
                set: { text.wrappedValue = String($0.prefix(IslandEvent.customTitleLimit)) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 220)
            .accessibilityLabel(label)
            Spacer(minLength: 0)
        }
    }

    /// The page's own spelling of `SettingsCard`, kept so the twenty-seven
    /// call sites read as sentences rather than as view construction.
    private func section<Content: View>(_ title: String, _ symbol: String = "square.grid.2x2",
                                        @ViewBuilder content: () -> Content) -> some View {
        SettingsCard(title: title, symbol: symbol) { content() }
    }

    private func settingToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
                Text(title).font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
                Text(detail).font(.system(size: MacBDesign.TypeScale.body)).foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private func shortcutRow(_ title: String, symbol: String, keys: String) -> some View {
        HStack(spacing: MacBDesign.Space.comfortable) {
            Image(systemName: symbol)
                .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
                .foregroundStyle(MacBDesign.muted)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title).font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
            Spacer(minLength: 10)
            Text(keys)
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium, design: .rounded))
                .foregroundStyle(MacBDesign.muted)
                .padding(.horizontal, MacBDesign.Space.close)
                .padding(.vertical, MacBDesign.Space.snug)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(keys)")
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool,
                               actionTitle: String = "İzin ver", action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.regular) {
            Text(title).font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold))
            Text(detail).font(.system(size: MacBDesign.TypeScale.body)).foregroundStyle(MacBDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Label(granted ? "İzin verildi" : "İzin bekleniyor",
                      systemImage: granted ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: MacBDesign.TypeScale.caption))
                    .foregroundStyle(granted ? MacBDesign.accent : MacBDesign.muted)
                Spacer(minLength: 8)
                if !granted {
                    Button(actionTitle, action: action)
                        .controlSize(.small)
                        .accessibilityLabel("\(title): \(actionTitle)")
                }
            }
            .padding(.top, MacBDesign.Space.hair)
        }
        .accessibilityElement(children: .contain)
    }

    /// A card's explanation, folded away until somebody wants it.
    ///
    /// Every section opened with a paragraph. Read once each, they are worth
    /// having; stacked down a window they are a wall of grey that the controls
    /// have to be found inside. Two lines and a "daha" is the same text without
    /// the wall.
    private func intro(_ text: String) -> some View {
        SettingsIntro(text: text)
    }

    /// Plays a sample of the voice beside it; pressed again, stops.
    private func previewButton(tag: String, action: @escaping () -> Void) -> some View {
        let isActive = voiceStudio.active == tag
        return Button(action: action) {
            Image(systemName: isActive ? "stop.fill" : "play.fill")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .help(isActive ? "Durdur" : "Sesi dinle")
        .accessibilityLabel(isActive ? "Durdur" : "Sesi dinle")
    }

    private var briefingPreviewTag: String {
        let chosen = preferences.briefingVoice
        if GeminiSpeech.voice(forTag: chosen) != nil { return chosen }
        return "system:" + chosen
    }

    private func previewBriefingVoice() {
        if let voice = GeminiSpeech.voice(forTag: preferences.briefingVoice) {
            VoiceStudio.shared.previewGemini(voice)
        } else if voiceStudio.active == briefingPreviewTag {
            VoiceStudio.shared.stop()
        } else {
            VoiceStudio.shared.previewSystem(identifier: preferences.briefingVoice)
        }
    }

    /// The local model: download, state, and whether the free engine uses it.
    @ViewBuilder private var localModelRows: some View {
        HStack(spacing: MacBDesign.Space.regular) {
            Text("Yerel model").font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
            Spacer(minLength: 8)
            switch localModel.state {
            case .missing, .failed:
                Button("İndir (\(localModel.file.sizeText))") { localModel.download() }
            case .downloading(let progress):
                ProgressView(value: progress).frame(width: 120)
                Text("%\(Int(progress * 100))").font(.system(size: MacBDesign.TypeScale.caption).monospacedDigit())
                    .foregroundStyle(MacBDesign.muted)
                Button("Vazgeç") { localModel.cancel() }
            case .verifying:
                ProgressView().controlSize(.small)
                Text("Doğrulanıyor…").font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
            case .ready:
                Label("Hazır", systemImage: "checkmark.circle.fill")
                    .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
                    .foregroundStyle(Color(nsColor: .systemGreen))
                Button("Çöp Sepeti’ne Taşı") { localModel.moveToTrash() }
            }
        }
        if case .failed(let reason) = localModel.state { message(reason, warning: true) }
        Toggle("Ücretsiz modda önce yerel modeli kullan", isOn: $preferences.localModelEnabled)
            .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
            .disabled(localModel.state != .ready)
        message("\(localModel.file.title) bu Mac'te çalışır: internet gerekmez, sınır yok, ücret yok; söylediğin ve ekrandan okuduğu hiçbir şey Mac'ten çıkmaz. Bir kez indirilir (Hugging Face), parmak izi doğrulanır. Konuşma bitince birkaç dakika içinde bellekten çıkar; pildeyken daha çabuk. Web araması ve hava durumu yine internet ister.")
    }

    private func message(_ text: String, warning: Bool = false) -> some View {
        Text(text).font(.system(size: MacBDesign.TypeScale.caption))
            .foregroundStyle(warning ? Color(nsColor: .systemOrange) : MacBDesign.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Which column the resource list is ordered by.
enum ProcessSort: String, CaseIterable {
    case memory, cpu
}

private struct WatchersSettingsView: View {
    @ObservedObject var store: WatchTaskStore
    @ObservedObject var cursor: AgentCursorOverlay
    @State private var priceURL = ""
    @State private var priceThreshold = ""
    @State private var textURL = ""
    @State private var textNeedle = ""
    @State private var repo = ""
    @State private var systemThreshold = "85"
    @State private var metric: WatchMetric = .cpuPercent
    @State private var showManualCreate = false

    private var quickColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 250), spacing: 12, alignment: .top)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            hero
            voiceFirst
            activeList
            manualFallback
            settings
        }
        .onAppear { cursor.pulse(label: "MacB AI takipte") }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(colors: [MacBDesign.accent.opacity(0.35), .purple.opacity(0.20), .blue.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "scope")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                }
                .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 8) {
                    Text("MacB AI")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Konuşarak verdiğin takip ve web işlerini sakin sakin yürütür. Sayfa okuma localdir; tıklama, yazma ve dışarı etki eden işler sende onay bekler.")
                        .font(.system(size: MacBDesign.TypeScale.body))
                        .foregroundStyle(MacBDesign.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                stat("Aktif", "\(store.activeCount)", "bolt.fill")
                stat("Yakalanan", "\(store.triggeredCount)", "bell.badge.fill")
                stat("Durum", store.isChecking ? "Bakıyor" : "Sakin", store.isChecking ? "dot.radiowaves.left.and.right" : "checkmark.seal.fill")
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(MacBDesign.cardFill)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(MacBDesign.accent.opacity(0.16)).frame(width: 180, height: 180).blur(radius: 28).offset(x: 70, y: -90)
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(MacBDesign.cardStroke, lineWidth: 0.8))
    }

    private var voiceFirst: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [MacBDesign.accent.opacity(0.30), .pink.opacity(0.16), .cyan.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Konuş, MacB AI kursun")
                        .font(.system(size: MacBDesign.TypeScale.title, weight: .semibold))
                    Text("Bu ekran form doldurman için değil. “Bu ürün ucuzlayınca söyle”, “şu sitede stok gelirse haber ver” ya da “tarayıcıdaki rezervasyon formunu doldur” dediğinde MacB işi burada sakince yönetir.")
                        .font(.system(size: MacBDesign.TypeScale.caption))
                        .foregroundStyle(MacBDesign.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                promptChip("Bu ürün 20.000 altına düşünce haber ver", "tag")
                promptChip("Bu sayfada stok gelirse söyle", "text.page")
                promptChip("Bu GitHub reposuna yeni sürüm çıkınca haber ver", "shippingbox")
                promptChip("CPU 85 üstüne çıkarsa uyar", "gauge.with.dots.needle.67percent")
                promptChip("Aktif tarayıcıdaki sayfayı oku", "safari")
                promptChip("Rezervasyon formunu doldur, göndermeden bana sor", "cursorarrow.click")
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .overlay(alignment: .bottomLeading) {
                    Circle().fill(MacBDesign.accent.opacity(0.10)).frame(width: 150, height: 150).blur(radius: 24).offset(x: -70, y: 76)
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(MacBDesign.cardStroke, lineWidth: 0.8))
    }

    private func promptChip(_ text: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                .foregroundStyle(MacBDesign.accent)
            Text(text)
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(MacBDesign.cardStroke.opacity(0.85), lineWidth: 0.7))
    }

    private func stat(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold)).monospacedDigit()
                Text(title).font(.system(size: MacBDesign.TypeScale.micro, weight: .medium)).foregroundStyle(MacBDesign.muted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var quickCreate: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Elle takip ekle")
                    .font(.system(size: MacBDesign.TypeScale.title, weight: .semibold))
                Text("Normalde konuşarak kuracaksın; bu bölüm yedek. Link, repo veya sistem eşiği yazarsan MacB AI onu da takip eder.")
                    .font(.system(size: MacBDesign.TypeScale.caption))
                    .foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: quickColumns, spacing: 12) {
                creatorCard(symbol: "tag", title: "Ürün fiyatı", detail: "Ürün linkini ve almak istediğin en yüksek fiyatı gir. Altına inerse haber verir.", tint: .orange) {
                    TextField("Ürün linki", text: $priceURL).textFieldStyle(.roundedBorder)
                    TextField("Hedef fiyat, örn. 19999", text: $priceThreshold).textFieldStyle(.roundedBorder)
                    Button("Fiyat düşünce haber ver") { addPrice() }.disabled(priceURL.isEmpty || Double(priceThreshold.replacingOccurrences(of: ",", with: ".")) == nil)
                }
                creatorCard(symbol: "text.page", title: "Sayfa değişimi", detail: "Bir yazı görünürse haber verir. Yazıyı boş bırakırsan sayfanın genel değişimini izler.", tint: .cyan) {
                    TextField("Sayfa linki", text: $textURL).textFieldStyle(.roundedBorder)
                    TextField("Aranacak yazı, örn. stokta", text: $textNeedle).textFieldStyle(.roundedBorder)
                    Button("Sayfayı takip et") { addText() }.disabled(textURL.isEmpty)
                }
                creatorCard(symbol: "shippingbox", title: "GitHub sürümü", detail: "Bir repo yaz. Yeni release/tag çıkınca MacB AI sana haber verir.", tint: .purple) {
                    TextField("owner/repo veya GitHub linki", text: $repo).textFieldStyle(.roundedBorder)
                    Button("Yeni sürümü takip et") { addRelease() }.disabled(repo.isEmpty)
                }
                creatorCard(symbol: "gauge.with.dots.needle.67percent", title: "Mac yorulunca", detail: "CPU, bellek veya pil belli seviyeye gelince haber verir. Örn. CPU 85 üstüne çıkarsa.", tint: .green) {
                    Picker("Metrik", selection: $metric) {
                        Text("CPU").tag(WatchMetric.cpuPercent)
                        Text("Bellek").tag(WatchMetric.memoryPercent)
                        Text("Pil").tag(WatchMetric.batteryPercent)
                    }.pickerStyle(.segmented)
                    TextField("Seviye, örn. 85", text: $systemThreshold).textFieldStyle(.roundedBorder)
                    Button("Bu seviyede haber ver") { addSystem() }.disabled(Double(systemThreshold.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
        }
    }

    private var manualFallback: some View {
        DisclosureGroup(isExpanded: $showManualCreate) {
            quickCreate
                .padding(.top, 12)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                    .foregroundStyle(MacBDesign.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Elle eklemek gerekirse")
                        .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold))
                    Text("Konuşma yerine direkt link girmek istediğinde aç.")
                        .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
                        .foregroundStyle(MacBDesign.muted)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.030), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MacBDesign.cardStroke, lineWidth: 0.7))
    }

    private func creatorCard<Content: View>(symbol: String, title: String, detail: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Image(systemName: symbol)
                        .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 28, height: 28)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text(title).font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold))
                }
                Text(detail)
                    .font(.system(size: MacBDesign.TypeScale.caption))
                    .foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(MacBDesign.cardStroke, lineWidth: 0.7))
    }

    private var activeList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MacB AI’ın işleri").font(.system(size: MacBDesign.TypeScale.title, weight: .semibold))
                Spacer()
                if store.isChecking { ProgressView().controlSize(.small) }
            }
            if store.tasks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(MacBDesign.accent)
                    Text("Henüz iş yok")
                        .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold))
                    Text("Konuşarak bir takip, web işi veya sistem uyarısı verdiğinde burada canlı kart olarak duracak.")
                        .font(.system(size: MacBDesign.TypeScale.caption))
                        .foregroundStyle(MacBDesign.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(26)
                .background(Color.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                ForEach(store.tasks) { task in watchRow(task) }
            }
            if let error = store.errorMessage {
                Text(error).font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(.orange)
            }
        }
    }

    private func watchRow(_ task: WatchTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: task.kind.symbol)
                .font(.system(size: MacBDesign.TypeScale.title, weight: .semibold))
                .foregroundStyle(statusColor(task))
                .frame(width: 38, height: 38)
                .background(statusColor(task).opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(task.title).font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold)).lineLimit(1)
                    Text(task.status.title)
                        .font(.system(size: MacBDesign.TypeScale.micro, weight: .bold))
                        .foregroundStyle(statusColor(task))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(statusColor(task).opacity(0.12), in: Capsule())
                }
                Text(task.condition.title)
                    .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
                    .foregroundStyle(MacBDesign.muted)
                    .lineLimit(1)
                Text([task.lastValue, task.errorMessage, lastChecked(task)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
                    .foregroundStyle(MacBDesign.muted.opacity(0.82))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { task.isEnabled }, set: { store.setEnabled(task, $0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            Button { Task { await store.check(id: task.id) } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).help("Şimdi kontrol et")
            Button(role: .destructive) { store.remove(task) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).help("Kaldır")
        }
        .padding(13)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(MacBDesign.cardStroke, lineWidth: 0.7))
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ajan görünürlüğü").font(.system(size: MacBDesign.TypeScale.title, weight: .semibold))
            Toggle(isOn: $cursor.isEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ekranda MacB imleç göstergesi")
                        .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
                    Text("MacB bir sayfayı kontrol ederken küçük bir imleç etiketi gösterir. Gerçek mouse’u oynatmaz; sadece ne yaptığını görünür kılar.")
                        .font(.system(size: MacBDesign.TypeScale.caption))
                        .foregroundStyle(MacBDesign.muted)
                }
            }
            .toggleStyle(.switch)
            Button("Göstergede dene") { cursor.pulse(label: "MacB burada") }
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(MacBDesign.cardStroke, lineWidth: 0.7))
    }

    private func addPrice() {
        guard let threshold = Double(priceThreshold.replacingOccurrences(of: ",", with: ".")) else { return }
        store.addWebsitePrice(title: hostTitle(priceURL, fallback: "Fiyat takibi"), url: priceURL, threshold: threshold)
        priceURL = ""; priceThreshold = ""
    }

    private func addText() {
        store.addWebsiteText(title: hostTitle(textURL, fallback: "Site takibi"), url: textURL, text: textNeedle)
        textURL = ""; textNeedle = ""
    }

    private func addRelease() {
        store.addGitHubRelease(title: repo, repository: repo)
        repo = ""
    }

    private func addSystem() {
        guard let threshold = Double(systemThreshold.replacingOccurrences(of: ",", with: ".")) else { return }
        store.addSystemMetric(title: metric.title, metric: metric, threshold: threshold)
    }

    private func statusColor(_ task: WatchTask) -> Color {
        switch task.status {
        case .triggered: return MacBDesign.accent
        case .failed: return .red
        case .checking: return .blue
        case .ok: return .green
        case .idle: return MacBDesign.muted
        }
    }

    private func lastChecked(_ task: WatchTask) -> String? {
        guard let date = task.lastCheckedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func hostTitle(_ raw: String, fallback: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        return URL(string: text)?.host ?? fallback
    }
}
