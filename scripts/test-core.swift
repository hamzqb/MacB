import Foundation
import CoreGraphics

// XCTest is shipped with full Xcode, but not all Command Line Tools installations.
// Keep this runner aligned with Tests/MacBCoreTests so local verification needs no downloads.
private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw TestFailure(description: message) }
}

private func withShelfFixture(_ body: (URL, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacBTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("example.txt")
    try Data("fixture".utf8).write(to: source)
    try body(directory, source)
}

@main
struct CoreTestRunner {
    static func main() {
        let frame = CGRect(x: 20, y: 40, width: 800, height: 600)
        func candidate(_ id: UInt32, pid: Int32 = 10, title: String = "Document", bounds: CGRect? = nil) -> WindowDescriptor {
            WindowDescriptor(id: id, pid: pid, title: title, frame: bounds ?? frame)
        }
        let tests: [(String, () throws -> Void)] = [
            ("VersionNumber: compares release versions numerically", {
                try expect(VersionNumber.isNewer("v0.2.0", than: "0.1.9"), "New minor release was missed")
                try expect(VersionNumber.isNewer("1.10.0", than: "1.9.9"), "Numeric components were compared as text")
                try expect(!VersionNumber.isNewer("1.2", than: "1.2.0"), "Equivalent versions differed")
                try expect(!VersionNumber.isNewer("1.1.9", than: "1.2.0"), "Older release was accepted")
            }),
            ("WindowVisibility: removes an inactive generic helper beside a named primary window", {
                let helper = WindowVisibilityCandidate(title: "Window", bundleIdentifier: "com.openai.codex", isMain: false, isFocused: false)
                let primary = WindowVisibilityCandidate(title: "ChatGPT", bundleIdentifier: "com.openai.codex", isMain: true, isFocused: true)
                try expect(!WindowVisibilityPolicy.shouldKeep(helper, among: [helper, primary]), "Generic helper remained visible")
                try expect(WindowVisibilityPolicy.shouldKeep(primary, among: [helper, primary]), "Primary window was removed")
            }),
            ("WindowVisibility: preserves focused or standalone windows named Window", {
                let focused = WindowVisibilityCandidate(title: "Window", isMain: true, isFocused: true)
                let standalone = WindowVisibilityCandidate(title: "Pencere", isMain: false, isFocused: false)
                try expect(WindowVisibilityPolicy.shouldKeep(focused, among: [focused]), "Focused generic-title document was removed")
                try expect(WindowVisibilityPolicy.shouldKeep(standalone, among: [standalone]), "Standalone generic-title window was removed")
            }),
            ("WindowVisibility: preserves generic document titles in unknown applications", {
                let document = WindowVisibilityCandidate(title: "Window", bundleIdentifier: "com.example.editor", isMain: false, isFocused: false)
                let primary = WindowVisibilityCandidate(title: "Project", bundleIdentifier: "com.example.editor", isMain: true, isFocused: true)
                try expect(WindowVisibilityPolicy.shouldKeep(document, among: [document, primary]), "An unknown app's real document was removed")
            }),
            ("WindowVisibility: removes Claude's inactive generic helper", {
                let helper = WindowVisibilityCandidate(title: "Window", bundleIdentifier: "com.anthropic.claudefordesktop", isMain: false, isFocused: false)
                let primary = WindowVisibilityCandidate(title: "Claude", bundleIdentifier: "com.anthropic.claudefordesktop", isMain: true, isFocused: true)
                try expect(!WindowVisibilityPolicy.shouldKeep(helper, among: [helper, primary]), "Claude helper remained visible")
            }),
            ("WindowLayout: halves and corners tile the visible screen", {
                let area = CGRect(x: 100, y: 40, width: 1200, height: 800)
                let current = CGRect(x: 200, y: 100, width: 640, height: 480)
                guard let left = WindowLayout.frame(for: .leftHalf, in: area, current: current),
                      let right = WindowLayout.frame(for: .rightHalf, in: area, current: current),
                      let topLeft = WindowLayout.frame(for: .topLeft, in: area, current: current),
                      let bottomRight = WindowLayout.frame(for: .bottomRight, in: area, current: current) else {
                    throw TestFailure(description: "Layout unexpectedly returned nil")
                }
                try expect(left.union(right) == area && left.intersection(right).width == 0, "Halves do not tile the screen")
                try expect(topLeft == CGRect(x: 100, y: 40, width: 600, height: 400), "Top-left frame is wrong")
                try expect(bottomRight == CGRect(x: 700, y: 440, width: 600, height: 400), "Bottom-right frame is wrong")
            }),
            ("WindowLayout: center clamps size and display move preserves proportions", {
                let area = CGRect(x: 100, y: 40, width: 1200, height: 800)
                let centered = WindowLayout.frame(for: .center, in: area,
                    current: CGRect(x: 0, y: 0, width: 2000, height: 1000))
                try expect(centered == area, "Oversized centered window was not clamped")
                let moved = WindowLayout.frameOnNextDisplay(
                    current: CGRect(x: 250, y: 200, width: 500, height: 400),
                    from: CGRect(x: 0, y: 0, width: 1000, height: 800),
                    to: CGRect(x: 1000, y: 0, width: 2000, height: 1200))
                try expect(moved == CGRect(x: 1500, y: 300, width: 1000, height: 600),
                           "Moving displays did not preserve relative size and position")
            }),
            ("BrowserMediaProbe: accepts only real playing media and cleans titles", {
                let playing = BrowserMediaProbe.decode(#"{"title":"Example — YouTube","artist":"Artist","isPlaying":true,"currentTime":12.5,"duration":90}"#)
                try expect(playing?.title == "Example", "Browser title suffix was not cleaned")
                try expect(playing?.artist == "Artist" && playing?.currentTime == 12.5, "Playing metadata was not decoded")
                try expect(BrowserMediaProbe.decode(#"{"title":"Paused","isPlaying":false}"#) == nil, "Paused media was accepted")
                try expect(BrowserMediaProbe.decode(#"{"title":"","isPlaying":true}"#) == nil, "Untitled media was accepted")
            }),
            ("WindowMatcher: requires same process and geometry", {
                try expect(WindowMatcher.uniqueMatch(pid: 10, title: "Document", frame: frame,
                    candidates: [candidate(1, pid: 20), candidate(2)]) == 2, "Wrong process matched")
                try expect(WindowMatcher.uniqueMatch(pid: 10, title: "Document", frame: frame,
                    candidates: [candidate(1, bounds: frame.offsetBy(dx: 50, dy: 0))]) == nil, "Different geometry matched")
            }),
            ("WindowMatcher: equal titles use geometry; ambiguity returns nil", {
                try expect(WindowMatcher.uniqueMatch(pid: 10, title: "Document", frame: frame,
                    candidates: [candidate(1), candidate(2, bounds: frame.offsetBy(dx: 100, dy: 0))]) == 1,
                    "Equal titles were not resolved by geometry")
                try expect(WindowMatcher.uniqueMatch(pid: 10, title: "Document", frame: frame,
                    candidates: [candidate(1), candidate(2)]) == nil, "Ambiguous windows matched")
            }),
            ("WindowMatcher: missing title still requires unambiguous geometry", {
                try expect(WindowMatcher.uniqueMatch(pid: 10, title: "Document", frame: frame,
                    candidates: [candidate(1, title: "")]) == 1, "Empty title prevented unique geometry match")
                try expect(WindowMatcher.uniqueMatch(pid: 10, title: "", frame: frame,
                    candidates: [candidate(1), candidate(2)]) == nil, "Empty title accepted ambiguous geometry")
                try expect(WindowMatcher.uniqueMatch(pid: 10, title: "Document", frame: .zero,
                    candidates: [candidate(1)]) == nil, "Zero-sized window matched")
            }),
            ("WindowMatcher: browser title suffix can differ when geometry is unique", {
                try expect(WindowMatcher.uniqueMatch(pid: 10, title: "Private — Chrome", frame: frame,
                    candidates: [candidate(1, title: "Private")]) == 1, "Unique geometry was rejected")
            }),
            ("PanelState: 180ms hover opens glance without resetting on repeated entry", {
                var state = PanelState()
                state.pointerEntered(at: 0)
                state.pointerEntered(at: 0.1)
                state.tick(at: 0.179)
                try expect(state.phase == .collapsed, "Hover opened before 180ms")
                state.tick(at: 0.18)
                try expect(state.phase == .glance && state.content == .music, "Hover did not open music glance")
                state.tick(at: 10)
                try expect(state.phase == .glance, "Hover unexpectedly expanded")
            }),
            ("PanelState: rapid exit cancels hover and reentry starts fresh delay", {
                var state = PanelState()
                state.pointerEntered(at: 0)
                state.pointerExited(at: 0.1)
                state.tick(at: 0.2)
                try expect(state.phase == .collapsed, "Cancelled hover still opened")
                state.pointerEntered(at: 0.25)
                state.tick(at: 0.42)
                try expect(state.phase == .collapsed, "Reentry reused old hover deadline")
                state.tick(at: 0.44)
                try expect(state.phase == .glance, "Reentry failed to open glance")
                state.pointerExited(at: 1)
                state.tick(at: 1.29)
                try expect(state.phase == .glance, "Glance closed before exit grace elapsed")
                state.tick(at: 1.31)
                try expect(state.phase == .collapsed, "Glance did not close after exit grace")
            }),
            ("PanelState: click expands immediately and hover cannot downgrade", {
                var state = PanelState()
                state.pointerEntered(at: 0)
                state.open()
                state.tick(at: 1)
                try expect(state.phase == .expanded && state.hoverDeadline == nil, "Click failed to cancel pending hover")
                state.select(.files)
                state.glance()
                try expect(state.phase == .expanded && state.content == .files, "Glance downgraded selected expanded content")
            }),
            ("PanelState: drag opens without forcing files and explicit close clears all interaction", {
                var state = PanelState()
                state.pointerEntered(at: 0)
                state.setDragging(true)
                try expect(state.phase == .expanded && state.content == .music, "Drag forced another section instead of preserving content")
                try expect(state.hoverDeadline == nil, "Drag retained hover deadline")
                state.setKeyboardFocus(true)
                state.pointerExited(at: 0.1)
                state.tick(at: 10)
                try expect(state.phase == .expanded, "Active interaction closed expanded panel")
                state.close()
                try expect(state == PanelState(), "Explicit close left stale phase/content/deadlines")
                state.tick(at: 20)
                try expect(state.phase == .collapsed, "Old deadline reopened closed panel")
            }),
            ("MorphTiming: finite small overshoot and exact endpoints", {
                try expect(MorphTiming.progress(-1) == 0 && MorphTiming.progress(0) == 0, "Start endpoint/clamp is not exact")
                try expect(MorphTiming.progress(1) == 1 && MorphTiming.progress(2) == 1, "End endpoint/clamp is not exact")
                var hasOvershoot = false
                for sample in 0...1000 {
                    let progress = MorphTiming.progress(Double(sample) / 1000)
                    try expect(progress.isFinite && progress >= 0 && progress <= 1.1, "Spring escaped finite visual bounds")
                    hasOvershoot = hasOvershoot || progress > 1
                }
                try expect(hasOvershoot, "Spring has no overshoot")
            }),
            ("MorphTiming: interrupted reversal starts at current frame and settles exactly", {
                for fraction in [0.05, 0.2, 0.5, 0.9] {
                    let currentWidth = 220 + (440 - 220) * MorphTiming.progress(fraction)
                    let rebasedStart = currentWidth + (220 - currentWidth) * MorphTiming.progress(0)
                    let rebasedEnd = currentWidth + (220 - currentWidth) * MorphTiming.progress(1)
                    try expect(abs(rebasedStart - currentWidth) < 0.000001, "Interrupted morph jumped at rebase")
                    try expect(abs(rebasedEnd - 220) < 0.000001, "Interrupted morph missed target frame")
                }
            }),
            ("PanelState: pointer crossing cancels delayed close", {
                var state = PanelState()
                state.open()
                state.pointerExited(at: 0)
                state.tick(at: 0.2)
                try expect(state.isOpen, "Panel closed before grace period ended")
                state.pointerEntered()
                state.tick(at: 1)
                try expect(state.isOpen, "Panel closed after pointer reentered")
            }),
            ("PanelState: drag and focus prevent closing until released", {
                var state = PanelState()
                state.setDragging(true)
                state.pointerExited(at: 0)
                state.tick(at: 1)
                try expect(state.isOpen, "Panel closed while dragging")
                state.setDragging(false)
                state.setKeyboardFocus(true)
                state.pointerExited(at: 1)
                state.tick(at: 2)
                try expect(state.isOpen, "Panel closed while keyboard focused")
                state.setKeyboardFocus(false)
                state.tick(at: 3)
                try expect(!state.isOpen, "Panel remained open after interaction ended")
            }),
            ("PanelState: Escape resets interaction", {
                var state = PanelState()
                state.setDragging(true)
                state.close()
                try expect(state == PanelState(), "Explicit close left stale interaction state")
            }),
            ("PanelState: files content closes to default music state", {
                var state = PanelState()
                state.select(.files)
                try expect(state.phase == .expanded && state.content == .files, "Files section did not open")
                state.close()
                try expect(state == PanelState(), "Files section did not close to default state")
            }),
            ("WindowSelection: cycle and reverse wrap", {
                var selection = WindowSelection()
                selection.replace(with: ["a", "b", "c"])
                selection.advance(backwards: true)
                try expect(selection.selectedID == "c", "Reverse selection did not wrap")
                selection.advance()
                try expect(selection.selectedID == "a", "Forward selection did not wrap")
            }),
            ("WindowSelection: live refresh and closed-window fallback", {
                var selection = WindowSelection()
                selection.replace(with: ["a", "b", "c"])
                selection.select("b")
                selection.replace(with: ["c", "b", "a"])
                try expect(selection.selectedID == "b", "Reorder changed selected identity")
                selection.replace(with: ["c", "a"])
                try expect(selection.selectedID == "a", "Closed selection did not fall back by position")
                selection.replace(with: [])
                try expect(selection.selectedID == nil, "Empty window set retained selection")
                selection.advance()
                try expect(selection.selectedID == nil, "Cycling empty window set created selection")
            }),
            ("ShelfPersistence: restart preserves references and deduplicates", {
                try withShelfFixture { directory, source in
                    let location = directory.appendingPathComponent("shelf.json")
                    let first = try ShelfPersistence(fileURL: location)
                    try first.add(urls: [source, source])
                    let restored = try ShelfPersistence(fileURL: location)
                    try expect(restored.records.count == 1, "Duplicate source added")
                    try expect(restored.records.first?.id == first.records.first?.id, "Restart changed record identity")
                    try expect(restored.resolve().first?.isAvailable == true, "Existing reference unavailable after restart")
                    try expect(try Data(contentsOf: source) == Data("fixture".utf8), "Source content changed")
                }
            }),
            ("ShelfPersistence: missing file remains in shelf", {
                try withShelfFixture { directory, source in
                    let shelf = try ShelfPersistence(fileURL: directory.appendingPathComponent("shelf.json"))
                    try shelf.add(urls: [source])
                    try FileManager.default.removeItem(at: source)
                    let restored = try ShelfPersistence(fileURL: shelf.fileURL)
                    try expect(restored.records.count == 1, "Missing source removed shelf entry")
                    try expect(restored.resolve().first?.isAvailable == false, "Missing source marked available")
                }
            }),
            ("ShelfPersistence: removing reference never deletes source", {
                try withShelfFixture { directory, source in
                    let shelf = try ShelfPersistence(fileURL: directory.appendingPathComponent("shelf.json"))
                    try shelf.add(urls: [source])
                    guard let id = shelf.records.first?.id else { throw TestFailure(description: "Source not added") }
                    try shelf.remove(id: id)
                    try expect(shelf.records.isEmpty, "Reference not removed")
                    try expect(FileManager.default.fileExists(atPath: source.path), "Source deleted")
                    try expect(try ShelfPersistence(fileURL: shelf.fileURL).records.isEmpty, "Removal not persisted")
                }
            }),
            ("ShelfPersistence: corrupt storage is not silently discarded", {
                try withShelfFixture { directory, _ in
                    let location = directory.appendingPathComponent("shelf.json")
                    let invalid = Data("invalid".utf8)
                    try invalid.write(to: location)
                    var rejected = false
                    do { _ = try ShelfPersistence(fileURL: location) } catch { rejected = true }
                    try expect(rejected, "Corrupt storage accepted")
                    try expect(try Data(contentsOf: location) == invalid, "Corrupt storage overwritten")
                }
            }),
            ("ShelfPersistence: web URLs are not added", {
                try withShelfFixture { directory, _ in
                    let shelf = try ShelfPersistence(fileURL: directory.appendingPathComponent("shelf.json"))
                    guard let url = URL(string: "https://example.com/image.png") else {
                        throw TestFailure(description: "Invalid test fixture URL")
                    }
                    try shelf.add(urls: [url])
                    try expect(shelf.records.isEmpty, "Remote URL added to local shelf")
                }
            })
        ]
        var failures = 0
        for (name, test) in tests {
            do { try test(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("\(tests.count - failures)/\(tests.count) core scenarios passed.")
        if failures > 0 { exit(1) }
    }
}
