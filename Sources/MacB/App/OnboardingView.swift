import SwiftUI

struct OnboardingView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var permissions: PermissionStore
    let finish: () -> Void
    @State private var page = 0

    private let pages = 3

    var body: some View {
        ZStack {
            onboardingBackground
            VStack(spacing: 0) {
                ZStack {
                    switch page {
                    case 0: welcome
                    case 1: features
                    default: access
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
        }
        .frame(width: 720, height: 520)
        .background(MacBDesign.surface)
        .tint(MacBDesign.accent)
        .onAppear { page = 0 }
    }

    private var onboardingBackground: some View {
        ZStack {
            LinearGradient(colors: [MacBDesign.accent.opacity(0.16), Color.clear, Color.primary.opacity(0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(MacBDesign.accent.opacity(0.20)).blur(radius: 64).frame(width: 210, height: 210).offset(x: -270, y: -185)
            Circle().fill(Color.blue.opacity(0.09)).blur(radius: 76).frame(width: 240, height: 240).offset(x: 270, y: 180)
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .rotationEffect(.degrees(-8))
                .frame(width: 360, height: 180)
                .offset(x: 235, y: -185)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: MacBDesign.Space.regular) {
                Button("Geri") { page -= 1 }
                    .disabled(page == 0)
                    .opacity(page == 0 ? 0 : 1)
                Spacer()
                HStack(spacing: MacBDesign.Space.snug) {
                    ForEach(0..<pages, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? MacBDesign.accent : Color.secondary.opacity(0.25))
                            .frame(width: index == page ? 18 : 6, height: 6)
                            .motion(MacBDesign.Motion.quick, value: page)
                            .accessibilityHidden(true)
                    }
                }
                Spacer()
                Button(page == pages - 1 ? "MacB’yi kullan" : "Devam") {
                    if page == pages - 1 { finish() } else { page += 1 }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
    }

    private var welcome: some View {
        HStack(alignment: .center, spacing: 34) {
            VStack(alignment: .leading, spacing: MacBDesign.Space.section) {
                Label("LOCAL-FIRST MAC YARDIMCIN", systemImage: "sparkles")
                    .font(.system(size: MacBDesign.TypeScale.micro, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(MacBDesign.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(MacBDesign.accent.opacity(0.12), in: Capsule())
                VStack(alignment: .leading, spacing: MacBDesign.Space.close) {
                    Text("MacB, Mac’inin üst kenarında sakin bir kontrol alanı.")
                        .font(.system(size: 34, weight: .semibold))
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Medya, pano, pencere ve küçük işleri hesabın olmadan, sunucuya bağlanmadan, bu Mac’te yönetir.")
                        .font(.system(size: MacBDesign.TypeScale.emphasis))
                        .foregroundStyle(MacBDesign.muted)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: MacBDesign.Space.close) {
                    heroChip("Sunucusuz", "lock.shield")
                    heroChip("Hızlı", "bolt.fill")
                    heroChip("Geri alınabilir", "arrow.uturn.backward")
                }
            }
            .frame(width: 330, alignment: .leading)

            notchPreview
        }
        .padding(42)
    }

    private var notchPreview: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.90))
                .frame(width: 300, height: 82)
                .overlay {
                    HStack(spacing: MacBDesign.Space.regular) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(MacBDesign.accent)
                        Text("MacB")
                            .foregroundStyle(.white)
                        Text("hazır")
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .font(.system(size: MacBDesign.TypeScale.title, weight: .semibold))
                }
                .shadow(color: .black.opacity(0.28), radius: 28, y: 16)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: MacBDesign.Space.regular) {
                previewTile("Medya", "music.note", "Çalan şey burada")
                previewTile("Pano", "doc.on.clipboard", "Kopyaladıkların")
                previewTile("Pencere", "macwindow", "Hızlı geçiş")
                previewTile("Raf", "tray.full", "Dosyalar el altında")
            }
        }
        .frame(width: 280)
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.primary.opacity(0.065)))
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.section) {
            VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
                Text("Nasıl çalışsın?")
                    .font(.system(size: MacBDesign.TypeScale.display, weight: .semibold))
                Text("Hepsi sonradan değişir. Başlangıçta sadece kullanacağın parçaları aç.")
                    .font(.system(size: MacBDesign.TypeScale.body))
                    .foregroundStyle(MacBDesign.muted)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: MacBDesign.Space.regular) {
                featureToggle("Dock önizlemeleri", "Dock’ta bekleyince pencereleri gösterir.", "rectangle.on.rectangle", $preferences.dockEnabled)
                featureToggle("Notch paneli", "Medya, pano ve raf üst kenarda durur.", "rectangle.topthird.inset.filled", $preferences.notchEnabled)
                featureToggle("Pencere seçici", "Pencereler arasında görerek geçersin.", "rectangle.3.group", $preferences.switcherEnabled)
            }
            Label("MacB’yi menü çubuğundan her zaman açabilirsin. Kapatırsan özellikler kaybolmaz; sadece sakinleşir.",
                  systemImage: "menubar.rectangle")
                .font(.system(size: MacBDesign.TypeScale.caption))
                .foregroundStyle(MacBDesign.muted)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(42)
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.section) {
            VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
                Text("İzinleri sakin sakin ver.")
                    .font(.system(size: MacBDesign.TypeScale.display, weight: .semibold))
                Text("MacB yalnız açtığın özellik için izin ister. İzin vermezsen uygulama yine çalışır; ilgili özellik bekler.")
                    .font(.system(size: MacBDesign.TypeScale.body))
                    .foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: MacBDesign.Space.regular) {
                if preferences.dockEnabled || preferences.switcherEnabled {
                    accessRow("Erişilebilirlik", "Pencereleri bulmak ve seçtiğin pencereye geçmek için.", permissions.accessibility, permissions.requestAccessibility)
                    accessRow("Ekran kaydı", "Yalnız canlı pencere önizlemeleri için. Görüntüler diske yazılmaz.", permissions.screenCapture, permissions.requestScreenCapture)
                }
                if preferences.switcherEnabled && preferences.shortcut == .commandTab {
                    accessRow("Giriş izleme", "⌘ Tab kısayolunu güvenilir biçimde algılamak için.", permissions.inputMonitoring, permissions.requestInputMonitoring)
                }
                if !(preferences.dockEnabled || preferences.switcherEnabled) {
                    emptyPermissionState
                }
            }
            Label("MacB telemetri, hesap veya sunucu kullanmaz. Veriler bu Mac’te kalır.", systemImage: "hand.raised.fill")
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
                .foregroundStyle(MacBDesign.muted)
        }
        .padding(42)
        .onAppear { permissions.startObserving() }
    }

    private var emptyPermissionState: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: MacBDesign.TypeScale.hero, weight: .semibold))
                .foregroundStyle(Color.green)
            Text("Şimdilik ekstra izin gerekmiyor.")
                .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold))
            Text("Notch paneli kapalıysa MacB menü çubuğunda sakin şekilde bekler.")
                .font(.system(size: MacBDesign.TypeScale.caption))
                .foregroundStyle(MacBDesign.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func heroChip(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.045), in: Capsule())
    }

    private func previewTile(_ title: String, _ symbol: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
            Image(systemName: symbol)
                .font(.system(size: MacBDesign.TypeScale.title, weight: .semibold))
                .foregroundStyle(MacBDesign.accent)
            Text(title)
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
            Text(detail)
                .font(.system(size: MacBDesign.TypeScale.micro))
                .foregroundStyle(MacBDesign.muted)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func featureToggle(_ title: String, _ detail: String, _ symbol: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: MacBDesign.Space.regular) {
                Image(systemName: symbol)
                    .font(.system(size: MacBDesign.TypeScale.heading, weight: .semibold))
                    .foregroundStyle(value.wrappedValue ? MacBDesign.accent : MacBDesign.muted)
                VStack(alignment: .leading, spacing: MacBDesign.Space.tight) {
                    Text(title)
                        .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold))
                    Text(detail)
                        .font(.system(size: MacBDesign.TypeScale.caption))
                        .foregroundStyle(MacBDesign.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(value.wrappedValue ? MacBDesign.accent.opacity(0.10) : Color.primary.opacity(0.032),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(value.wrappedValue ? MacBDesign.accent.opacity(0.42) : MacBDesign.cardStroke,
                          lineWidth: value.wrappedValue ? 1.1 : 0.5))
        .motion(MacBDesign.Motion.quick, value: value.wrappedValue)
    }

    private func accessRow(_ title: String, _ detail: String, _ granted: Bool, _ action: @escaping () -> Void) -> some View {
        HStack(spacing: MacBDesign.Space.comfortable) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: MacBDesign.TypeScale.heading, weight: .semibold))
                .foregroundStyle(granted ? Color.green : MacBDesign.muted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: MacBDesign.Space.tight) {
                Text(title).font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold))
                Text(detail).font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted {
                Text("Hazır")
                    .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12), in: Capsule())
            } else {
                Button("İzin ver", action: action)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}
