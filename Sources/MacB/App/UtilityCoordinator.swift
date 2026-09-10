import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor final class UtilityCoordinator: ObservableObject {
    @Published private(set) var removalCandidates: [AppRemovalCandidate] = []
    @Published private(set) var selectedApplicationName = ""
    @Published private(set) var selectedRemovalIDs: Set<String> = []
    @Published var statusMessage: String?
    @Published var isWorking = false

    private let archiveService = ArchiveService()
    private let uninstallService = AppUninstallService()

    var selectedRemovalCandidates: [AppRemovalCandidate] { removalCandidates.filter { selectedRemovalIDs.contains($0.id) } }
    var removalSize: Int64 { selectedRemovalCandidates.reduce(0) { $0 + $1.size } }
    var macWhisperInstalled: Bool { macWhisperURL != nil }

    func createArchive() {
        let panel = NSOpenPanel()
        panel.title = "Sıkıştırılacak dosyaları seç"
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let inputs = panel.urls
        let save = NSSavePanel()
        save.title = "ZIP arşivini kaydet"
        save.nameFieldStringValue = inputs.count == 1 ? inputs[0].deletingPathExtension().lastPathComponent + ".zip" : "Arşiv.zip"
        save.allowedContentTypes = [.zip]
        guard save.runModal() == .OK, let destination = save.url else { return }
        run { [archiveService] in
            try await archiveService.createZIP(from: inputs, at: destination, replaceExisting: true)
            return "\(destination.lastPathComponent) oluşturuldu."
        }
    }

    func extractArchive() {
        let panel = NSOpenPanel()
        panel.title = "Açılacak ZIP arşivini seç"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let archive = panel.url else { return }
        let folder = NSOpenPanel()
        folder.title = "Çıkarma klasörünü seç"
        folder.canChooseFiles = false; folder.canChooseDirectories = true; folder.canCreateDirectories = true
        guard folder.runModal() == .OK, let destination = folder.url else { return }
        run { [archiveService] in
            try await archiveService.extractZIP(archive, to: destination)
            return "Arşiv \(destination.lastPathComponent) klasörüne çıkarıldı."
        }
    }

    func inspectApplication() {
        let panel = NSOpenPanel()
        panel.title = "Kaldırılacak uygulamayı seç"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.applicationBundle]
        guard panel.runModal() == .OK, let application = panel.url else { return }
        isWorking = true; statusMessage = nil
        Task {
            do {
                let service = uninstallService
                let found = try await Task.detached(priority: .utility) { try service.candidates(for: application) }.value
                removalCandidates = found
                selectedRemovalIDs = Set(found.filter { $0.kind != .support }.map(\.id))
                selectedApplicationName = application.deletingPathExtension().lastPathComponent
                statusMessage = found.isEmpty ? "Bu uygulama için kaldırılacak öğe bulunamadı." : nil
            } catch { statusMessage = error.localizedDescription; removalCandidates = []; selectedRemovalIDs = []; selectedApplicationName = "" }
            isWorking = false
        }
    }

    func removeInspectedApplication() {
        let candidates = selectedRemovalCandidates
        guard !candidates.isEmpty else { return }
        removalCandidates = []; selectedRemovalIDs = []; selectedApplicationName = ""
        run { [uninstallService] in
            try await uninstallService.moveToTrash(candidates)
            return "Uygulama ve seçilen kalıntılar Çöp Sepeti’ne taşındı."
        }
    }

    func isSelected(_ candidate: AppRemovalCandidate) -> Bool { selectedRemovalIDs.contains(candidate.id) }
    func toggleRemoval(_ candidate: AppRemovalCandidate) {
        if selectedRemovalIDs.contains(candidate.id) { selectedRemovalIDs.remove(candidate.id) }
        else { selectedRemovalIDs.insert(candidate.id) }
    }

    func sendAudioToMacWhisper() {
        guard let app = macWhisperURL else { statusMessage = "MacWhisper bu Mac’te bulunamadı."; return }
        let panel = NSOpenPanel()
        panel.title = "MacWhisper’a gönderilecek sesi seç"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie]
        guard panel.runModal() == .OK else { return }
        NSWorkspace.shared.open(panel.urls, withApplicationAt: app, configuration: .init()) { [weak self] _, error in
            Task { @MainActor in self?.statusMessage = error?.localizedDescription ?? "Dosya MacWhisper’a gönderildi." }
        }
    }

    private var macWhisperURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.goodsnooze.MacWhisper")
            ?? ["/Applications/MacWhisper.app", NSHomeDirectory() + "/Applications/MacWhisper.app"]
                .map(URL.init(fileURLWithPath:)).first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func run(_ operation: @escaping () async throws -> String) {
        guard !isWorking else { return }
        isWorking = true; statusMessage = nil
        Task {
            do { statusMessage = try await operation() }
            catch { statusMessage = error.localizedDescription }
            isWorking = false
        }
    }
}
