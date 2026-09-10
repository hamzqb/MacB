import SwiftUI

struct OnboardingView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var permissions: PermissionStore
    let finish: () -> Void
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0: welcome
                case 1: features
                default: access
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                if page > 0 { Button("Geri") { page -= 1 } }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle().fill(index == page ? MacBDesign.accent : Color.secondary.opacity(0.25))
                            .frame(width: 6, height: 6).accessibilityHidden(true)
                    }
                }
                Spacer()
                Button(page == 2 ? "MacB’yi kullan" : "Devam") {
                    if page == 2 { finish() } else { page += 1 }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 620, height: 470)
        .background(MacBDesign.surface)
        .tint(MacBDesign.accent)
        .onAppear { page = 0 }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .font(.system(size: 42, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(MacBDesign.accent)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("MacB’ye hoş geldin").font(.system(size: 29, weight: .semibold))
                Text("Pencerelerin, medyan ve sık kullandığın araçlar\nmenü çubuğundan bir dokunuş uzağında.")
                    .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                featureCard("Dock", "macwindow.on.rectangle", "Pencere önizlemeleri")
                featureCard("Notch", "rectangle.topthird.inset.filled", "Medya ve dosya rafı")
                featureCard("Pencereler", "rectangle.3.group", "Hızlı geçiş ve yerleşim")
            }
            .padding(.horizontal, 34)
        }
        .padding(28)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Çalışma alanını seç").font(.system(size: 25, weight: .semibold))
                Text("Bunları daha sonra Ayarlar’dan değiştirebilirsin.").foregroundStyle(.secondary)
            }
            onboardingToggle("Dock önizlemeleri", "Dock simgesinde bekleyince pencereleri göster.", $preferences.dockEnabled)
            onboardingToggle("Notch paneli", "Medya, dosya, pano ve işleri üst kenarda tut.", $preferences.notchEnabled)
            onboardingToggle("Pencere seçici", "⌘ Tab ile uygulama pencerelerini önizleyerek değiştir.", $preferences.switcherEnabled)
            Label("MacB Dock’ta görünmez; ekranın sağ üstündeki menü çubuğu simgesinden her zaman açılır.",
                  systemImage: "menubar.rectangle")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(12)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(38)
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Gerekli erişimler").font(.system(size: 25, weight: .semibold))
                Text("MacB yalnız açtığın özellikler için izin ister. İzinleri sonra da verebilirsin.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if preferences.dockEnabled || preferences.switcherEnabled {
                accessRow("Erişilebilirlik", "Pencereleri bulmak ve seçtiğin pencereye geçmek için.",
                          permissions.accessibility, permissions.requestAccessibility)
                accessRow("Ekran kaydı", "Yalnız açık kartlarda canlı pencere önizlemesi için.",
                          permissions.screenCapture, permissions.requestScreenCapture)
            }
            if preferences.switcherEnabled && preferences.shortcut == .commandTab {
                accessRow("Giriş izleme", "⌘ Tab kısayolunu güvenilir biçimde algılamak için.",
                          permissions.inputMonitoring, permissions.requestInputMonitoring)
            }
            Label("Pencere görüntüleri diske yazılmaz. MacB telemetri veya kullanıcı hesabı kullanmaz.",
                  systemImage: "hand.raised.fill")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(38)
        .onAppear { permissions.startObserving() }
    }

    private func featureCard(_ title: String, _ symbol: String, _ detail: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 21)).foregroundStyle(MacBDesign.accent)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).frame(height: 105)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
    }

    private func onboardingToggle(_ title: String, _ detail: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.toggleStyle(.switch)
    }

    private func accessRow(_ title: String, _ detail: String, _ granted: Bool, _ action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 19)).foregroundStyle(granted ? Color.green : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if granted { Text("Hazır").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary) }
            else { Button("İzin ver", action: action).controlSize(.small) }
        }
        .padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
    }
}
