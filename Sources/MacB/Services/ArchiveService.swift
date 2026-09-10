import Foundation

enum ArchiveServiceError: LocalizedError {
    case noInput, invalidInput, unsupportedArchive, unsafeEntry(String), archiveTooLarge, destinationConflict(String), timedOut, commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInput: return "Sıkıştırılacak dosya seçilmedi."
        case .invalidInput: return "Seçilen dosyalardan birine erişilemiyor."
        case .unsupportedArchive: return "Şimdilik yalnızca ZIP arşivleri açılabilir."
        case .unsafeEntry(let name): return "Arşiv güvenli olmayan bir yol içeriyor: \(name)"
        case .archiveTooLarge: return "Arşivin çıkarılmış boyutu güvenli sınırı aşıyor."
        case .destinationConflict(let name): return "Hedefte aynı adlı bir öğe zaten var: \(name)"
        case .timedOut: return "Arşiv işlemi zaman aşımına uğradı ve durduruldu."
        case .commandFailed(let detail): return detail.isEmpty ? "Arşiv işlemi tamamlanamadı." : detail
        }
    }
}

/// ZIP creation/extraction backed by macOS system tools. No shell is involved.
final class ArchiveService {
    func createZIP(from inputURLs: [URL], at destination: URL, replaceExisting: Bool = false) async throws {
        let inputs = inputURLs.map(\.standardizedFileURL)
        guard !inputs.isEmpty else { throw ArchiveServiceError.noInput }
        guard inputs.allSatisfy({ $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }), destination.isFileURL else {
            throw ArchiveServiceError.invalidInput
        }
        let destinationPath = destination.standardizedFileURL.path
        guard !inputs.contains(where: { input in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory)
                && isDirectory.boolValue && destinationPath.hasPrefix(input.path + "/")
        }) else { throw ArchiveServiceError.invalidInput }
        let existed = FileManager.default.fileExists(atPath: destination.path)
        if existed && !replaceExisting { throw CocoaError(.fileWriteFileExists) }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".MacB-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: temporary) }
        if inputs.count == 1 {
            try await run("/usr/bin/zip", ["-q", "-r", temporary.path, "--", inputs[0].lastPathComponent],
                          currentDirectory: inputs[0].deletingLastPathComponent())
        } else {
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("MacB-Archive-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: staging) }
            var usedNames = Set<String>()
            for input in inputs {
                var name = input.lastPathComponent
                var suffix = 2
                while usedNames.contains(name) {
                    name = "\(input.deletingPathExtension().lastPathComponent) \(suffix)"
                        + (input.pathExtension.isEmpty ? "" : ".\(input.pathExtension)")
                    suffix += 1
                }
                usedNames.insert(name)
                try FileManager.default.copyItem(at: input, to: staging.appendingPathComponent(name))
            }
            try await run("/usr/bin/zip", ["-q", "-r", temporary.path, "--", "."], currentDirectory: staging)
        }
        _ = try await output("/usr/bin/zipinfo", ["-t", temporary.path])
        if existed { _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: destination) }
    }

    func extractZIP(_ archive: URL, to destination: URL, maximumExpandedSize: Int64 = 20 * 1_024 * 1_024 * 1_024) async throws {
        guard archive.pathExtension.lowercased() == "zip" else { throw ArchiveServiceError.unsupportedArchive }
        guard FileManager.default.fileExists(atPath: archive.path) else { throw ArchiveServiceError.invalidInput }
        let listing = try await output("/usr/bin/zipinfo", ["-1", archive.path])
        let destinationRoot = destination.standardizedFileURL.path + "/"
        let names = listing.split(separator: "\n", omittingEmptySubsequences: true)
        guard names.count <= 10_000 else { throw ArchiveServiceError.archiveTooLarge }
        var foldedNames = Set<String>()
        for rawName in names {
            let name = String(rawName)
            let components = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
            if name.hasPrefix("/") || name.contains("\0") || components.contains("..") {
                throw ArchiveServiceError.unsafeEntry(name)
            }
            let outputURL = destination.appendingPathComponent(name).standardizedFileURL
            guard outputURL.path.hasPrefix(destinationRoot) else { throw ArchiveServiceError.unsafeEntry(name) }
            guard foldedNames.insert(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted else {
                throw ArchiveServiceError.destinationConflict(name)
            }
            if FileManager.default.fileExists(atPath: outputURL.path) {
                throw ArchiveServiceError.destinationConflict(name)
            }
        }
        let totals = try await output("/usr/bin/zipinfo", ["-t", archive.path])
        guard let match = totals.range(of: #"[0-9]+ bytes uncompressed"#, options: .regularExpression),
              let bytes = Int64(totals[match].split(separator: " ")[0]) else {
            throw ArchiveServiceError.commandFailed("Arşivin çıkarılmış boyutu doğrulanamadı.")
        }
        if bytes > maximumExpandedSize { throw ArchiveServiceError.archiveTooLarge }
        let verbose = try await output("/usr/bin/zipinfo", ["-l", archive.path])
        for line in verbose.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let first = trimmed.first, "lbcp s".filter({ $0 != " " }).contains(first) { throw ArchiveServiceError.unsafeEntry(String(line)) }
        }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("MacB-Extract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        try await run("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
        try validateExtractedTree(at: staging)
        let topLevelItems = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
        for item in topLevelItems {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) {
                throw ArchiveServiceError.destinationConflict(item.lastPathComponent)
            }
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var moved: [(source: URL, target: URL)] = []
        do {
            for item in topLevelItems {
                let target = destination.appendingPathComponent(item.lastPathComponent)
                try FileManager.default.moveItem(at: item, to: target)
                moved.append((item, target))
            }
        } catch {
            for pair in moved.reversed() { try? FileManager.default.moveItem(at: pair.target, to: pair.source) }
            throw error
        }
    }

    private func validateExtractedTree(at staging: URL) throws {
        if let enumerator = FileManager.default.enumerator(at: staging, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]) {
            for case let item as URL in enumerator {
                let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else {
                    throw ArchiveServiceError.unsafeEntry(item.lastPathComponent)
                }
            }
        }
    }

    private func run(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) async throws {
        _ = try await output(executable, arguments, currentDirectory: currentDirectory)
    }

    private func output(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) async throws -> String {
        let holder = RunningProcess()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process(), pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.currentDirectoryURL = currentDirectory
                process.standardOutput = pipe; process.standardError = pipe
                do {
                    try process.run()
                    holder.set(process)
                    let timeout = DispatchWorkItem { holder.terminate(markTimedOut: true) }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 120, execute: timeout)
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    timeout.cancel()
                    let timedOut = holder.finish()
                    let text = String(data: data, encoding: .utf8) ?? ""
                    if timedOut { continuation.resume(throwing: ArchiveServiceError.timedOut) }
                    else if process.terminationStatus == 0 { continuation.resume(returning: text) }
                    else { continuation.resume(throwing: ArchiveServiceError.commandFailed(text.trimmingCharacters(in: .whitespacesAndNewlines))) }
                } catch { continuation.resume(throwing: error) }
            }
            }
        } onCancel: {
            holder.terminate(markTimedOut: false)
        }
    }
}

private final class RunningProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var timedOut = false

    func set(_ process: Process) {
        lock.lock(); self.process = process; lock.unlock()
    }

    func terminate(markTimedOut: Bool) {
        lock.lock()
        if markTimedOut { timedOut = true }
        let process = process
        lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }

    func finish() -> Bool {
        lock.lock(); defer { lock.unlock() }
        process = nil
        return timedOut
    }
}
