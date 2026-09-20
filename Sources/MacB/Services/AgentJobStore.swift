import Combine
import Foundation
import MacBCore

/// The jobs MacB was given to do while nobody was watching, and what they
/// found.
///
/// Kept on this Mac, at 0600, and never longer than it takes to read the
/// answer: a delivered job falls off the end once there are more than a
/// handful. What a person asks their assistant to look into is not something
/// that should accumulate into a diary.
@MainActor final class AgentJobStore: ObservableObject {
    @Published private(set) var jobs: [AgentJob] = []

    private let url: URL
    private var isUnreadable = false

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacB", isDirectory: true)
            .appendingPathComponent("jobs.json")
        load()
        // A job that was running when MacB was quit did not survive the quit.
        // Saying so is better than a card that claims to still be working.
        for index in jobs.indices where jobs[index].state == .running || jobs[index].state == .queued {
            jobs[index].state = .failed("MacB kapandığı için yarıda kaldı.")
            jobs[index].finishedAt = Date()
        }
        save()
    }

    var running: [AgentJob] { jobs.filter { !$0.isFinished } }
    /// Finished and not yet seen: what is put in front of somebody who has
    /// just come back to their Mac.
    var waiting: [AgentJob] { jobs.filter(\.isWaitingForUser) }
    var hasWork: Bool { !running.isEmpty }

    @discardableResult
    func add(request: String) -> AgentJob? {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let job = AgentJob(request: trimmed)
        jobs.insert(job, at: 0)
        trim()
        save()
        return job
    }

    func update(_ id: UUID, _ change: (inout AgentJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
        save()
    }

    func markDelivered(_ id: UUID) {
        update(id) { $0.isDelivered = true }
    }

    func cancel(_ id: UUID) {
        update(id) { job in
            guard !job.isFinished else { return }
            job.state = .cancelled
            job.finishedAt = Date()
        }
    }

    func remove(_ id: UUID) {
        jobs.removeAll { $0.id == id }
        save()
    }

    /// Everything seen and done with. The user's own "tamam, kapat".
    func clearDelivered() {
        jobs.removeAll { $0.isDelivered && $0.isFinished }
        save()
    }

    // MARK: - Storage

    private func trim() {
        guard jobs.count > AgentPolicy.maximumJobs else { return }
        // Unfinished and unseen work is kept whatever its age; what falls off
        // the end is what has already been read.
        var kept = jobs.filter { !$0.isFinished || !$0.isDelivered }
        let spare = AgentPolicy.maximumJobs - kept.count
        if spare > 0 {
            kept += jobs.filter { $0.isFinished && $0.isDelivered }.prefix(spare)
        }
        jobs = jobs.filter { job in kept.contains(where: { $0.id == job.id }) }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([AgentJob].self, from: data) else {
            isUnreadable = true
            return
        }
        jobs = decoded
    }

    private func save() {
        guard !isUnreadable else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
