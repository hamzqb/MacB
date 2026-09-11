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
            ("WindowVisibility: removes generic helpers in every application", {
                let document = WindowVisibilityCandidate(title: "Window", bundleIdentifier: "com.example.editor", isMain: false, isFocused: false)
                let primary = WindowVisibilityCandidate(title: "Project", bundleIdentifier: "com.example.editor", isMain: true, isFocused: true)
                try expect(!WindowVisibilityPolicy.shouldKeep(document, among: [document, primary]), "Generic helper remained visible")
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
            ("WindowDesktop: onscreen windows stay on the current desktop", {
                let location = WindowDesktopClassifier.classify(
                    isOnScreen: true, isMinimized: false, isApplicationHidden: false)
                try expect(location == .current, "An onscreen window left the current desktop section")
            }),
            ("WindowDesktop: offscreen windows are separated from the current desktop", {
                let location = WindowDesktopClassifier.classify(
                    isOnScreen: false, isMinimized: false, isApplicationHidden: false)
                try expect(location == .other, "An offscreen Space window was not separated")
            }),
            ("WindowDesktop: uncertain windows are never mislabeled as another desktop", {
                let unavailable = WindowDesktopClassifier.classify(
                    isOnScreen: nil, isMinimized: false, isApplicationHidden: false)
                let minimized = WindowDesktopClassifier.classify(
                    isOnScreen: false, isMinimized: true, isApplicationHidden: false)
                let hidden = WindowDesktopClassifier.classify(
                    isOnScreen: false, isMinimized: false, isApplicationHidden: true)
                try expect(unavailable == .unknown && minimized == .unknown && hidden == .unknown,
                           "An uncertain window was incorrectly labeled as another desktop")
            }),
            ("WindowDesktop: real Space IDs map to numbered desktops", {
                let first = WindowDesktopAssignment.resolve(spaceIDs: [3], orderedSpaceIDs: [3, 4], currentSpaceIDs: [3])
                let second = WindowDesktopAssignment.resolve(spaceIDs: [4], orderedSpaceIDs: [3, 4], currentSpaceIDs: [3])
                try expect(first == .init(location: .current, index: 1), "Current Space was not Desktop 1")
                try expect(second == .init(location: .other, index: 2), "Second Space was not Desktop 2")
            }),
            ("WindowDesktop: sticky windows remain on the visible desktop", {
                let value = WindowDesktopAssignment.resolve(spaceIDs: [4, 3], orderedSpaceIDs: [3, 4], currentSpaceIDs: [3])
                try expect(value == .init(location: .current, index: 1), "Sticky window left the current desktop")
            }),
            ("WindowDesktop: missing Space membership stays unknown", {
                let value = WindowDesktopAssignment.resolve(spaceIDs: [], orderedSpaceIDs: [3, 4], currentSpaceIDs: [3])
                try expect(value == .init(location: .unknown, index: nil), "Unknown membership invented a desktop")
            }),
            ("PanelState: 180ms hover opens peek without resetting on repeated entry", {
                var state = PanelState()
                state.pointerEntered(at: 0)
                state.pointerEntered(at: 0.1)
                state.tick(at: 0.179)
                try expect(state.phase == .collapsed, "Hover opened before 180ms")
                state.tick(at: 0.18)
                try expect(state.phase == .peek && state.content == .home, "Hover did not open the home peek")
                state.tick(at: 10)
                try expect(state.phase == .peek, "Hover unexpectedly expanded")
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
                try expect(state.phase == .peek, "Reentry failed to open peek")
                state.pointerExited(at: 1)
                state.tick(at: 1.29)
                try expect(state.phase == .peek, "Peek closed before exit grace elapsed")
                state.tick(at: 1.31)
                try expect(state.phase == .collapsed, "Peek did not close after exit grace")
            }),
            ("PanelState: click expands immediately and hover cannot downgrade", {
                var state = PanelState()
                state.pointerEntered(at: 0)
                state.open()
                state.tick(at: 1)
                try expect(state.phase == .expanded && state.hoverDeadline == nil, "Click failed to cancel pending hover")
                state.select(.files)
                state.peek()
                try expect(state.phase == .expanded && state.content == .files, "Peek downgraded selected expanded content")
            }),
            ("PanelState: drag opens without forcing files and explicit close clears all interaction", {
                var state = PanelState()
                state.pointerEntered(at: 0)
                state.setDragging(true)
                try expect(state.phase == .expanded && state.content == .home, "Drag forced another section instead of preserving content")
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
            ("PanelState: files content closes to the default home state", {
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
            }),
            ("IslandWidgetLayout: packs widgets into rows without exceeding the column count", {
                let layout = IslandWidgetLayout(widgets: [
                    IslandWidget(kind: .media, size: .wide, isEnabled: true),
                    IslandWidget(kind: .timer, size: .medium, isEnabled: true),
                    IslandWidget(kind: .clipboard, size: .medium, isEnabled: true),
                    IslandWidget(kind: .weather, size: .small, isEnabled: true)
                ])
                let rows = layout.rows(columns: 4)
                try expect(rows.count == 3, "Expected three rows, found \(rows.count)")
                for row in rows {
                    try expect(row.usedColumns <= 4, "Row used \(row.usedColumns) of 4 columns")
                }
                try expect(rows[0].widgets.map(\.kind) == [.media], "Wide widget did not claim its own row")
            }),
            ("IslandWidgetLayout: a widget wider than the display is narrowed instead of clipped", {
                let layout = IslandWidgetLayout(widgets: [
                    IslandWidget(kind: .media, size: .wide, isEnabled: true)
                ])
                let rows = layout.rows(columns: 2)
                try expect(rows.count == 1, "Oversized widget did not produce a row")
                try expect(rows[0].widgets[0].size.columns <= 2, "Oversized widget kept a span wider than the grid")
            }),
            ("IslandWidgetLayout: disabled widgets take no space", {
                var layout = IslandWidgetLayout.standard
                for widget in layout.widgets { layout.setEnabled(id: widget.id, false) }
                try expect(layout.rows(columns: 4).isEmpty, "Disabled widgets still produced rows")
                try expect(IslandGeometry.gridHeight(rows: []) == 0, "Empty grid reserved height")
            }),
            ("IslandWidgetLayout: reordering is stable and survives a round trip", {
                var layout = IslandWidgetLayout.standard
                let moved = layout.widgets[0]
                layout.move(id: moved.id, to: 3)
                try expect(layout.widgets[3].id == moved.id, "Widget did not move to the requested index")
                let data = try JSONEncoder().encode(layout)
                let restored = try JSONDecoder().decode(IslandWidgetLayout.self, from: data)
                try expect(restored == layout, "Layout changed across a save and load")
            }),
            ("IslandWidgetLayout: a saved layout regains widget kinds added by a newer build", {
                let saved = IslandWidgetLayout(widgets: [
                    IslandWidget(kind: .clipboard, size: .medium, isEnabled: true)
                ])
                let merged = saved.merging()
                try expect(merged.widgets.first?.kind == .clipboard, "Saved order was discarded")
                try expect(merged.widgets.count == IslandWidgetKind.allCases.count, "New widget kinds stayed hidden")
            }),
            ("IslandGeometry: the panel stays inside the display and keeps whole columns", {
                for screenWidth in [1180.0, 1512.0, 1728.0, 2056.0] as [CGFloat] {
                    let width = IslandGeometry.expandedWidth(screenWidth: screenWidth)
                    try expect(width <= screenWidth - IslandGeometry.displayMargin,
                               "Panel exceeded the display at \(screenWidth) pt")
                    try expect(width >= screenWidth * 0.70, "Panel was far narrower than the brief at \(screenWidth) pt")
                    let columns = IslandGeometry.columns(forWidth: width)
                    try expect(columns >= IslandGeometry.minimumColumns, "Grid dropped below two columns")
                    let columnWidth = IslandGeometry.columnWidth(forWidth: width, columns: columns)
                    let spanned = IslandGeometry.widgetWidth(columnWidth: columnWidth, span: columns)
                    let content = width - IslandGeometry.horizontalPadding * 2
                    try expect(abs(spanned - content) < 0.5, "A full-width widget did not match the content width")
                }
            }),
            ("IslandWidgetLayout: the home strip stays on one row on a wide display", {
                let width = IslandGeometry.expandedWidth(screenWidth: 1512)
                let columns = IslandGeometry.columns(forWidth: width)
                let strip = IslandWidgetLayout(widgets: [
                    IslandWidget(kind: .timer, size: .medium, isEnabled: true),
                    IslandWidget(kind: .media, size: .wide, isEnabled: true),
                    IslandWidget(kind: .quickLaunch, size: .small, isEnabled: true),
                    IslandWidget(kind: .calendar, size: .medium, isEnabled: true),
                    IslandWidget(kind: .weather, size: .small, isEnabled: true)
                ])
                try expect(strip.rows(columns: columns).count == 1,
                           "Reference strip of 11 units did not fit \(columns) columns")
            }),
            ("IslandWidgetLayout: the shipped default fills one row on the smallest supported display", {
                for screenWidth in [1440.0, 1512.0, 1728.0] as [CGFloat] {
                    let columns = IslandGeometry.columns(forWidth: IslandGeometry.expandedWidth(screenWidth: screenWidth))
                    let rows = IslandWidgetLayout.standard.rows(columns: columns)
                    try expect(rows.count == 1, "Default strip wrapped to \(rows.count) rows at \(screenWidth) pt")
                }
            }),
            ("IslandGeometry: every widget in a row shares one height", {
                let rows = IslandWidgetLayout.standard.rows(columns: 12)
                let expected = IslandGeometry.widgetHeight * CGFloat(rows.count) + IslandGeometry.gap * CGFloat(rows.count - 1)
                try expect(IslandGeometry.gridHeight(rows: rows) == expected, "Strip height did not follow the row count")
            }),
            ("IslandGeometry: a narrow display still renders every enabled widget", {
                let width = IslandGeometry.expandedWidth(screenWidth: 1180)
                let columns = IslandGeometry.columns(forWidth: width)
                let layout = IslandWidgetLayout.standard
                let rows = layout.rows(columns: columns)
                let placed = rows.reduce(0) { $0 + $1.widgets.count }
                try expect(placed == layout.enabledWidgets.count, "\(layout.enabledWidgets.count - placed) widgets were dropped")
                try expect(IslandGeometry.expandedHeight(bodyHeight: IslandGeometry.gridHeight(rows: rows)) > 0, "Grid produced no height")
            }),
            ("IslandEvent: a level event replaces its own kind instead of queueing", {
                let first = IslandEvent.volume(0.3, isMuted: false)
                let second = IslandEvent.volume(0.4, isMuted: false)
                try expect(second.supersedes(first), "A second volume change queued behind the first")
                try expect(second.outranks(first), "A newer volume change did not take the panel")
            }),
            ("IslandEvent: a quiet event cannot interrupt a louder one", {
                let volume = IslandEvent.volume(0.5, isMuted: false)
                let track = IslandEvent.nowPlaying(title: "Kill Bill", artist: "SZA")
                try expect(!track.outranks(volume), "A track change stole the panel from the volume slider")
                try expect(volume.outranks(track), "The volume slider lost to a track change")
                try expect(IslandEvent.batteryLow(8).outranks(volume), "A low battery could not interrupt")
            }),
            ("IslandEvent: muting reads as mute rather than zero volume", {
                let muted = IslandEvent.volume(0.7, isMuted: true)
                try expect(muted.kind == .mute, "Muting produced a volume event")
                try expect(muted.progress == 0, "A muted event kept its old level")
                let silent = IslandEvent.volume(0, isMuted: false)
                try expect(silent.kind == .mute, "Zero volume did not read as silence")
            }),
            ("IslandEvent: levels stay inside zero and one", {
                for raw in [-3.0, 0.0, 0.42, 1.0, 7.5] {
                    guard let progress = IslandEvent.volume(raw, isMuted: false).progress else { continue }
                    try expect(progress >= 0 && progress <= 1, "Volume \(raw) produced \(progress)")
                }
            }),
            ("IslandGeometry: an event strip is sized by its own content", {
                let short = IslandGeometry.eventWidth(title: "Ses", detail: "40%", hasProgress: true)
                let long = IslandGeometry.eventWidth(title: "Çok uzun bir şarkı adı burada",
                                                    detail: "Bir sanatçı", hasProgress: false)
                try expect(short < long, "A long title did not widen the strip")
                try expect(long <= IslandGeometry.peekMaximumWidth, "The strip grew past the peek ceiling")
                try expect(short >= 220, "The strip fell below its floor")
            }),
            ("IslandGeometry: quick access widens by tile, not by display", {
                let two = IslandGeometry.launcherWidth(itemCount: 2, screenWidth: 1440)
                let six = IslandGeometry.launcherWidth(itemCount: 6, screenWidth: 1440)
                let many = IslandGeometry.launcherWidth(itemCount: 40, screenWidth: 1440)
                try expect(two <= six, "More tiles did not widen the panel")
                try expect(six < IslandGeometry.expandedWidth(screenWidth: 1440),
                           "Six tiles opened a full-width panel")
                try expect(many == IslandGeometry.expandedWidth(screenWidth: 1440),
                           "A long row ignored the panel ceiling")
                try expect(two >= IslandGeometry.navigationMinimumWidth,
                           "A short row squeezed the icon navigation")
            }),
            ("IslandGeometry: quick access stays one tile row whatever the panel does", {
                let height = IslandGeometry.launcherHeight()
                try expect(height == IslandGeometry.launcherTileHeight, "Quick access reserved more than one tile")
                for width in [640.0, 1008.0, 1440.0] as [CGFloat] {
                    let panel = IslandGeometry.expandedHeight(bodyHeight: height)
                    try expect(panel > height, "The panel did not add its own chrome at \(width) pt")
                    try expect(panel < 260, "Quick access grew the panel past a single row at \(width) pt")
                }
            }),
            ("IslandWidget: every catalog entry is browsable and described", {
                let layout = IslandWidgetLayout.standard
                try expect(layout.widgets.count == IslandWidgetKind.allCases.count,
                           "The shipped layout does not carry the whole catalog")
                let listed = layout.groups.flatMap(\.widgets).map(\.kind)
                try expect(Set(listed) == Set(IslandWidgetKind.allCases),
                           "A widget kind is missing from the library")
                try expect(listed.count == IslandWidgetKind.allCases.count,
                           "A widget kind is listed in more than one category")
                for kind in IslandWidgetKind.allCases {
                    try expect(!kind.title.isEmpty, "\(kind) has no title")
                    try expect(!kind.summary.isEmpty, "\(kind) has no summary")
                    try expect(!kind.symbol.isEmpty, "\(kind) has no symbol")
                }
                for group in layout.groups {
                    try expect(!group.widgets.isEmpty, "\(group.category) is listed but empty")
                }
            }),
            ("IslandWidget: adding from the library lands at the end, at full size", {
                var layout = IslandWidgetLayout.standard
                guard let clock = layout.widgets.first(where: { $0.kind == .worldClock }) else {
                    throw TestFailure(description: "World clock missing from the catalog")
                }
                layout.add(id: clock.id)
                try expect(layout.enabledWidgets.last?.kind == .worldClock,
                           "An added widget did not land at the end of the strip")
                try expect(layout.enabledWidgets.last?.size == IslandWidgetKind.worldClock.defaultSize,
                           "An added widget arrived at the wrong size")
                guard let note = layout.widgets.first(where: { $0.kind == .notes }) else {
                    throw TestFailure(description: "Notes missing from the catalog")
                }
                layout.resize(id: note.id, to: .small)
                layout.add(id: note.id)
                try expect(layout.widgets.first { $0.kind == .notes }?.size == IslandWidgetKind.notes.defaultSize,
                           "Re-adding a widget kept a size it was shrunk to while hidden")
            }),
            ("IslandWidget: the settings arrows step over hidden widgets", {
                var layout = IslandWidgetLayout.standard
                let visible = layout.enabledWidgets
                guard visible.count >= 2, let second = visible.dropFirst().first else {
                    throw TestFailure(description: "The shipped strip has fewer than two widgets")
                }
                layout.moveVisible(id: second.id, by: -1)
                try expect(layout.enabledWidgets.first?.id == second.id,
                           "Moving up did not reach the previous visible widget")
                layout.moveVisible(id: second.id, by: -1)
                try expect(layout.enabledWidgets.first?.id == second.id,
                           "Moving up past the start reordered the strip")
                guard let last = layout.enabledWidgets.last else {
                    throw TestFailure(description: "The strip lost its widgets")
                }
                layout.moveVisible(id: last.id, by: 1)
                try expect(layout.enabledWidgets.last?.id == last.id,
                           "Moving down past the end reordered the strip")
                try expect(layout.widgets.count == IslandWidgetKind.allCases.count,
                           "Reordering dropped a widget from the catalog")
            }),
            ("IslandGeometry: the library grows the panel without moving the strip", {
                let rows = IslandWidgetLayout.standard.rows(columns: 11)
                let closed = IslandGeometry.homeHeight(rows: rows, isEditing: false)
                let open = IslandGeometry.homeHeight(rows: rows, isEditing: true)
                try expect(closed == IslandGeometry.gridHeight(rows: rows),
                           "A closed library still reserved space")
                try expect(open == closed + IslandGeometry.gap + IslandGeometry.libraryHeight(),
                           "The open library reserved the wrong height")
                try expect(IslandGeometry.homeHeight(rows: [], isEditing: true) == IslandGeometry.libraryHeight(),
                           "An empty strip added a gap in front of the library")
            }),
            ("IslandGeometry: the library widens a narrow strip but never narrows a full one", {
                let screenWidth: CGFloat = 1440
                let closed = IslandGeometry.homeWidth(unitCount: 1, isEditing: false, screenWidth: screenWidth)
                let open = IslandGeometry.homeWidth(unitCount: 1, isEditing: true, screenWidth: screenWidth)
                try expect(open > closed, "Opening the library did not widen a one-widget strip")
                try expect(open >= IslandGeometry.libraryCardWidth * 3,
                           "The library opened too narrow to show three cards")
                try expect(open <= IslandGeometry.expandedWidth(screenWidth: screenWidth),
                           "The library pushed the panel past the display ceiling")
                let full = IslandGeometry.homeWidth(unitCount: 16, isEditing: false, screenWidth: 1512)
                try expect(IslandGeometry.homeWidth(unitCount: 16, isEditing: true, screenWidth: 1512) == full,
                           "The library narrowed a full strip")
            }),
            ("AppLeftover: an identifier-named file is an exact match whatever macOS appended", {
                let spotify = AppIdentity(bundleIdentifier: "com.spotify.client", name: "Spotify",
                                          executableName: "Spotify", teamIdentifier: "2FNC3A47ZF",
                                          helperIdentifiers: ["com.spotify.client.helper"])
                let exact: [(String, AppLeftoverKind)] = [
                    ("com.spotify.client", .support),
                    ("com.spotify.client.plist", .preference),
                    ("com.spotify.client.savedState", .savedState),
                    ("com.spotify.client.binarycookies", .cookie),
                    ("com.spotify.client", .container),
                    ("2FNC3A47ZF.com.spotify.client", .groupContainer),
                    ("group.com.spotify.client", .groupContainer),
                    ("com.spotify.client.helper", .launchAgent)
                ]
                for (name, kind) in exact {
                    try expect(AppLeftoverMatcher.confidence(fileName: name, kind: kind, identity: spotify) == .exact,
                               "\(name) was not matched exactly")
                }
                try expect(AppLeftoverMatcher.confidence(fileName: "com.spotify.client.updater.plist",
                                                         kind: .preference, identity: spotify) == .likely,
                           "A helper preference was not reported as likely")
                try expect(AppLeftoverMatcher.confidence(fileName: "Spotify_2026-01-04_Mac.ips",
                                                         kind: .crashReport, identity: spotify) == .likely,
                           "A crash report named after the executable was missed")
            }),
            ("AppLeftover: a name match is the weakest verdict and is refused where names are not used", {
                let spotify = AppIdentity(bundleIdentifier: "com.spotify.client", name: "Spotify",
                                          executableName: "Spotify")
                try expect(AppLeftoverMatcher.confidence(fileName: "Spotify", kind: .support, identity: spotify) == .possible,
                           "A folder named after the application was not reported")
                try expect(AppLeftoverConfidence.possible.isSelectedByDefault == false,
                           "A name match would be ticked by default")
                try expect(AppLeftoverConfidence.likely.isSelectedByDefault,
                           "An identifier match would not be ticked by default")
                for kind in [AppLeftoverKind.container, .groupContainer, .application] {
                    try expect(AppLeftoverMatcher.confidence(fileName: "Spotify", kind: kind, identity: spotify) == nil,
                               "A name match leaked into \(kind)")
                }
            }),
            ("AppLeftover: shared vendor and generic folders are never offered by name", {
                let chrome = AppIdentity(bundleIdentifier: "com.google.Chrome", name: "Google",
                                         executableName: "Google Chrome")
                try expect(AppLeftoverMatcher.confidence(fileName: "Google", kind: .support, identity: chrome) == nil,
                           "Uninstalling Chrome offered the shared Google folder")
                try expect(AppLeftoverMatcher.confidence(fileName: "com.google.Chrome", kind: .support, identity: chrome) == .exact,
                           "The identifier match inside a vendor folder was lost")
                let notes = AppIdentity(bundleIdentifier: "com.example.notes", name: "Notes")
                try expect(AppLeftoverMatcher.confidence(fileName: "Notes", kind: .support, identity: notes) == nil,
                           "A generic name was offered")
                let short = AppIdentity(bundleIdentifier: "com.example.ab", name: "Ab")
                try expect(AppLeftoverMatcher.confidence(fileName: "Ab", kind: .support, identity: short) == nil,
                           "A two-letter name was offered")
            }),
            ("AppLeftover: a neighbouring identifier is never mistaken for the application", {
                let spotify = AppIdentity(bundleIdentifier: "com.spotify.client", name: "Spotify",
                                          executableName: "Spotify")
                for name in ["com.spotify.clienthelper", "com.spotifyx.client", "org.spotify.client",
                             "SpotifyDeluxe", "com.apple.Safari", "Discord"] {
                    try expect(AppLeftoverMatcher.confidence(fileName: name, kind: .support, identity: spotify) == nil,
                               "\(name) was matched against Spotify")
                }
                // A group container ending in the whole identifier belongs to that
                // application whatever team prefix macOS put in front of it, but
                // without a signature to confirm the prefix it is only likely.
                let unsigned = AppIdentity(bundleIdentifier: "com.example.tool", name: "Tooling")
                try expect(AppLeftoverMatcher.confidence(fileName: "TEAMID.com.example.tool",
                                                         kind: .groupContainer, identity: unsigned) == .likely,
                           "An unsigned app lost its own group container")
                try expect(AppLeftoverMatcher.confidence(fileName: "TEAMID.com.example.toolkit",
                                                         kind: .groupContainer, identity: unsigned) == nil,
                           "A longer identifier was matched as a group container")
            }),
            ("AppLeftover: the scan covers every place a leftover lands, and marks the ones needing an admin", {
                let covered = Set(AppLeftoverLocation.all.map(\.kind))
                for kind in AppLeftoverKind.allCases where kind != .application {
                    try expect(covered.contains(kind), "\(kind) has no directory to scan")
                }
                let userPaths = Set(AppLeftoverLocation.all.filter { $0.root == .userLibrary }.map(\.path))
                for expected in ["Application Support", "Caches", "Containers", "Group Containers",
                                 "Preferences", "Preferences/ByHost", "Saved Application State",
                                 "HTTPStorages", "WebKit", "Logs", "LaunchAgents", "Application Scripts"] {
                    try expect(userPaths.contains(expected), "\(expected) is not scanned")
                }
                let system = AppLeftoverLocation.all.filter { $0.root == .systemLibrary }
                try expect(!system.isEmpty, "Nothing under /Library is reported at all")
                try expect(system.allSatisfy(\.requiresAdministrator), "A /Library item was offered for removal")
                try expect(AppLeftoverLocation.all.filter { $0.root == .userLibrary }
                    .allSatisfy { !$0.requiresAdministrator }, "A user library item was marked admin-only")
            }),
            ("AppLeftover: a vendor folder is looked into once, and never offered itself", {
                let chrome = AppIdentity(bundleIdentifier: "com.google.Chrome", name: "Chrome",
                                         executableName: "Google Chrome", teamIdentifier: "EQHXZ8M8AV")
                try expect(AppLeftoverMatcher.isVendorContainer(fileName: "Google", identity: chrome),
                           "The vendor folder was not recognised")
                try expect(AppLeftoverMatcher.confidence(fileName: "Google", kind: .support, identity: chrome) == nil,
                           "The shared vendor folder was offered for removal")
                try expect(AppLeftoverMatcher.confidence(fileName: "Chrome", kind: .support, identity: chrome) == .possible,
                           "The application folder inside the vendor folder was missed")
                try expect(!AppLeftoverMatcher.isVendorContainer(fileName: "Mozilla", identity: chrome),
                           "Another vendor's folder was treated as this one's")
                // An application whose vendor component is its own name has nothing
                // to descend into: that folder was already matched at the top level.
                let spotify = AppIdentity(bundleIdentifier: "com.spotify.client", name: "Spotify")
                try expect(AppLeftoverMatcher.vendorToken(of: spotify) == nil,
                           "Spotify would descend into its own folder twice")
                let short = AppIdentity(bundleIdentifier: "com.ab.tool", name: "Tooling")
                try expect(AppLeftoverMatcher.vendorToken(of: short) == nil,
                           "A two-letter vendor component was treated as a company folder")
            }),
            ("FaceEmbedding: a template is the normalised mean, not the loudest sample", {
                let quiet: [Float] = [1, 0, 0]
                let loud: [Float] = [0, 900, 0]
                guard let template = FaceEmbedding.average([quiet, loud]) else {
                    throw TestFailure(description: "Averaging produced no template")
                }
                let toQuiet = FaceEmbedding.cosineSimilarity(template, quiet)
                let toLoud = FaceEmbedding.cosineSimilarity(template, loud)
                try expect(abs(toQuiet - toLoud) < 0.001, "A larger sample dominated the template")
                let length = template.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
                try expect(abs(length - 1) < 0.001, "Template was not a unit vector")
            }),
            ("FaceEmbedding: mismatched or empty vectors score zero rather than crashing", {
                try expect(FaceEmbedding.cosineSimilarity([1, 0], [1, 0, 0]) == 0, "Different lengths produced a score")
                try expect(FaceEmbedding.cosineSimilarity([], []) == 0, "Empty vectors produced a score")
                try expect(FaceEmbedding.average([]) == nil, "Averaging nothing produced a template")
                try expect(FaceEmbedding.normalized([0, 0, 0]) == nil, "A zero vector was normalised")
            }),
            ("FaceMatcher: samples from another embedder are never compared", {
                let sample = FaceSample(embedding: [1, 0, 0], pose: .center, quality: 0.9)
                let identity = FaceIdentity(name: "Ben", samples: [sample], embedderIdentifier: "model-a")
                let scores = FaceMatcher.score([1, 0, 0], against: [identity], embedderIdentifier: "model-b")
                try expect(scores.isEmpty, "A stale enrollment was scored against a different model")
                let match = FaceMatcher.bestMatch([1, 0, 0], against: [identity],
                                                  embedderIdentifier: "model-b", strictness: .relaxed)
                try expect(match == nil, "A stale enrollment unlocked the app")
            }),
            ("FaceMatcher: a disabled identity cannot unlock", {
                let sample = FaceSample(embedding: [1, 0, 0], pose: .center, quality: 0.9)
                var identity = FaceIdentity(name: "Ben", samples: [sample], embedderIdentifier: "model-a")
                identity.isEnabled = false
                let match = FaceMatcher.bestMatch([1, 0, 0], against: [identity],
                                                  embedderIdentifier: "model-a", strictness: .relaxed)
                try expect(match == nil, "A disabled identity still matched")
            }),
            ("FaceMatcher: a stranger stays out at every strictness", {
                let sample = FaceSample(embedding: [1, 0, 0], pose: .center, quality: 0.9)
                let identity = FaceIdentity(name: "Ben", samples: [sample], embedderIdentifier: "model-a")
                for strictness in FaceMatchStrictness.allCases {
                    let match = FaceMatcher.bestMatch([-1, 0, 0], against: [identity],
                                                      embedderIdentifier: "model-a", strictness: strictness)
                    try expect(match == nil, "An opposite face matched at \(strictness.rawValue)")
                }
                let own = FaceMatcher.bestMatch([1, 0, 0], against: [identity],
                                                embedderIdentifier: "model-a", strictness: .strict)
                try expect(own != nil, "The enrolled face failed to match itself")
            }),
            ("FaceMatcher: strictness thresholds only ever get harder", {
                let ordered = [FaceMatchStrictness.relaxed, .balanced, .strict]
                for index in 1..<ordered.count {
                    try expect(ordered[index].threshold > ordered[index - 1].threshold,
                               "\(ordered[index].rawValue) was not stricter than \(ordered[index - 1].rawValue)")
                }
            }),
            ("FaceIdentity: enrollment is complete only after all nine poses", {
                var identity = FaceIdentity(name: "Ben", embedderIdentifier: "model-a")
                try expect(!identity.isComplete, "An empty enrollment claimed to be complete")
                try expect(identity.missingPoses.count == 9, "The guided walk did not ask for nine poses")
                for pose in FacePose.allCases {
                    identity.samples.append(FaceSample(embedding: [1, 0, 0], pose: pose, quality: 0.9))
                }
                try expect(identity.isComplete, "A full enrollment was reported incomplete")
                try expect(identity.missingPoses.isEmpty, "A full enrollment still listed missing poses")
            }),
            ("FacePose: a frame counts only when the head is actually at that angle", {
                try expect(FacePose.left.accepts(yaw: -0.42, pitch: 0), "The exact target pose was rejected")
                try expect(!FacePose.left.accepts(yaw: 0.42, pitch: 0), "A right turn satisfied the left pose")
                try expect(!FacePose.up.accepts(yaw: 0, pitch: -0.30), "Looking down satisfied the up pose")
                try expect(FacePose.center.accepts(yaw: 0.1, pitch: -0.1), "A small wobble failed the centre pose")
            }),
            ("FaceUnlockSettings: an area is guarded only when the feature is on and picked", {
                var settings = FaceUnlockSettings()
                try expect(!settings.guards(.clipboard), "A disabled feature still guarded an area")
                settings.isEnabled = true
                try expect(settings.guards(.clipboard), "An enabled, selected area was left unguarded")
                try expect(!settings.guards(.camera), "An unselected area was guarded")
                try expect(settings.strictness == .strict, "The default was not the strict threshold")
                try expect(!settings.allowsExperimentalModel, "The experimental model was on by default")
            }),
            ("FaceUnlockSettings: settings survive a JSON round trip", {
                var settings = FaceUnlockSettings()
                settings.isEnabled = true
                settings.protectedAreas = [.clipboard, .shelf, .camera, .uninstaller]
                settings.idleRelockSeconds = 900
                let data = try JSONEncoder().encode(settings)
                let restored = try JSONDecoder().decode(FaceUnlockSettings.self, from: data)
                try expect(restored == settings, "Settings changed across a restart")
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
