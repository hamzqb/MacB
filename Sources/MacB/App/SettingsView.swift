import AppKit
import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "Genel", windows = "Pencereler", tools = "Araçlar", appearance = "Görünüm", permissions = "İzinler"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .windows: return "rectangle.split.2x1"
        case .tools: return "wrench.and.screwdriver"
        case .appearance: return "circle.lefthalf.filled"
        case .permissions: return "hand.raised"
        }
    }
    var subtitle: String {
        switch self {
        case .general: return "MacB, çalışma şekline uyum sağlasın."
        case .windows: return "Pencerelerini daha az uğraşla yerleştir."
        case .tools: return "Günlük işlerin için güvenli, yerel yardımcılar."
        case .appearance: return "Küçük ayrıntılar, daha sakin bir masaüstü."
        case .permissions: return "Hangi özelliklerin erişimi olacağı senin elinde."
        }
    }
}

struct SettingsView: View {
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
    @ObservedObject var keyboardCleaning: KeyboardCleaningService
    @ObservedObject var updates: UpdateService
    var openPanel: () -> Void
    @AppStorage("settingsPage") private var selectedPage: SettingsPage = .general
    @State private var showRemovalConfirmation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.55)
            ScrollView {
                VStack(alignment: .leading, spacing: MacBDesign.contentSpacing) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedPage.rawValue)
                            .font(.system(size: 27, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text(selectedPage.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(MacBDesign.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    switch selectedPage {
                    case .general: generalPage
                    case .windows: windowsPage
                    case .tools: toolsPage
                    case .appearance: appearancePage
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
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(MacBDesign.surface)
        .tint(MacBDesign.accent)
        .alert("Seçilen öğeler Çöp Sepeti’ne taşınsın mı?", isPresented: $showRemovalConfirmation) {
            Button("Vazgeç", role: .cancel) {}
            Button("Çöp Sepeti’ne Taşı", role: .destructive, action: utilities.removeInspectedApplication)
        } message: {
            Text("\(utilities.selectedApplicationName) ile ilişkili \(utilities.selectedRemovalCandidates.count) öğe taşınacak. Kaynakları silmeden önce listeden seçimini kontrol et.")
        }
    }

    private var windowsPage: some View {
        VStack(alignment: .leading, spacing: 28) {
            section("Pencere yönetimi") {
                settingToggle("Pencere kısayolları", detail: "Etkin pencereyi ekranın yarısına, köşesine veya başka ekrana taşı.",
                              isOn: $preferences.windowManagementEnabled)
                if preferences.windowManagementEnabled {
                    message("Erişilebilirlik izni gerekir. Kısayollar her uygulamadaki etkin pencere üzerinde çalışır.")
                }
            }
            if preferences.windowManagementEnabled {
                Divider().opacity(0.55)
                section("Temel yerleşimler") {
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
                Divider().opacity(0.55)
                section("Köşeler ve ekranlar") {
                    shortcutRow("Sol üst / Sağ üst", symbol: "rectangle.split.2x1", keys: "⌃⌥U  /  ⌃⌥I")
                    rowDivider
                    shortcutRow("Sol alt / Sağ alt", symbol: "rectangle.split.2x1", keys: "⌃⌥J  /  ⌃⌥K")
                    rowDivider
                    shortcutRow("Önceki boyut", symbol: "arrow.uturn.backward", keys: "⌃⌥⌫")
                    rowDivider
                    shortcutRow("Sonraki ekran", symbol: "display.2", keys: "⌃⌥⌘→")
                }
            }
        }
    }

    private var toolsPage: some View {
        VStack(alignment: .leading, spacing: 28) {
            section("Claude ve Codex") {
                if aiActivity.activities.isEmpty {
                    message("Açık masaüstü veya terminal oturumu bulunmadı.")
                } else {
                    ForEach(aiActivity.activities.prefix(5)) { activity in
                        HStack(spacing: 10) {
                            Image(systemName: activity.kind.symbol).foregroundStyle(MacBDesign.accent).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.kind.rawValue).font(.system(size: 13, weight: .medium))
                                Text("\(activity.source) · \(activity.elapsedText)").font(.system(size: 11)).foregroundStyle(MacBDesign.muted)
                            }
                            Spacer()
                            Circle().fill(Color.green).frame(width: 7, height: 7).accessibilityLabel("Çalışıyor")
                        }
                    }
                }
            }
            Divider().opacity(0.55)
            section("Sistem") {
                HStack(spacing: 10) {
                    systemMetric("CPU", "\(Int(systemMonitor.snapshot.cpuUsage))%")
                    systemMetric("RAM", percentage(systemMonitor.snapshot.usedMemory, systemMonitor.snapshot.totalMemory))
                    systemMetric("Disk", percentage(UInt64(max(0, systemMonitor.snapshot.totalDisk - systemMonitor.snapshot.availableDisk)), UInt64(max(0, systemMonitor.snapshot.totalDisk))))
                    systemMetric("Pil", systemMonitor.snapshot.batteryPercent.map { "\(Int($0))%" } ?? "—")
                }
                Label(thermalText, systemImage: "thermometer.medium")
                    .font(.system(size: 11)).foregroundStyle(MacBDesign.muted)
            }
            Divider().opacity(0.55)
            section("Klavye temizleme") {
                Text("Klavye girişini geçici olarak durdurur. Fare çalışır; üç kez Esc acil çıkıştır.")
                    .font(.system(size: 12)).foregroundStyle(MacBDesign.muted)
                HStack(spacing: 9) {
                    if keyboardCleaning.isActive {
                        Button("Kilidi aç", action: keyboardCleaning.stop)
                        Text("\(keyboardCleaning.remainingSeconds) sn").font(.system(size: 11, design: .monospaced)).foregroundStyle(MacBDesign.muted)
                    } else {
                        Button("30 saniye") { keyboardCleaning.start(duration: 30) }
                        Button("1 dakika") { keyboardCleaning.start(duration: 60) }
                        Button("2 dakika") { keyboardCleaning.start(duration: 120) }
                    }
                }
                if let error = keyboardCleaning.errorMessage { message(error, warning: true) }
            }
            Divider().opacity(0.55)
            section("Arşiv") {
                Text("Dosyaları MacB içinde ZIP olarak sıkıştır veya güvenli biçimde çıkar.")
                    .font(.system(size: 12)).foregroundStyle(MacBDesign.muted)
                HStack(spacing: 9) {
                    Button("ZIP oluştur…", action: utilities.createArchive)
                    Button("ZIP çıkar…", action: utilities.extractArchive)
                }
            }
            Divider().opacity(0.55)
            section("Uygulama kaldırma") {
                Text("Uygulamayı ve ilişkili kullanıcı kalıntılarını önce gösterir, sonra Çöp Sepeti’ne taşır.")
                    .font(.system(size: 12)).foregroundStyle(MacBDesign.muted)
                Button("Uygulama seç…", action: utilities.inspectApplication)
                if !utilities.removalCandidates.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(utilities.selectedApplicationName) · \(utilities.removalCandidates.count) öğe · \(ByteCountFormatter.string(fromByteCount: utilities.removalSize, countStyle: .file))")
                            .font(.system(size: 12, weight: .medium))
                        ForEach(utilities.removalCandidates) { candidate in
                            Toggle(isOn: Binding(get: { utilities.isSelected(candidate) }, set: { _ in utilities.toggleRemoval(candidate) })) {
                                Text(candidate.url.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(MacBDesign.muted)
                                    .lineLimit(2).help(candidate.url.path)
                            }.toggleStyle(.checkbox)
                        }
                        Button("Seçilenleri Çöp Sepeti’ne taşı", role: .destructive) { showRemovalConfirmation = true }
                            .disabled(utilities.selectedRemovalCandidates.isEmpty)
                    }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Divider().opacity(0.55)
            section("MacWhisper") {
                Text(utilities.macWhisperInstalled ? "Ses veya video dosyasını MacWhisper’a gönder." : "MacWhisper kurulu değil.")
                    .font(.system(size: 12)).foregroundStyle(MacBDesign.muted)
                Button("Dosya gönder…", action: utilities.sendAudioToMacWhisper).disabled(!utilities.macWhisperInstalled)
            }
            if utilities.isWorking { ProgressView().controlSize(.small) }
            if let status = utilities.statusMessage { message(status, warning: false) }
        }
        .onAppear { systemMonitor.refresh() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 36, height: 36)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                Text("MacB").font(.system(size: 21, weight: .semibold))
            }
            .padding(.horizontal, 10)
            VStack(spacing: 5) {
                ForEach(SettingsPage.allCases) { page in
                    Button { selectedPage = page } label: {
                        HStack(spacing: 10) {
                            Image(systemName: page.icon)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(selectedPage == page ? MacBDesign.accent : MacBDesign.muted)
                                .frame(width: 19)
                                .accessibilityHidden(true)
                            Text(page.rawValue).font(.system(size: 13, weight: selectedPage == page ? .medium : .regular))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .background(selectedPage == page ? MacBDesign.accent.opacity(0.11) : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedPage == page ? [.isSelected] : [])
                }
            }
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text("Ücretsiz ve açık kaynak").font(.system(size: 10))
                Text("Sürüm \(AppVersion.current)").font(.system(size: 10, design: .monospaced))
            }
            .foregroundStyle(MacBDesign.muted)
            .padding(.horizontal, 10)
        }
        .padding(.horizontal, 12)
        .padding(.top, 29)
        .padding(.bottom, 24)
        .frame(width: MacBDesign.sidebarWidth)
        .background(Color.primary.opacity(0.025))
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 28) {
            section("Çalışma alanı") {
                settingToggle("Dock önizlemeleri", detail: "Bir simgenin üzerinde bekle, istediğin pencereye geç.", isOn: $preferences.dockEnabled)
                rowDivider
                settingToggle("Notch paneli", detail: "Medya, dosya, pano ve işlerini ekranın üst kenarından aç.", isOn: $preferences.notchEnabled)
                rowDivider
                settingToggle("Pencere seçici", detail: "Kısayolu basılı tut, Tab ile ilerle, bırakarak seç.", isOn: $preferences.switcherEnabled)
                if preferences.switcherEnabled {
                    HStack(spacing: 12) {
                        Text("Klavye kısayolu").font(.system(size: 12)).foregroundStyle(MacBDesign.muted)
                        Spacer(minLength: 4)
                        Picker("Klavye kısayolu", selection: $preferences.shortcut) {
                            ForEach(SwitcherShortcut.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 144)
                    }
                    .padding(.top, 2)
                }
                if let shortcutError = hotKey.registrationError { message(shortcutError, warning: true) }
            }
            Divider().opacity(0.55)
            section("Akıllı akış") {
                settingToggle("Akıllı Notch", detail: "Panel açılırken müzik, raf ve indirme durumuna göre doğru bölümü öne çıkar.", isOn: $preferences.smartNotchEnabled)
                rowDivider
                settingToggle("Favori pencereler", detail: "Yıldızladığın pencereleri Dock ve pencere seçicide üstte tut.", isOn: $preferences.favoriteWindowsEnabled)
                rowDivider
                settingToggle("Uygulama grupları", detail: "Pencere seçicide aynı uygulamanın pencerelerini birlikte göster.", isOn: $preferences.groupedWindowsEnabled)
                rowDivider
                settingToggle("Odak modu", detail: "Seçtiğin pencere öne gelirken diğer uygulamaları gizle.", isOn: $preferences.focusModeEnabled)
            }
            Divider().opacity(0.55)
            section("Dosya rafı") {
                VStack(alignment: .leading, spacing: 5) {
                    Text(shelf.items.isEmpty ? "Dosyaların için küçük bir yer." : "\(shelf.items.count) öğe elinin altında.")
                        .font(.system(size: 13, weight: .medium))
                    Text("Dosyalar yerinde kalır. Raftan kaldırmak dosyayı silmez.")
                        .font(.system(size: 12)).foregroundStyle(MacBDesign.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button("Dosya ekle…", action: shelf.chooseFiles)
                    Button("Paneli aç", action: openPanel).disabled(!preferences.notchEnabled)
                }
                .controlSize(.regular)
                if !preferences.notchEnabled {
                    message("Paneli açmak için Notch panelini etkinleştir.")
                }
                if let error = shelf.errorMessage { message(error, warning: true) }
            }
            Divider().opacity(0.55)
            section("Güncellemeler") {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(updateTitle).font(.system(size: 13, weight: .medium))
                        Text(updateDetail).font(.system(size: 11)).foregroundStyle(MacBDesign.muted)
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

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 28) {
            section("Island yüzeyi") {
                Picker("Island yüzeyi", selection: $preferences.islandAppearance) {
                    ForEach(IslandAppearance.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Island yüzeyi")
            }
            section("Panel davranışı") {
                settingToggle("Küçük göstergeler", detail: "Panel kapalıyken oynatma durumunu ve raftaki öğe sayısını göster.", isOn: $preferences.compactIndicators)
                rowDivider
                settingToggle("Yumuşak geçişler", detail: "Paneller açılırken ve kapanırken kısa animasyonlar kullan.", isOn: $preferences.animationsEnabled)
                rowDivider
                settingToggle("Pencere peek modu", detail: "Kartta bekleyince pencerenin ekrandaki yerini hafifçe vurgula.", isOn: $preferences.peekEnabled)
            }
            section("Raf yardımcıları") {
                settingToggle("Son dosyalar", detail: "Downloads, Desktop ve Documents içinden son dosyaları öner. macOS klasör erişimi isteyebilir.", isOn: $preferences.recentFilesEnabled)
                rowDivider
                settingToggle("Mini pano rafı", detail: "Son kopyaladığın metinleri Pano görünümünde tut.", isOn: $preferences.clipboardShelfEnabled)
                rowDivider
                settingToggle("İndirme göstergesi", detail: "Downloads klasöründeki yeni dosyaları göster. macOS klasör erişimi isteyebilir.", isOn: $preferences.fileActivityEnabled)
            }
            section("Gizlilik") {
                settingToggle("Özel araçları kilitle", detail: "Pano ve kamera açılırken Touch ID, Apple Watch veya Mac parolanla doğrula.", isOn: $preferences.protectPrivateTools)
            }
            section("Yoğunluk") {
                Picker("Görünüm yoğunluğu", selection: $preferences.interfaceDensity) {
                    ForEach(InterfaceDensity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Görünüm yoğunluğu")
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "accessibility").font(.system(size: 16)).accessibilityHidden(true)
                Text(reduceMotion
                     ? "macOS’ta Hareketi Azalt açık. MacB bu tercihe uyar ve animasyonları kapalı tutar."
                     : "macOS’ta Hareketi Azalt açıldığında, MacB animasyonları otomatik olarak kapatır.")
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(MacBDesign.muted)
            .padding(16)
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
            permissionRow("Spotify otomasyonu", detail: "Parça bilgisini okumak ve oynatma kontrollerini kullanmak için.",
                          granted: spotify.isAuthorized,
                          actionTitle: spotify.isRunning ? "İzin ver" : "Spotify’ı aç",
                          action: spotify.isRunning ? spotify.requestAuthorization : spotify.openSpotify)
            if let error = spotify.errorMessage { message(error, warning: true) }
            rowDivider
            permissionRow("Apple Music otomasyonu", detail: "Apple Music parça bilgisini okumak ve oynatma kontrollerini kullanmak için.",
                          granted: appleMusic.isAuthorized,
                          actionTitle: appleMusic.isRunning ? "İzin ver" : "Apple Music’i aç",
                          action: appleMusic.isRunning ? appleMusic.requestAuthorization : appleMusic.openAppleMusic)
            if let error = appleMusic.errorMessage { message(error, warning: true) }
            rowDivider
            permissionRow("Tarayıcı medyası", detail: "Safari ve Chromium sekmelerinde yalnız gerçekten oynayan medyayı bulmak için.",
                          granted: browserMedia.isAuthorized,
                          actionTitle: browserMedia.isRunning ? "İzin ver" : "Tarayıcıyı aç",
                          action: browserMedia.isRunning ? browserMedia.requestAuthorization : openDefaultBrowser)
            if let error = browserMedia.errorMessage { message(error, warning: true) }
            rowDivider
            permissionRow("Kamera", detail: "Canlı önizleme yalnız sen kamera düğmesine bastığında çalışır.",
                          granted: camera.isAuthorized, actionTitle: "İzin ver", action: camera.requestAuthorization)
            if let error = camera.errorMessage { message(error, warning: true) }
            Text("Bir izin kapalıyken diğer özellikler çalışmaya devam eder. macOS yeniden başlatma isterse MacB’yi kapatıp aç.")
                .font(.system(size: 11)).foregroundStyle(MacBDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private var rowDivider: some View { Divider().opacity(0.45) }

    private func systemMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: 10)).foregroundStyle(MacBDesign.muted)
        }.frame(maxWidth: .infinity).frame(height: 52).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
    }

    private func percentage(_ used: UInt64, _ total: UInt64) -> String {
        total > 0 ? "\(Int(Double(used) / Double(total) * 100))%" : "—"
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

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 14, weight: .semibold)).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 16, content: content)
        }
    }

    private func settingToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private func shortcutRow(_ title: String, symbol: String, keys: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MacBDesign.muted)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer(minLength: 10)
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(MacBDesign.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(keys)")
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool,
                               actionTitle: String = "İzin ver", action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(MacBDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Label(granted ? "İzin verildi" : "İzin bekleniyor",
                      systemImage: granted ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 11))
                    .foregroundStyle(granted ? MacBDesign.accent : MacBDesign.muted)
                Spacer(minLength: 8)
                if !granted {
                    Button(actionTitle, action: action)
                        .controlSize(.small)
                        .accessibilityLabel("\(title): \(actionTitle)")
                }
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .contain)
    }

    private func message(_ text: String, warning: Bool = false) -> some View {
        Text(text).font(.system(size: 11))
            .foregroundStyle(warning ? Color(nsColor: .systemOrange) : MacBDesign.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
