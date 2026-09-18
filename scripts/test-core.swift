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

/// Unwraps, or fails the scenario with a sentence rather than a crash.
private func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw TestFailure(description: message) }
    return value
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
            ("IslandGeometry: an event strip is sized by its own content", {
                let short = IslandGeometry.eventWidth(title: "Şarj", detail: "%80", hasProgress: true)
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
                // Vendor folder plus application name is both halves of the identifier.
                try expect(AppLeftoverMatcher.vendorChildConfidence(fileName: "Chrome", kind: .support,
                                                                    identity: chrome) == .likely,
                           "The application's own folder inside its vendor folder was still only a guess")
                try expect(AppLeftoverMatcher.vendorChildConfidence(fileName: "Drive", kind: .support,
                                                                    identity: chrome) == nil,
                           "A sibling product inside the vendor folder was offered")
            }),
            ("AppLeftover: a share extension is found under the team prefix and its own suffix", {
                let telegram = AppIdentity(bundleIdentifier: "ru.keepcoder.Telegram", name: "Telegram",
                                           executableName: "Telegram", teamIdentifier: "6N38VWS5BX")
                for kind in [AppLeftoverKind.groupContainer, .applicationScript] {
                    try expect(AppLeftoverMatcher.confidence(fileName: "6N38VWS5BX.ru.keepcoder.Telegram.TelegramShare",
                                                             kind: kind, identity: telegram) == .likely,
                               "The share extension was missed in \(kind)")
                }
                try expect(AppLeftoverMatcher.confidence(fileName: "6N38VWS5BX.ru.keepcoder.Telegram",
                                                         kind: .groupContainer, identity: telegram) == .exact,
                           "The plain group container stopped being an exact match")
                try expect(AppLeftoverMatcher.confidence(fileName: "6N38VWS5BX.ru.keepcoder.Telegrams.Share",
                                                         kind: .groupContainer, identity: telegram) == nil,
                           "A neighbouring identifier under the same team was claimed")
            }),
            ("AppLeftover: a crash report is matched on the process name, helpers included", {
                let chrome = AppIdentity(bundleIdentifier: "com.google.Chrome", name: "Chrome",
                                         executableName: "Google Chrome", teamIdentifier: "EQHXZ8M8AV")
                try expect(AppLeftoverMatcher.confidence(fileName: "Google Chrome Helper_2026-09-07-145618_mac.diag",
                                                         kind: .crashReport, identity: chrome) == .likely,
                           "A helper's crash report was missed")
                try expect(AppLeftoverMatcher.confidence(fileName: "Google Chrome_3F445A3A-8D0C.plist",
                                                         kind: .crashReport, identity: chrome) == .likely,
                           "The CrashReporter record was missed")
                try expect(AppLeftoverMatcher.confidence(fileName: "Google Chrome Helper_2026-09-07-145618_mac.diag",
                                                         kind: .log, identity: chrome) == nil,
                           "Process-name matching leaked out of crash reports")
                try expect(AppLeftoverMatcher.confidence(fileName: "Google Chromecast_2026-09-07.diag",
                                                         kind: .crashReport, identity: chrome) == nil,
                           "Another process whose name starts the same was claimed")
                let paths = Set(AppLeftoverLocation.all.map(\.path))
                try expect(paths.contains("Application Support/CrashReporter") && paths.contains("Logs/DiagnosticReports"),
                           "Crash reports have nowhere to be found")
            }),
            ("CacheSweep: only caches, logs and build output are ever swept", {
                let paths = Set(CacheSource.all.map(\.path))
                for expected in ["Library/Caches", "Library/Logs", "Library/Developer/Xcode/DerivedData"] {
                    try expect(paths.contains(expected), "\(expected) is not swept")
                }
                for forbidden in ["Documents", "Library/Containers", "Library/Group Containers",
                                  "Library/Preferences", "Library/Application Support", "Desktop"] {
                    try expect(!paths.contains(forbidden), "\(forbidden) is swept")
                }
            }),
            ("CacheSweep: a queue is not a cache and is never offered", {
                for name in ["CloudKit", "com.apple.containermanagerd",
                             "com.apple.nsurlsessiond", "com.apple.appstore"] {
                    try expect(!CacheSweepRules.isSweepable(name: name), "\(name) was offered")
                }
                try expect(CacheSweepRules.isSweepable(name: "com.spotify.client"),
                           "An ordinary application cache was refused")
                for name in ["", ".", "..", ".marker", "a/b"] {
                    try expect(!CacheSweepRules.isSweepable(name: name), "\(name) was accepted")
                }
            }),
            ("CacheSweep: the sweep reaches exactly one level into a listed directory", {
                let home = "/Users/tester"
                for allowed in ["\(home)/Library/Caches/com.spotify.client",
                                "\(home)/Library/Logs/Claude", "\(home)/.npm/_cacache"] {
                    try expect(CacheSweepRules.isSweepablePath(allowed, home: home), "\(allowed) was refused")
                }
                for refused in ["\(home)/Library/Caches",
                                "\(home)/Library/Caches/com.spotify.client/Data",
                                "\(home)/Library/Preferences/com.spotify.client.plist",
                                "/Library/Caches/com.spotify.client",
                                "\(home)/Library/Caches/../Preferences/x"] {
                    try expect(!CacheSweepRules.isSweepablePath(refused, home: home), "\(refused) was allowed")
                }
                try expect(!CacheSweepRules.isSweepablePath("\(home)/Library/Caches/x", home: ""),
                           "An empty home directory matched everything")
            }),
            ("CacheSweep: build tool caches are read as developer work", {
                try expect(CacheSweepRules.group(forCacheName: "Homebrew", default: .applications) == .developer,
                           "Homebrew was filed under applications")
                try expect(CacheSweepRules.group(forCacheName: "org.swift.swiftpm", default: .applications) == .developer,
                           "SwiftPM was filed under applications")
                try expect(CacheSweepRules.group(forCacheName: "com.spotify.client", default: .applications) == .applications,
                           "An application cache was filed under developer work")
                try expect(CacheSweepRules.group(forCacheName: "SomeThing", default: .logs) == .logs,
                           "An unknown folder ignored the caller's fallback")
            }),
            ("LidFold: the fold only starts once the lid is past the open angle", {
                try expect(LidFold.progress(forAngle: 180) == 0, "An open lid folded")
                try expect(LidFold.progress(forAngle: LidFold.defaultOpenAngle) == 0, "The boundary folded")
                try expect(abs(LidFold.progress(forAngle: 37) - 0.5) < 0.02, "The midpoint was wrong")
                try expect(LidFold.progress(forAngle: 14) == 1, "A shut lid was not folded")
                try expect(LidFold.progress(forAngle: 0) == 1, "A shut lid was not folded")
                try expect(LidFold.isClosed(angle: 3) && !LidFold.isClosed(angle: 30), "Closed was misread")
            }),
            ("LidFold: every degree of hinge adds the same amount of fold", {
                let step = LidFold.progress(forAngle: 50) - LidFold.progress(forAngle: 55)
                for start in stride(from: 55.0, to: 20.0, by: -5) {
                    let delta = LidFold.progress(forAngle: start - 5) - LidFold.progress(forAngle: start)
                    try expect(abs(delta - step) < 0.001, "The fold was not a straight line at \(start)°")
                }
            }),
            ("LidFold: a chosen angle moves the whole fold with it", {
                try expect(abs(LidFold.progress(forAngle: 80, openAngle: 100) - 0.233) < 0.01,
                           "A higher starting angle did not move the fold")
                try expect(LidFold.progress(forAngle: 80, openAngle: 60) == 0,
                           "The default start folded too early")
                try expect(LidFold.clampOpenAngle(0) == LidFold.minimumOpenAngle,
                           "An impossible angle was accepted")
                try expect(LidFold.clampOpenAngle(500) == LidFold.maximumOpenAngle,
                           "An impossible angle was accepted")
                try expect(abs(LidFold.progress(forAngle: 18, openAngle: 20) - 0.333) < 0.01,
                           "The lowest starting angle had no room to animate")
            }),
            ("Automation: an event runs only the rules waiting for it", {
                func rule(_ trigger: AutomationTrigger, _ action: AutomationAction = .pauseMedia,
                          enabled: Bool = true) -> AutomationRule {
                    AutomationRule(title: "Kural", isEnabled: enabled, trigger: trigger, action: action)
                }
                var engine = AutomationEngine(rules: [
                    rule(.lidOpened, .showNotice("merhaba")), rule(.lidClosing, .pauseMedia)
                ])
                try expect(engine.actions(for: .lidOpened) == [.showNotice("merhaba")], "Wrong rule ran")
                try expect(engine.actions(for: .lidClosing) == [.pauseMedia], "Wrong rule ran")
                try expect(engine.actions(for: .timerFinished).isEmpty, "An unrelated event ran a rule")
                var off = AutomationEngine(rules: [rule(.timerFinished, enabled: false)])
                try expect(off.actions(for: .timerFinished).isEmpty, "A switched-off rule ran")
            }),
            ("Automation: a rule rests before it can run again", {
                let rule = AutomationRule(title: "Kural", trigger: .mediaStarted, action: .pauseMedia)
                var engine = AutomationEngine(rules: [rule])
                let start = Date()
                try expect(engine.actions(for: .mediaStarted, now: start).count == 1, "The rule did not run")
                try expect(engine.actions(for: .mediaStarted, now: start.addingTimeInterval(5)).isEmpty,
                           "Skipping tracks ran the rule again")
                try expect(engine.actions(for: .mediaStarted,
                                          now: start.addingTimeInterval(AutomationEngine.cooldown + 1)).count == 1,
                           "The rule never woke up again")
            }),
            ("Automation: a battery rule fires once on the way down", {
                let rule = AutomationRule(title: "Kural", trigger: .batteryBelow(percent: 20), action: .pauseMedia)
                var engine = AutomationEngine(rules: [rule])
                let start = Date()
                try expect(engine.actions(for: .batteryLevel(15), now: start).isEmpty,
                           "A battery that was already low fired on launch")
                try expect(engine.actions(for: .batteryLevel(60), now: start).isEmpty, "Charging fired a rule")
                try expect(engine.actions(for: .batteryLevel(19), now: start.addingTimeInterval(600)).count == 1,
                           "Crossing the line did nothing")
                try expect(engine.actions(for: .batteryLevel(12), now: start.addingTimeInterval(1200)).isEmpty,
                           "The same crossing fired twice")
            }),
            ("Automation: only the web and local files may be opened", {
                try expect(AutomationAction.openLink("https://example.com").isSafe, "A web link was refused")
                try expect(AutomationAction.openLink("file:///Users/x/notes.txt").isSafe, "A file was refused")
                try expect(!AutomationAction.openLink("x-apple-shortcut://run?name=wipe").isSafe,
                           "A custom scheme was allowed")
                try expect(!AutomationAction.openLink("javascript:alert(1)").isSafe, "A script link was allowed")
                try expect(!AutomationAction.openLink("https://").isSafe, "A link with no host was allowed")
                try expect(AutomationAction.runShortcut(name: "Gece Modu").isSafe, "A shortcut name was refused")
                try expect(!AutomationAction.runShortcut(name: "Gece\nrm -rf /").isSafe,
                           "A shortcut name carried a second line")
                try expect(!AutomationAction.startTimer(minutes: 0).isSafe, "A zero-minute timer was allowed")
                try expect(!AutomationAction.showNotice("   ").isSafe, "A blank notice was allowed")
                var engine = AutomationEngine(rules: [
                    AutomationRule(title: "Kural", trigger: .lidOpened,
                                   action: .openLink("javascript:alert(1)"))
                ])
                try expect(engine.actions(for: .lidOpened).isEmpty, "An unsafe action ran")
            }),
            ("Automation: an application rule ignores the case of the identifier", {
                var engine = AutomationEngine(rules: [
                    AutomationRule(title: "Kural", trigger: .appLaunched(bundleIdentifier: "com.spotify.client"),
                                   action: .pauseMedia)
                ])
                try expect(engine.actions(for: .appLaunched("com.Spotify.Client")).count == 1,
                           "Case stopped a rule from running")
                var quitting = AutomationEngine(rules: [
                    AutomationRule(title: "Kural", trigger: .appQuit(bundleIdentifier: "com.spotify.client"),
                                   action: .pauseMedia)
                ])
                try expect(quitting.actions(for: .appLaunched("com.spotify.client")).isEmpty,
                           "A quit rule ran on a launch")
            }),
            ("Automation: rules survive a restart", {
                let rules = [AutomationRule(title: "Şarj", trigger: .chargerConnected, action: .startTimer(minutes: 25)),
                             AutomationRule(title: "Safari", trigger: .appQuit(bundleIdentifier: "com.apple.Safari"),
                                            action: .runShortcut(name: "Kapat"))]
                let data = try JSONEncoder().encode(rules)
                try expect(try JSONDecoder().decode([AutomationRule].self, from: data) == rules,
                           "The rules changed across a restart")
            }),
            ("LidScreenBlur: the screen is untouched until the fold starts", {
                for index in 0..<LidScreenBlur.layerCount {
                    try expect(LidScreenBlur.layerAlpha(index, progress: 0) == 0, "A pane was already up")
                }
                try expect(LidScreenBlur.strength(progress: 0) == 0, "The blur started early")
            }),
            ("LidScreenBlur: every pane has arrived before the lid shuts", {
                for index in 0..<LidScreenBlur.layerCount {
                    try expect(LidScreenBlur.layerAlpha(index, progress: 0.95) == 1, "A pane never arrived")
                }
                try expect(LidScreenBlur.strength(progress: 1) == 1, "The blur never reached full")
            }),
            ("LidScreenBlur: the blur only ever deepens, in every stretch of the fold", {
                var previous = -1.0
                for step in 0...100 {
                    let strength = LidScreenBlur.strength(progress: Double(step) / 100)
                    try expect(strength >= previous, "The blur went backwards")
                    previous = strength
                }
                for step in 0..<19 {
                    let low = Double(step) / 20, high = Double(step + 1) / 20
                    try expect(LidScreenBlur.strength(progress: high) > LidScreenBlur.strength(progress: low),
                               "The screen looked frozen for a stretch of the fold")
                }
            }),
            ("LidScreenBlur: panes arrive one after another so the radius steps up", {
                try expect(LidScreenBlur.layerAlpha(0, progress: 0.4) == 1, "The first pane lagged")
                try expect(LidScreenBlur.layerAlpha(1, progress: 0.4) < 0.5, "The second pane came too early")
                try expect(LidScreenBlur.layerAlpha(2, progress: 0.4) == 0, "The last pane came too early")
                try expect(LidScreenBlur.layerAlpha(-1, progress: 1) == 0, "A pane that does not exist arrived")
                try expect(LidScreenBlur.layerAlpha(LidScreenBlur.layerCount, progress: 1) == 0,
                           "A pane past the end arrived")
            }),
            ("IslandEvent: a hand-written line replaces the greeting, detail intact", {
                let event = try require(IslandEvent.welcome(hour: 2, time: "09:14", batteryPercent: 78,
                                                            custom: "Hoş geldin"),
                                        "A written line produced no greeting at all")
                try expect(event.title == "Hoş geldin", "The written line was ignored")
                try expect(event.detail == "09:14 · %78", "The detail was lost")
                let bye = try require(IslandEvent.farewell(hour: 2, batteryPercent: 72,
                                                           custom: "  Kendine iyi bak  "),
                                      "A written farewell produced nothing")
                try expect(bye.title == "Kendine iyi bak", "The farewell was not trimmed")
                try expect(bye.detail == "%72", "The battery was lost")
            }),
            ("IslandEvent: an empty line leaves the time of day in charge", {
                try expect(IslandEvent.customTitle(nil) == nil, "Nothing became something")
                try expect(IslandEvent.customTitle("") == nil, "An empty field counted")
                try expect(IslandEvent.customTitle("   \n ") == nil, "Spaces blanked the island")
                // Both ends of the lid are the same rule: an empty field is an
                // instruction to say nothing, not a request to have something
                // picked by the clock.
                for blank in [nil, "", "   \n "] as [String?] {
                    try expect(IslandEvent.welcome(hour: 2, time: "09:14", batteryPercent: 78,
                                                   custom: blank) == nil,
                               "An empty welcome line still put something on screen")
                    try expect(IslandEvent.farewell(hour: 2, batteryPercent: 78, custom: blank) == nil,
                               "An empty farewell line still put something on screen")
                }
                let long = String(repeating: "a", count: IslandEvent.customTitleLimit + 20)
                try expect(IslandEvent.customTitle(long)?.count == IslandEvent.customTitleLimit,
                           "A line too long for the island was not cut")
            }),
            ("LidFold: an opening is reported once, and only after a real close", {
                var tracker = LidFoldTracker()
                for angle in [110.0, 104, 112, 100] {
                    try expect(tracker.update(angle: angle) == .none, "Typing wobble counted as an event")
                }
                try expect(tracker.update(angle: 55) == .folding, "The fold was not reported")
                try expect(tracker.update(angle: 40) == .none, "The fold was reported twice")
                try expect(tracker.update(angle: 2) == .none, "Closing raised an event")
                try expect(tracker.update(angle: 20) == .none, "A half open lid greeted")
                try expect(tracker.update(angle: 95) == .opened, "The opening was missed")
                try expect(tracker.update(angle: 100) == .none, "The same open lid greeted twice")
                // A dip that never reaches closed must never greet on the way back.
                var dipping = LidFoldTracker()
                _ = dipping.update(angle: 120)
                try expect(dipping.update(angle: 40) == .folding, "The dip did not fold")
                try expect(dipping.update(angle: 120) == .none, "A dip greeted")
                // A sensor that goes quiet forgets the angle but not the state.
                var quiet = LidFoldTracker()
                _ = quiet.update(angle: 3)
                try expect(quiet.update(angle: nil) == .none, "A silent sensor raised an event")
                try expect(quiet.progress == 0, "A silent sensor still folded the island")
                try expect(quiet.update(angle: 100) == .opened, "The opening was lost with the reading")
            }),
            ("IslandEvent: the lid line carries the time and the battery with it", {
                let event = try require(IslandEvent.welcome(hour: 9, time: "09:14", batteryPercent: 78,
                                                            custom: "Günaydın"),
                                        "A written greeting produced nothing")
                try expect(event.kind == .welcome && event.detail == "09:14 · %78", "The greeting read wrong")
                let noBattery = try require(IslandEvent.welcome(hour: 9, time: "09:14", batteryPercent: nil,
                                                                custom: "Günaydın"),
                                            "A written greeting produced nothing")
                try expect(noBattery.detail == "09:14", "A machine with no battery printed one")
            }),
            ("ProcessRanking: a helper is credited to the application it belongs to", {
                let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
                try expect(ProcessRanking.bundlePath(forExecutablePath: helper) == "/Applications/Google Chrome.app",
                           "The innermost helper bundle won over the application")
                try expect(ProcessRanking.groupKey(forExecutablePath: helper, name: "Google Chrome H") == "Google Chrome",
                           "A helper was listed on its own")
                try expect(ProcessRanking.bundlePath(forExecutablePath: "/usr/libexec/fileproviderd") == nil,
                           "A daemon was given a bundle")
                try expect(ProcessRanking.groupKey(forExecutablePath: "/usr/libexec/com.apple.someverylongdaemon",
                                                   name: "com.apple.somev") == "com.apple.someverylongdaemon",
                           "The truncated kernel name won over the path")
                try expect(ProcessRanking.groupKey(forExecutablePath: "", name: "kernel_task") == "kernel_task",
                           "A process with no path lost its name")
            }),
            ("ProcessRanking: memory is summed and processor time is a rate", {
                let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
                let helper = "/Applications/Google Chrome.app/Contents/Helpers/Renderer.app/Contents/MacOS/Renderer"
                let samples = [
                    ProcessSample(pid: 1, path: chrome, name: "Google Chrome",
                                  residentBytes: 400_000_000, cpuTimeNanos: 3_000_000_000),
                    ProcessSample(pid: 2, path: helper, name: "Renderer",
                                  residentBytes: 600_000_000, cpuTimeNanos: 2_000_000_000)
                ]
                let usage = ProcessRanking.usage(current: samples,
                                                 previous: [1: 2_000_000_000, 2: 2_000_000_000],
                                                 elapsed: 2)
                guard let group = usage.first, usage.count == 1 else {
                    throw TestFailure(description: "Helpers were not folded into the application")
                }
                try expect(group.memoryBytes == 1_000_000_000, "Memory was not summed")
                try expect(group.processCount == 2, "The process count was wrong")
                try expect(abs(group.cpuPercent - 50) < 0.01, "One core-second over two seconds was not half a core")
                try expect(group.leadPID == 2, "The heaviest process was not the one named")
                let fresh = ProcessRanking.usage(current: [samples[0]], previous: [:], elapsed: 2)
                try expect(fresh.first?.cpuPercent == 0,
                           "A process seen once reported its whole lifetime as recent work")
            }),
            ("ProcessRanking: the two orderings answer two different questions", {
                let hungry = ProcessUsage(name: "Hungry", memoryBytes: 900, cpuPercent: 1,
                                          processCount: 1, leadPID: 1)
                let busy = ProcessUsage(name: "Busy", memoryBytes: 100, cpuPercent: 90,
                                        processCount: 1, leadPID: 2)
                try expect(ProcessRanking.topByMemory([busy, hungry], limit: 2).first?.name == "Hungry",
                           "The memory list was not ordered by memory")
                try expect(ProcessRanking.topByCPU([hungry, busy], limit: 2).first?.name == "Busy",
                           "The processor list was not ordered by processor")
                try expect(ProcessRanking.topByCPU([busy, hungry], limit: 0).isEmpty,
                           "A limit of zero still returned rows")
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
            }),
            ("TrashRestorePlan: an item is only put back into a place that is still free", {
                try expect(TrashRestorePlan.outcome(trashedExists: true, originalExists: false) == .restore,
                           "An item still in the Trash was not offered back")
                try expect(TrashRestorePlan.outcome(trashedExists: false, originalExists: false) == .missingFromTrash,
                           "An emptied Trash was treated as restorable")
                try expect(TrashRestorePlan.outcome(trashedExists: true, originalExists: true) == .occupied,
                           "A restore would have overwritten whatever took the old path")
                try expect(TrashRestorePlan.outcome(trashedExists: false, originalExists: true) == .missingFromTrash,
                           "A missing item was not reported as missing")
            }),
            ("TrashRestorePlan: the report names every outcome, not only the good one", {
                try expect(TrashRestorePlan.summary(restored: 0, missing: 0, occupied: 0) == "Geri alınacak bir şey yok.",
                           "An empty undo claimed to have done something")
                let partial = TrashRestorePlan.summary(restored: 2, missing: 1, occupied: 3)
                try expect(partial.contains("2 öğe"), "The restored count went unreported")
                try expect(partial.contains("1 öğe"), "The missing count went unreported")
                try expect(partial.contains("3 öğe"), "The blocked count went unreported")
                let clean = TrashRestorePlan.summary(restored: 4, missing: 0, occupied: 0)
                try expect(!clean.contains("bulunamadı") && !clean.contains("dolu"),
                           "A clean undo reported failures it did not have")
            }),
            ("LidScreenBlur: the radius climbs the whole way down and is front-loaded", {
                try expect(LidScreenBlur.blurRadius(progress: 0) == 0, "The blur started before the lid moved")
                var previous = -1.0
                for step in 0...20 {
                    let radius = LidScreenBlur.blurRadius(progress: Double(step) / 20)
                    try expect(radius > previous, "The radius stalled at \(Double(step) / 20)")
                    previous = radius
                }
                try expect(abs(LidScreenBlur.blurRadius(progress: 1) - LidScreenBlur.maximumRadius) < 0.001,
                           "The blur did not reach its maximum by the end of the fold")
                // Half way down the lid, more than half the blur: the early part
                // of the fold is the part anyone has time to look at.
                try expect(LidScreenBlur.blurRadius(progress: 0.5) > LidScreenBlur.maximumRadius * 0.5,
                           "The blur was not front-loaded")
            }),
            ("LidScreenBlur: the dim follows the blur without ever hiding the screen on its own", {
                try expect(LidScreenBlur.dimAlpha(progress: 0) == 0, "The screen dimmed before the lid moved")
                try expect(LidScreenBlur.dimAlpha(progress: 1) == LidScreenBlur.maximumDim,
                           "The dim did not reach its maximum")
                try expect(LidScreenBlur.maximumDim < 0.5, "The dim was heavy enough to be the whole effect")
                try expect(LidScreenBlur.dimAlpha(progress: 0.5) < LidScreenBlur.maximumDim * 0.5,
                           "The dim ran ahead of the blur instead of trailing it")
            }),
            ("LidBlurLiveness: a lid held perfectly still is not a lid that stopped reporting", {
                // The bug this exists to stop: the hinge reports the same angle
                // over and over while somebody closes the lid slowly, and the
                // blur used to read that as a dead sensor and take itself off.
                var liveness = LidBlurLiveness()
                var now = 0.0
                for _ in 0..<120 {
                    liveness.sawReading(at: now)
                    now += 0.5
                    try expect(!liveness.isStalled(at: now),
                               "The blur gave up on a hinge that was still answering, at \(now)s")
                }
            }),
            ("RadialMenu: slice zero is straight up and the rest run clockwise", {
                let zone = RadialMenuMetrics().deadZone
                let up = RadialMenuGeometry.slice(dx: 0, dy: 80, count: 4, deadZone: zone)
                let right = RadialMenuGeometry.slice(dx: 80, dy: 0, count: 4, deadZone: zone)
                let down = RadialMenuGeometry.slice(dx: 0, dy: -80, count: 4, deadZone: zone)
                let left = RadialMenuGeometry.slice(dx: -80, dy: 0, count: 4, deadZone: zone)
                try expect(up == 0, "Up was not the first slice, it was \(String(describing: up))")
                try expect(right == 1, "The ring did not run clockwise")
                try expect(down == 2, "Down landed on \(String(describing: down))")
                try expect(left == 3, "Left landed on \(String(describing: left))")
                // A slice is centred on its direction, so either side of straight
                // up is still the first slice.
                try expect(RadialMenuGeometry.slice(dx: 20, dy: 80, count: 6, deadZone: zone) == 0, "Up drifted off slice zero")
                try expect(RadialMenuGeometry.slice(dx: -20, dy: 80, count: 6, deadZone: zone) == 0, "Up drifted off slice zero")
                for count in RadialMenuGeometry.minimumSlices...RadialMenuGeometry.maximumSlices {
                    for step in 0..<count {
                        let angle = RadialMenuGeometry.midAngle(step, count: count)
                        let picked = RadialMenuGeometry.slice(dx: sin(angle) * 90, dy: cos(angle) * 90,
                                                              count: count, deadZone: zone)
                        try expect(picked == step,
                                   "Aiming at the middle of slice \(step) of \(count) picked \(String(describing: picked))")
                    }
                }
            }),
            ("ClipboardSearch: typing part of an entry finds it, however it was written", {
                let entry = ["İstanbul Havalimanı", nil, "https://ornek.com/güzergâh"]
                for query in ["istanbul", "İSTANBUL", "Havalimani", "havalimanı", "  istanbul  "] {
                    try expect(ClipboardSearch.matches(haystack: entry, query: query),
                               "Searching for \(query) missed the entry")
                }
                try expect(ClipboardSearch.matches(haystack: entry, query: "guzergah"),
                           "Searching without the accents missed the entry")
                try expect(!ClipboardSearch.matches(haystack: entry, query: "ankara"),
                           "An entry matched something that is not in it")
                try expect(ClipboardSearch.matches(haystack: entry, query: ""),
                           "An empty search hid everything")
                try expect(ClipboardSearch.matches(haystack: entry, query: "   "),
                           "A search of spaces hid everything")
                try expect(!ClipboardSearch.matches(haystack: [nil, nil], query: "x"),
                           "An entry with nothing in it matched")
            }),
            ("RadialMenu: one slice is a real ring, aimed in any direction", {
                let zone = RadialMenuMetrics().deadZone
                for degrees in stride(from: 0.0, to: 360.0, by: 15) {
                    let radians = degrees * .pi / 180
                    let picked = RadialMenuGeometry.slice(dx: sin(radians) * 70, dy: cos(radians) * 70,
                                                          count: 1, deadZone: zone)
                    try expect(picked == 0, "A one-slice ring missed at \(degrees)°")
                }
                try expect(RadialMenuGeometry.slice(dx: 0, dy: 0, count: 1, deadZone: zone) == nil,
                           "A one-slice ring fired from the middle")
            }),
            ("ThreeFingerTap: a tap opens the ring, a swipe and a wrong count do not", {
                func tap(fingers: [Int], step: Double) -> Bool {
                    var recogniser = ThreeFingerTap()
                    var now = 0.0
                    var fired = false
                    for count in fingers {
                        if recogniser.frame(fingers: count, at: now) { fired = true }
                        now += step
                    }
                    return fired
                }
                // Three fingers landing a little apart and leaving together.
                try expect(tap(fingers: [1, 2, 3, 3, 0], step: 0.02),
                           "A three-finger tap was not recognised")
                try expect(tap(fingers: [3, 3, 2, 1, 0], step: 0.02),
                           "A tap whose fingers came off one at a time was missed")
                // A swipe: three fingers, held far longer than a tap.
                try expect(!tap(fingers: Array(repeating: 3, count: 30) + [0], step: 0.02),
                           "A three-finger swipe opened the ring")
                try expect(!tap(fingers: [2, 2, 0], step: 0.02), "Two fingers counted as three")
                try expect(!tap(fingers: [3, 4, 4, 0], step: 0.02), "Four fingers counted as three")
                try expect(!tap(fingers: [1, 1, 0], step: 0.02), "One finger counted as three")
                try expect(!tap(fingers: [0, 0, 0], step: 0.02), "Nothing at all counted as a tap")
                try expect(ThreeFingerTap.maximumDuration < 0.5,
                           "The window was long enough to swallow a swipe")
            }),
            ("AIResponseStream: text, searching and sources are read out of the stream", {
                try expect(AIResponseStream.event(fromData: #"data: {"type":"response.output_text.delta","delta":"Merhaba"}"#) == .text("Merhaba"),
                           "A text delta was not read")
                try expect(AIResponseStream.event(fromData: #"data: {"type":"response.web_search_call.searching"}"#) == .searching,
                           "A search starting was not noticed")
                let done = #"data: {"type":"response.completed","response":{"output":[{"type":"web_search_call"},{"type":"message","content":[{"type":"output_text","text":"x","annotations":[{"type":"url_citation","url":"https://a.com/1","title":"A"},{"type":"url_citation","url":"https://a.com/1","title":"A again"},{"type":"url_citation","url":"javascript:alert(1)","title":"bad"},{"type":"url_citation","url":"https://b.com","title":""}]}]}]}}"#
                guard case .finished(let sources) = AIResponseStream.event(fromData: done) else {
                    throw TestFailure(description: "A finished response was not recognised")
                }
                try expect(sources.map(\.url.absoluteString) == ["https://a.com/1", "https://b.com"],
                           "Sources were duplicated, lost, or let a non-web link through: \(sources.map(\.url))")
                try expect(sources[1].displayTitle == "b.com", "A source with no title had nothing to show")
                if case .failed = AIResponseStream.event(fromData: #"data: {"type":"error","error":{"message":"bad model"}}"#) {} else {
                    throw TestFailure(description: "An error from OpenAI was swallowed")
                }
                for noise in ["", "event: response.output_text.delta", "data: [DONE]", "data: {not json",
                              #"data: {"type":"response.something_new"}"#] {
                    try expect(AIResponseStream.event(fromData: noise) == .ignored, "\(noise) was not ignored")
                }
            }),
            ("AIResponseStream: only the conversation goes out, never stored, history capped", {
                let history = (0..<10).map { AITurn(question: "q\($0)", answer: "a\($0)") }
                let body = AIResponseStream.requestBody(question: "son", model: "m", history: history)
                try expect(body["store"] as? Bool == false, "The conversation was left for OpenAI to keep")
                try expect(body["stream"] as? Bool == true, "The answer was not streamed")
                let input = body["input"] as? [[String: Any]] ?? []
                try expect(input.count == AIResponseStream.maximumHistory * 2 + 1,
                           "History was not capped: \(input.count) messages")
                try expect(input.last?["content"] as? String == "son", "The new question was not last")
                let tools = body["tools"] as? [[String: Any]] ?? []
                try expect(tools.first?["type"] as? String == "web_search", "Web search was not offered")
                try expect(Set(body.keys) == ["model", "input", "stream", "store", "tools", "instructions"],
                           "Something other than the conversation was sent: \(body.keys.sorted())")
            }),
            ("ScreenshotDetection: macOS's own mark decides, the name is only a fallback", {
                try expect(ScreenshotDetection.isScreenshot(fileName: "Adsız.png", hasCaptureAttribute: true),
                           "A marked screenshot with an unusual name was missed")
                try expect(ScreenshotDetection.isScreenshot(fileName: "Ekran Resmi 2026-09-18 10.12.03.png", hasCaptureAttribute: nil),
                           "A Turkish screenshot name was not recognised")
                try expect(ScreenshotDetection.isScreenshot(fileName: "Screenshot 2026-09-18 at 10.12.03.png", hasCaptureAttribute: nil),
                           "An English screenshot name was not recognised")
                try expect(!ScreenshotDetection.isScreenshot(fileName: ".Ekran Resmi 2026.png", hasCaptureAttribute: true),
                           "The half-written temporary file was taken")
                try expect(!ScreenshotDetection.isScreenshot(fileName: "tatil.png", hasCaptureAttribute: nil),
                           "An ordinary picture was taken for a screenshot")
                try expect(!ScreenshotDetection.isScreenshot(fileName: "Screenshot notlar.txt", hasCaptureAttribute: nil),
                           "A text file was taken for a screenshot")
                let home = URL(fileURLWithPath: "/Users/x")
                try expect(ScreenshotDetection.folder(configured: nil, home: home, exists: { _ in true }).path == "/Users/x/Desktop",
                           "The default folder was not the Desktop")
                try expect(ScreenshotDetection.folder(configured: "/Users/x/Pics", home: home, exists: { _ in false }).path == "/Users/x/Desktop",
                           "A configured folder that no longer exists was watched")
                try expect(ScreenshotDetection.folder(configured: "/Users/x/Pics", home: home, exists: { _ in true }).path == "/Users/x/Pics",
                           "The user's chosen folder was ignored")
            }),
            ("AIKeyFormat: an obviously broken key is caught before it is stored", {
                try expect(AIKeyFormat.looksLikeKey("sk-" + String(repeating: "a", count: 40)),
                           "A real-shaped key was rejected")
                try expect(AIKeyFormat.looksLikeKey("  sk-" + String(repeating: "a", count: 40) + "\n"),
                           "A key with the usual paste whitespace around it was rejected")
                try expect(!AIKeyFormat.looksLikeKey("sk-short"), "A truncated paste was accepted")
                try expect(!AIKeyFormat.looksLikeKey(String(repeating: "a", count: 40)),
                           "Something with no prefix at all was accepted")
                try expect(!AIKeyFormat.looksLikeKey("sk-" + String(repeating: "a", count: 20) + " " +
                                                     String(repeating: "b", count: 20)),
                           "A key with a space in the middle of it was accepted")
                try expect(!AIKeyFormat.looksLikeKey(""), "An empty field was accepted")
            }),
            ("RadialMenu: the middle chooses nothing, at every size", {
                for scale in [RadialMenuMetrics.minimumScale, 0.85, 1, RadialMenuMetrics.maximumScale] {
                    let metrics = RadialMenuMetrics(scale: scale)
                    let zone = metrics.deadZone
                    try expect(RadialMenuGeometry.slice(dx: 0, dy: 0, count: 6, deadZone: zone) == nil,
                               "The ring fired at the point the click landed, at \(scale)")
                    try expect(RadialMenuGeometry.slice(dx: zone - 0.5, dy: 0, count: 6, deadZone: zone) == nil,
                               "The dead zone was smaller than it claims, at \(scale)")
                    try expect(RadialMenuGeometry.slice(dx: zone + 0.5, dy: 0, count: 6, deadZone: zone) != nil,
                               "Nothing outside the dead zone could be picked, at \(scale)")
                    // The hand has to be able to leave the middle and still land
                    // on the band it can see.
                    try expect(zone < metrics.innerRadius,
                               "The dead zone reached past the hole at \(scale)")
                    try expect(metrics.outerRadius > metrics.innerRadius + 20,
                               "The band was too thin to aim at, at \(scale)")
                }
                try expect(RadialMenuMetrics(scale: 99).scale == RadialMenuMetrics.maximumScale,
                           "The size dial had no ceiling")
                try expect(RadialMenuMetrics(scale: 0).scale == RadialMenuMetrics.minimumScale,
                           "The size dial had no floor")
            }),
            ("RadialMenu: the ring stays on screen even in a corner", {
                let screen = (x: 0.0, y: 0.0, width: 1440.0, height: 900.0)
                let size = RadialMenuMetrics().side
                for cursor in [(x: 0.0, y: 0.0), (x: 1440.0, y: 900.0), (x: 2.0, y: 898.0)] {
                    let origin = RadialMenuGeometry.origin(forCursor: cursor, size: size, screen: screen)
                    try expect(origin.x >= screen.x && origin.x + size <= screen.x + screen.width,
                               "The ring hung off the side at \(cursor)")
                    try expect(origin.y >= screen.y && origin.y + size <= screen.y + screen.height,
                               "The ring hung off the top or bottom at \(cursor)")
                }
                let middle = RadialMenuGeometry.origin(forCursor: (x: 720, y: 450), size: size, screen: screen)
                try expect(middle.x == 720 - size / 2 && middle.y == 450 - size / 2,
                           "The ring was nudged even though it fitted")
            }),
            ("RadialMenu: a slice that cannot work is dropped, not left dead on the ring", {
                let safari = RadialSlot.open(path: "/Applications/Safari.app")
                let gone = RadialSlot.open(path: "/Applications/Silindi.app")
                let layout = RadialMenuLayout(slots: [.action(.island), .action(.switcher), .action(.windowLeft),
                                                      safari, gone])
                let granted = layout.usableSlots(hasAccessibility: true) { $0 != "/Applications/Silindi.app" }
                try expect(granted == [.action(.island), .action(.switcher), .action(.windowLeft), safari],
                           "A granted ring lost slices, or kept a deleted application: \(granted)")
                let denied = layout.usableSlots(hasAccessibility: false) { _ in true }
                try expect(!denied.contains(.action(.switcher)) && !denied.contains(.action(.windowLeft)),
                           "A slice that needs Accessibility survived without it")
                try expect(denied.contains(safari), "Opening an application was wrongly tied to Accessibility")
                let nothing = RadialMenuLayout(slots: [gone]).usableSlots(hasAccessibility: true) { _ in false }
                try expect(!nothing.isEmpty, "A ring of deleted applications opened empty")
                try expect(!RadialAction.island.requiresAccessibility && !RadialAction.settings.requiresAccessibility,
                           "MacB's own panels claimed to need Accessibility")
                try expect(safari.title == "Safari" && RadialSlot.open(path: "/Users/x/Notlar").title == "Notlar",
                           "A slice's name was not taken from what it opens")
            }),
            ("RadialMenu: a stored ring is clamped on the way back in, old shape included", {
                let tooMany = RadialMenuLayout(actions: Array(repeating: .island, count: 30))
                try expect(tooMany.slots.count == RadialMenuGeometry.maximumSlices,
                           "A ring with thirty slices was allowed")
                try expect(RadialMenuLayout(slots: []).slots.count == 1, "An empty ring was allowed")
                let encoded = try JSONEncoder().encode(RadialMenuLayout(actions: Array(repeating: .shelf, count: 30)))
                let decoded = try JSONDecoder().decode(RadialMenuLayout.self, from: encoded)
                try expect(decoded.slots.count == RadialMenuGeometry.maximumSlices,
                           "Decoding skipped the clamp that encoding respected")
                // A ring saved before slices could open things.
                let legacy = #"{"actions":["clipboard","settings"]}"#.data(using: .utf8)!
                let migrated = try JSONDecoder().decode(RadialMenuLayout.self, from: legacy)
                try expect(migrated.slots == [.action(.clipboard), .action(.settings)],
                           "A ring saved in the old shape was lost: \(migrated.slots)")
                let mixed = RadialMenuLayout(slots: [.action(.island), .open(path: "/Applications/Safari.app")])
                let roundTrip = try JSONDecoder().decode(RadialMenuLayout.self, from: JSONEncoder().encode(mixed))
                try expect(roundTrip == mixed, "An application slice did not survive being saved")
            }),
            ("RadialMenu: an application with its own ring gets it, every other gets the general one", {
                let general = RadialMenuLayout.default
                let finder = RadialMenuLayout(actions: [.shelf])
                let perApp = ["com.apple.finder": finder]
                try expect(RadialMenuProfiles.layout(for: "com.apple.finder", standard: general, perApp: perApp) == finder,
                           "Finder did not get its own ring")
                try expect(RadialMenuProfiles.layout(for: "com.apple.Safari", standard: general, perApp: perApp) == general,
                           "An application without a ring got someone else's")
                try expect(RadialMenuProfiles.layout(for: nil, standard: general, perApp: perApp) == general,
                           "No frontmost application broke the ring")
            }),
            ("LidBlurLiveness: a hinge that goes quiet takes the blur down with it", {
                var liveness = LidBlurLiveness()
                liveness.sawReading(at: 10)
                try expect(!liveness.isStalled(at: 10 + LidBlurLiveness.stallTimeout),
                           "The blur came off exactly on the timeout rather than past it")
                try expect(liveness.isStalled(at: 10 + LidBlurLiveness.stallTimeout + 0.1),
                           "A silent hinge left the whole screen blurred")
                try expect(LidBlurLiveness.stallTimeout > 1,
                           "The timeout was tight enough for one late reading to clear the screen")
                liveness.reset()
                try expect(!liveness.isStalled(at: 1_000),
                           "A blur that was never asked for reported itself as stalled")
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
