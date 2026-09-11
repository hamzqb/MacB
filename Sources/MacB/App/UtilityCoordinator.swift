import AppKit
import Combine
import MacBCore
import UniformTypeIdentifiers

@MainActor final class UtilityCoordinator: ObservableObject {
    @Published private(set) var removalCandidates: [AppRemovalCandidate] = []
    @Published private(set) var selectedApplicationName = ""
    @Published private(set) var selectedRemovalIDs: Set<String> = []
    @Published private(set) var inspectedIdentity: AppIdentity?
    @Published private(set) var inspectedIsRunning = false
    @Published var statusMessage: String?
    @Published var isWorking = false

    private let archiveService = ArchiveService()
    private let uninstallService = AppUninstallService()

    var selectedRemovalCandidates: [AppRemovalCandidate] { removalCandidates.filter { selectedRemovalIDs.contains($0.id) } }
    var removalSize: Int64 { selectedRemovalCandidates.reduce(0) { $0 + $1.size } }

    /// The review list, grouped the way it is read: strongest evidence first.
    var removalGroups: [(confidence: AppLeftoverConfidence, candidates: [AppRemovalCandidate])] {
        AppLeftoverConfidence.allCases.reversed().compactMap { confidence in
            let members = removalCandidates.filter { $0.confidence == confidence }
            return members.isEmpty ? nil : (confidence, members)
        }
    }

    /// Items found under /Library. They are shown so the user knows they exist,
    /// and never ticked, because MacB does not ask for administrator rights.
    var administratorOnlyCandidates: [AppRemovalCandidate] { removalCandidates.filter(\.requiresAdministrator) }
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
        inspectApplication(at: application)
    }

    func inspectApplication(at application: URL) {
        isWorking = true; statusMessage = nil
        Task {
            do {
                let service = uninstallService
                let report = try await Task.detached(priority: .utility) { try service.report(for: application) }.value
                removalCandidates = report.candidates
                // Only the evidence that names the application is ticked. A name
                // match is shown, explained and left for the user to decide.
                selectedRemovalIDs = Set(report.candidates
                    .filter { $0.confidence.isSelectedByDefault && !$0.requiresAdministrator }
                    .map(\.id))
                inspectedIdentity = report.identity
                inspectedIsRunning = report.runningProcessCount > 0
                selectedApplicationName = report.identity.name
                statusMessage = report.candidates.isEmpty ? "Bu uygulama için kaldırılacak öğe bulunamadı." : nil
            } catch {
                statusMessage = error.localizedDescription
                clearInspection()
            }
            isWorking = false
        }
    }

    /// Quits the application so its own bundle can be recycled.
    func quitInspectedApplication() {
        guard let identity = inspectedIdentity else { return }
        isWorking = true
        Task {
            let stopped = await uninstallService.quitApplication(identity)
            inspectedIsRunning = !stopped
            statusMessage = stopped ? nil : "Uygulama kapanmadı. Kendi penceresinden kapatman gerekebilir."
            isWorking = false
        }
    }

    private func clearInspection() {
        removalCandidates = []
        selectedRemovalIDs = []
        selectedApplicationName = ""
        inspectedIdentity = nil
        inspectedIsRunning = false
    }

    func removeInspectedApplication() {
        let candidates = selectedRemovalCandidates
        guard !candidates.isEmpty else { return }
        let identity = inspectedIdentity
        let count = candidates.count
        clearInspection()
        run { [uninstallService] in
            // The bundle cannot be recycled while it is running, so the quit that
            // the review sheet offered is repeated here for the case where the
            // application came back to life in between.
            if let identity, uninstallService.isRunning(identity) {
                guard await uninstallService.quitApplication(identity) else {
                    throw AppUninstallError.stillRunning
                }
            }
            try await uninstallService.moveToTrash(candidates)
            return "\(count) öğe Çöp Sepeti’ne taşındı. Geri almak için Çöp Sepeti'nden çıkar."
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
