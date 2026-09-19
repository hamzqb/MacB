import AppKit
import MacBCore

/// Command-line probes for features that otherwise need a gesture to reach.
@MainActor enum Probe {
    static func run(_ arguments: [String]) -> (@MainActor () async -> Void)? {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        func values(after flag: String) -> [String] {
            guard let index = arguments.firstIndex(of: flag) else { return [] }
            return Array(arguments[(index + 1)...].prefix { !$0.hasPrefix("--") })
        }

        if let text = value(after: "--translate") {
            let target = value(after: "--to") ?? "tr"
            return {
                switch await OfflineTranslator().translate(text, preferredTarget: target) {
                case .success(let result): print("\(result.source) → \(result.target): \(result.text)")
                case .failure(let failure): print("error: \(failure.message)")
                }
            }
        }
        if let path = value(after: "--convert") {
            return {
                let url = URL(fileURLWithPath: path)
                do {
                    if ShelfConversion.canConvertToJPEG(url) {
                        print("jpeg: \(try await ShelfConverter.jpegCopy(of: url).path)")
                    }
                    print("reduced: \(try await ShelfConverter.reducedCopy(of: url).path)")
                } catch { print("error: \(error.localizedDescription)") }
            }
        }
        let pdfs = values(after: "--merge")
        if !pdfs.isEmpty {
            return {
                do { print("merged: \(try await ShelfConverter.merge(pdfs.map { URL(fileURLWithPath: $0) }).path)") }
                catch { print("error: \(error.localizedDescription)") }
            }
        }
        if arguments.contains("--keep-awake-probe") {
            return {
                let service = KeepAwakeService.shared
                print("started: \(service.start(minutes: 1))  remaining: \(service.remainingText)")
                print(shell("/usr/bin/pmset", ["-g", "assertions"]).split(separator: "\n")
                    .filter { $0.contains("MacB") }.joined(separator: "\n"))
                service.stop()
                let after = shell("/usr/bin/pmset", ["-g", "assertions"]).contains("MacB: Uyanık tut")
                print("released: \(!after)")
            }
        }
        if arguments.contains("--selection-probe") {
            return {
                let delay = Double(value(after: "--selection-probe") ?? "") ?? 0
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                switch await SelectedTextService().read() {
                case .success(let selection):
                    print("app: \(selection.appName)  chars: \(selection.text.count)  via: \(selection.element == nil ? "⌘C" : "AX")  replaceable: \(selection.canReplace)")
                    if let replacement = value(after: "--replace-with") {
                        print("replaced: \(SelectedTextService().replace(selection, with: replacement))")
                    }
                case .failure(let failure): print("error: \(failure.message)")
                }
            }
        }
        if arguments.contains("--arrangement-probe") {
            return {
                let service = WindowArrangementService(directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("macb-arrangement-probe-\(UUID().uuidString)"))
                print("displays: \(WindowArrangementService.currentSignature().summary)")
                guard let saved = service.saveCurrent(named: "probe") else {
                    print("error: \(service.lastMessage ?? "—")"); return
                }
                let apps = Set(saved.windows.map(\.bundleIdentifier)).count
                print("windows: \(saved.windows.count) in \(apps) apps")
                if arguments.contains("--apply") {
                    print("moved back in place: \(service.apply(saved))  \(service.lastMessage ?? "")")
                }
            }
        }
        return nil
    }

    private static func shell(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
