import AppKit
import MacBCore
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "Genel", windows = "Pencereler", widgets = "Widget'lar", tools = "Araçlar", automation = "Otomasyon", appearance = "Görünüm", privacy = "Gizlilik", permissions = "İzinler"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .windows: return "rectangle.split.2x1"
        case .widgets: return "square.grid.2x2"
        case .tools: return "wrench.and.screwdriver"
        case .automation: return "wand.and.rays"
        case .appearance: return "circle.lefthalf.filled"
        case .privacy: return "faceid"
        case .permissions: return "hand.raised"
        }
    }
    var subtitle: String {
        switch self {
        case .general: return "MacB, çalışma şekline uyum sağlasın."
        case .windows: return "Pencerelerini daha az uğraşla yerleştir."
        case .widgets: return "Island'da ne göründüğüne ve hangi sırada durduğuna sen karar ver."
        case .tools: return "Günlük işlerin için güvenli, yerel yardımcılar."
        case .automation: return "Bir şey olunca MacB senin yerine yapsın."
        case .appearance: return "Küçük ayrıntılar, daha sakin bir masaüstü."
        case .privacy: return "Özel alanlarını neyin açacağına sen karar ver."
        case .permissions: return "Hangi özelliklerin erişimi olacağı senin elinde."
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
    @ObservedObject var briefing: BriefingService
    @ObservedObject var scenarios: ScenarioStore
    @ObservedObject var assistant: AIAssistantService
    @ObservedObject var arrangements: WindowArrangementService
    @ObservedObject var keepAwake: KeepAwakeService
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
                    case .automation: AutomationSettingsView(automation: automation, preferences: preferences)
                    case .appearance: appearancePage
                    case .privacy: PrivacySettingsView(faceUnlock: faceUnlock)
                    case .permissions: permissionsPage
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, MacBDesign.contentSpacing)
                .padding(.top, 30)
                .padding(.bottom, 28)
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

    private var toolsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
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
            section("Yapay zekâ anahtarları", "key.horizontal") {
                intro("Halkadaki Yapay zekâ dilimi, menüdeki \u{201C}Yapay zekâya sor\u{201D} ve seçili metin işleri bu anahtarlarla çalışır. Her anahtar Keychain'e yazılır — plist'e, dosyaya ya da koda değil — ve bir daha ekranda gösterilmez. Bir anahtar yalnız ait olduğu servise gider; giden tek şey sorduğun soru.")
                HStack(spacing: MacBDesign.Space.regular) {
                    Text("Soruları cevaplayan")
                        .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                    Spacer(minLength: 8)
                    Picker("Sağlayıcı", selection: $preferences.aiProvider) {
                        Text("Otomatik (ücretsiz olan)").tag("")
                        ForEach(AIProvider.textOrder) { provider in
                            Text(provider.title).tag(provider.rawValue)
                        }
                    }
                    .labelsHidden().fixedSize()
                }
                if let active = assistant.provider {
                    message("Şu an \(active.title) cevaplıyor." + (active.canSearchWeb ? "" : " Bu sağlayıcıda web araması yok, cevaplar kaynaksız gelir."))
                } else {
                    message("Hiç anahtar yok. Aşağıdan birini gir — Groq ücretsiz ve hızlı.", warning: true)
                }
                ForEach(AIProvider.textOrder) { provider in
                    rowDivider
                    providerRow(provider)
                }
                if let error = aiKey.errorMessage { message(error, warning: true) }
                message("Anahtarını bir yere yapıştırdıysan (sohbet, not, ekran görüntüsü) onu iptal et ve yenisini üret. Sızmış bir anahtar senin faturana çalışır.", warning: true)
            }
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
            section("Dock ve ⌘Tab", "dock.rectangle") {
                settingToggle("Dock'ta ve ⌘Tab'da görün",
                              detail: "Kapalıyken MacB yalnız island'da ve menü çubuğunda durur; ⌘Tab listesinde çıkmaz.",
                              isOn: $preferences.showInDock)
            }
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
                settingToggle("Sesli oku", detail: "macOS'un kendi Türkçe sesiyle. Ücretsiz, internetsiz.",
                              isOn: $preferences.briefingSpeaks)
                    .disabled(!preferences.briefingEnabled)
                HStack(spacing: MacBDesign.Space.close) {
                    Button("Şimdi dene") { briefing.give() }
                    if briefing.isVisible { Button("Kapat") { briefing.dismiss() } }
                    Spacer()
                }
                message("Her şey bu Mac'ten okunur, hiçbir yere gitmez, anahtar gerekmez. Takvim ve hatırlatıcılar yalnız izin verdiysen okunur.")
            }
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
                }
                HStack(spacing: MacBDesign.Space.regular) {
                    Text("Karakter").font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                    Spacer(minLength: 8)
                    Picker("Karakter", selection: $preferences.jarvisPersona) {
                        ForEach(JarvisPersona.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden().fixedSize()
                }
                message((JarvisPersona(rawValue: preferences.jarvisPersona) ?? .mirror).note)
                HStack(spacing: MacBDesign.Space.regular) {
                    Text("Model").font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
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
            section("Arşiv", "doc.zipper") {
                Text("Dosyaları MacB içinde ZIP olarak sıkıştır veya güvenli biçimde çıkar.")
                    .font(.system(size: MacBDesign.TypeScale.body)).foregroundStyle(MacBDesign.muted)
                HStack(spacing: MacBDesign.Space.regular) {
                    Button("ZIP oluştur…", action: utilities.createArchive)
                    Button("ZIP çıkar…", action: utilities.extractArchive)
                }
            }
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
            section("MacWhisper", "waveform") {
                Text(utilities.macWhisperInstalled ? "Ses veya video dosyasını MacWhisper’a gönder." : "MacWhisper kurulu değil.")
                    .font(.system(size: MacBDesign.TypeScale.body)).foregroundStyle(MacBDesign.muted)
                Button("Dosya gönder…", action: utilities.sendAudioToMacWhisper).disabled(!utilities.macWhisperInstalled)
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
                HStack(spacing: MacBDesign.Space.regular) {
                    TextField("Şehir", text: Binding(
                        get: { weather.placeQuery },
                        set: { weather.placeQuery = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .accessibilityLabel("Hava durumu şehri")
                    if weather.isLoading { ProgressView().controlSize(.small) }
                    Spacer()
                }
                Text("Şehir adı Open-Meteo üzerinden çözülür. Konum izni istenmez, sorgu yalnızca panel açıkken ve en fazla 15 dakikada bir yapılır.")
                    .font(.system(size: MacBDesign.TypeScale.caption))
                    .foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
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
            if let error = camera.errorMessage { message(error, warning: true) }
            Text("Bir izin kapalıyken diğer özellikler çalışmaya devam eder. macOS yeniden başlatma isterse MacB’yi kapatıp aç.")
                .font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, MacBDesign.Space.tight)
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
