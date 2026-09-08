import AppKit
import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "Genel", appearance = "Görünüm", permissions = "İzinler"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "circle.lefthalf.filled"
        case .permissions: return "hand.raised"
        }
    }
    var subtitle: String {
        switch self {
        case .general: return "MacB, çalışma şekline uyum sağlasın."
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
    @ObservedObject var shelf: ShelfStore
    var shortcutError: String?
    var openPanel: () -> Void
    @State private var selectedPage: SettingsPage = .general
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
                Text("Sürüm 0.1.0").font(.system(size: 10, design: .monospaced))
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
                settingToggle("Notch paneli", detail: "Spotify ve dosya rafını ekranın üst kenarından aç.", isOn: $preferences.notchEnabled)
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
                if let shortcutError { message(shortcutError, warning: true) }
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
        }
    }

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 28) {
            section("Panel davranışı") {
                settingToggle("Küçük göstergeler", detail: "Panel kapalıyken oynatma durumunu ve raftaki öğe sayısını göster.", isOn: $preferences.compactIndicators)
                rowDivider
                settingToggle("Yumuşak geçişler", detail: "Paneller açılırken ve kapanırken kısa animasyonlar kullan.", isOn: $preferences.animationsEnabled)
                rowDivider
                settingToggle("Pencere peek modu", detail: "Kartta bekleyince pencerenin ekrandaki yerini hafifçe vurgula.", isOn: $preferences.peekEnabled)
                rowDivider
                settingToggle("Notch hızlı komutları", detail: "Masaüstü, Finder, Terminal ve ekran görüntüsü komutlarını müzik paneline ekle.", isOn: $preferences.quickCommandsEnabled)
            }
            section("Raf yardımcıları") {
                settingToggle("Son dosyalar", detail: "Downloads, Desktop ve Documents içinden son dosyaları öner. macOS klasör erişimi isteyebilir.", isOn: $preferences.recentFilesEnabled)
                rowDivider
                settingToggle("Mini pano rafı", detail: "Son kopyaladığın metinleri geçici olarak Dosyalar görünümünde tut.", isOn: $preferences.clipboardShelfEnabled)
                rowDivider
                settingToggle("İndirme göstergesi", detail: "Downloads klasöründeki yeni dosyaları göster. macOS klasör erişimi isteyebilir.", isOn: $preferences.fileActivityEnabled)
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
            Text("Bir izin kapalıyken diğer özellikler çalışmaya devam eder. macOS yeniden başlatma isterse MacB’yi kapatıp aç.")
                .font(.system(size: 11)).foregroundStyle(MacBDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private var rowDivider: some View { Divider().opacity(0.45) }

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
