import MacBCore
import SwiftUI

/// The Gizlilik page: face unlock for MacB's own private areas.
///
/// The page states the limits plainly, because they are the feature: MacB does
/// not unlock macOS, does not learn the Mac password, and keeps no pictures.
struct PrivacySettingsView: View {
    @ObservedObject var faceUnlock: FaceUnlockService
    @State private var enrollmentName = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("MacB Yüz Kilidi") {
                Toggle(isOn: Binding(
                    get: { faceUnlock.settings.isEnabled },
                    set: { value in faceUnlock.update { $0.isEnabled = value } }
                )) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Yüzümle aç").font(.system(size: 13, weight: .medium))
                        Text("Sadece MacB'nin kendi özel alanlarını açar. Mac oturumunu açmaz, Mac parolanı istemez, saklamaz.")
                            .font(.system(size: 12)).foregroundStyle(MacBDesign.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!faceUnlock.isEnrolled)
                .accessibilityLabel("Yüzümle aç")

                if !faceUnlock.isEnrolled {
                    enrollment
                } else {
                    enrolledSummary
                }
            }

            if faceUnlock.isEnrolled {
                section("Neyi korusun") {
                    ForEach(ProtectedArea.allCases, id: \.rawValue) { area in
                        Toggle(isOn: Binding(
                            get: { faceUnlock.settings.protectedAreas.contains(area) },
                            set: { value in
                                faceUnlock.update { settings in
                                    if value { settings.protectedAreas.insert(area) }
                                    else { settings.protectedAreas.remove(area) }
                                }
                            }
                        )) {
                            Label(area.title, systemImage: area.symbol)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }

                section("Eşleşme ve kilit") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Eşleşme sıkılığı").font(.system(size: 13, weight: .medium))
                        Picker("", selection: Binding(
                            get: { faceUnlock.settings.strictness },
                            set: { value in faceUnlock.update { $0.strictness = value } }
                        )) {
                            ForEach(FaceMatchStrictness.allCases, id: \.rawValue) { level in
                                Text(level.title).tag(level)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                        Text("Sıkı seçenek yanlış eşleşmeyi zorlaştırır, karanlıkta biraz daha çok deneme ister.")
                            .font(.system(size: 11)).foregroundStyle(MacBDesign.muted)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Boşta kalınca kilitle").font(.system(size: 13, weight: .medium))
                        Picker("", selection: Binding(
                            get: { faceUnlock.settings.idleRelockSeconds },
                            set: { value in faceUnlock.update { $0.idleRelockSeconds = value } }
                        )) {
                            ForEach(FaceUnlockSettings.idleRelockChoices, id: \.self) { seconds in
                                Text(relockTitle(seconds)).tag(seconds)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 300)
                    }
                }

                section("Kayıtlı yüzler") {
                    if faceUnlock.isVaultUnlocked {
                        ForEach(faceUnlock.identities) { identity in
                            HStack(spacing: 12) {
                                Toggle("", isOn: Binding(
                                    get: { identity.isEnabled },
                                    set: { faceUnlock.setIdentity(identity.id, enabled: $0) }
                                ))
                                .labelsHidden()
                                .accessibilityLabel(identity.name)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(identity.name).font(.system(size: 13, weight: .medium))
                                    Text("\(identity.samples.count) örnek · \(identity.embedderIdentifier)")
                                        .font(.system(size: 11)).foregroundStyle(MacBDesign.muted)
                                }
                                Spacer()
                                Button("Sil", role: .destructive) { faceUnlock.remove(identity.id) }
                                    .controlSize(.small)
                            }
                        }
                    } else {
                        Button("Kayıtları göster") {
                            Task { _ = await faceUnlock.unlockVault() }
                        }
                            .controlSize(.small)
                        Text("Kayıtlar şifreli. Görmek için Touch ID ya da Mac parolan gerekir; ikisini de macOS sorar, MacB görmez.")
                            .font(.system(size: 11)).foregroundStyle(MacBDesign.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            section("Model") {
                Toggle(isOn: Binding(
                    get: { faceUnlock.settings.allowsExperimentalModel },
                    set: { value in faceUnlock.update { $0.allowsExperimentalModel = value } }
                )) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Deneysel: kendi modelimi kullan").font(.system(size: 13, weight: .medium))
                        Text("MacB yüz tanıma modeli dağıtmaz. Kendi derlediğin Core ML modelini Application Support/MacB/Models içine koyarsan burada açabilirsin. Lisansı senin sorumluluğunda.")
                            .font(.system(size: 12)).foregroundStyle(MacBDesign.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Text("Şu an kullanılan: \(faceUnlock.embedderName)")
                    .font(.system(size: 11)).foregroundStyle(MacBDesign.muted)
            }

            section("Veri") {
                Text("Kamera yalnızca tarama sırasında çalışır. Kare hiçbir zaman diske yazılmaz, hiçbir yere gönderilmez. Sadece yüzün sayısal karşılığı AES-GCM ile şifrelenip saklanır; anahtar Anahtar Zinciri'nde, Touch ID ya da Mac parolası arkasında durur ve bu Mac'ten çıkmaz.")
                    .font(.system(size: 12)).foregroundStyle(MacBDesign.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if faceUnlock.isEnrolled {
                    Button("Yüz kaydını sil", role: .destructive) { showDeleteConfirmation = true }
                        .controlSize(.small)
                }
            }

            if let message = faceUnlock.errorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog("Yüz kaydı silinsin mi?", isPresented: $showDeleteConfirmation) {
            Button("Sil", role: .destructive) { faceUnlock.deleteEnrollment() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Kayıtlı yüzler ve onları koruyan anahtar kalıcı olarak silinir. Geri alınamaz.")
        }
    }

    // MARK: - Enrollment

    @ViewBuilder private var enrollment: some View {
        if faceUnlock.isEnrolling {
            VStack(alignment: .leading, spacing: 10) {
                FaceEnrollmentCameraView(frame: faceUnlock.previewFrame,
                                         faceVisible: faceUnlock.isFaceVisible,
                                         pose: faceUnlock.enrollmentPose,
                                         completed: faceUnlock.capturedPoses.count,
                                         total: FacePose.allCases.count)
                Button("Vazgeç") { faceUnlock.cancelEnrollment() }
                    .controlSize(.small)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Ad", text: $enrollmentName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button("Yüzümü kaydet") {
                    Task { await faceUnlock.beginEnrollment(name: enrollmentName) }
                }
                .controlSize(.small)
                Text("Dokuz açıdan kısa bir tarama. Kamera sadece bu sırada açılır.")
                    .font(.system(size: 11)).foregroundStyle(MacBDesign.muted)
            }
        }
    }

    @ViewBuilder private var enrolledSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(MacBDesign.accent)
            Text("Yüz kaydın hazır.").font(.system(size: 12))
            if faceUnlock.isExperimentalModel {
                Text("Deneysel model").font(.system(size: 11))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(MacBDesign.accent.opacity(0.18), in: Capsule())
            }
        }
    }

    private func relockTitle(_ seconds: TimeInterval) -> String {
        seconds < 3600 ? "\(Int(seconds / 60)) dk" : "\(Int(seconds / 3600)) sa"
    }

    /// Matches the grouping used by every other settings page.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MacBDesign.muted)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 14, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(MacBDesign.cardFill, in: RoundedRectangle(cornerRadius: MacBDesign.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: MacBDesign.Radius.card, style: .continuous)
                    .strokeBorder(MacBDesign.cardStroke))
        }
    }
}

private struct FaceEnrollmentCameraView: View {
    let frame: CGImage?
    let faceVisible: Bool
    let pose: FacePose?
    let completed: Int
    let total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanOffset: CGFloat = -72

    private var progress: CGFloat {
        total > 0 ? CGFloat(completed) / CGFloat(total) : 0
    }

    var body: some View {
        ZStack {
            cameraImage
            LinearGradient(colors: [.black.opacity(0.08), .clear, .black.opacity(0.58)],
                           startPoint: .top, endPoint: .bottom)
            faceGuide

            VStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(faceVisible ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(faceVisible ? "Yüz algılandı" : "Yüzünü çerçeveye getir")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.48), in: Capsule())

                Spacer()

                VStack(spacing: 3) {
                    Text(pose?.title ?? "Karşıya bak")
                        .font(.system(size: 16, weight: .semibold))
                    Text("\(completed) / \(total) açı tamam")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial.opacity(0.72), in: Capsule())
            }
            .padding(14)
        }
        .frame(width: 380, height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .onAppear { startScanAnimation() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Yüz kaydı. \(pose?.title ?? "Karşıya bak"). \(completed) / \(total) açı tamam.")
    }

    @ViewBuilder private var cameraImage: some View {
        if let frame {
            Image(decorative: frame, scale: 1, orientation: .up)
                .resizable()
                .scaledToFill()
                .scaleEffect(x: -1, y: 1)
        } else {
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 26, weight: .medium))
                    Text("Kamera hazırlanıyor…")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var faceGuide: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.24), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(faceVisible ? Color.green : Color.orange,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: progress)

            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < completed ? Color.green : Color.white.opacity(0.58))
                    .frame(width: 3, height: 10)
                    .offset(y: -91)
                    .rotationEffect(.degrees(Double(index) / Double(total) * 360))
            }

            Capsule()
                .fill((faceVisible ? Color.green : Color.orange).opacity(0.78))
                .frame(width: 132, height: 2)
                .shadow(color: faceVisible ? .green : .orange, radius: 7)
                .offset(y: scanOffset)
        }
        .frame(width: 190, height: 190)
    }

    private func startScanAnimation() {
        guard !reduceMotion else {
            scanOffset = 0
            return
        }
        scanOffset = -72
        withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
            scanOffset = 72
        }
    }
}
