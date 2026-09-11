import CoreGraphics
import XCTest
@testable import MacBCore

final class IslandWidgetTests: XCTestCase {
    func testRowsNeverExceedTheColumnCount() {
        let layout = IslandWidgetLayout(widgets: [
            IslandWidget(kind: .media, size: .wide, isEnabled: true),
            IslandWidget(kind: .timer, size: .medium, isEnabled: true),
            IslandWidget(kind: .clipboard, size: .medium, isEnabled: true),
            IslandWidget(kind: .weather, size: .small, isEnabled: true)
        ])
        let rows = layout.rows(columns: 4)
        XCTAssertEqual(rows.count, 3)
        for row in rows { XCTAssertLessThanOrEqual(row.usedColumns, 4) }
        XCTAssertEqual(rows[0].widgets.map(\.kind), [.media])
    }

    func testHomeStripStaysOnOneRowOnAWideDisplay() {
        let width = IslandGeometry.expandedWidth(screenWidth: 1512)
        let strip = IslandWidgetLayout(widgets: [
            IslandWidget(kind: .timer, size: .medium, isEnabled: true),
            IslandWidget(kind: .media, size: .wide, isEnabled: true),
            IslandWidget(kind: .quickLaunch, size: .small, isEnabled: true),
            IslandWidget(kind: .calendar, size: .medium, isEnabled: true),
            IslandWidget(kind: .weather, size: .small, isEnabled: true)
        ])
        XCTAssertEqual(strip.rows(columns: IslandGeometry.columns(forWidth: width)).count, 1)
    }

    func testShippedDefaultFillsOneRowOnTheSmallestSupportedDisplay() {
        for screenWidth in [1440, 1512, 1728].map(CGFloat.init) {
            let columns = IslandGeometry.columns(forWidth: IslandGeometry.expandedWidth(screenWidth: screenWidth))
            XCTAssertEqual(IslandWidgetLayout.standard.rows(columns: columns).count, 1)
        }
    }

    func testEveryWidgetInARowSharesOneHeight() {
        let rows = IslandWidgetLayout.standard.rows(columns: 12)
        let expected = IslandGeometry.widgetHeight * CGFloat(rows.count) + IslandGeometry.gap * CGFloat(rows.count - 1)
        XCTAssertEqual(IslandGeometry.gridHeight(rows: rows), expected)
    }

    func testOversizedWidgetIsNarrowedInsteadOfClipped() {
        let layout = IslandWidgetLayout(widgets: [IslandWidget(kind: .media, size: .wide, isEnabled: true)])
        let rows = layout.rows(columns: 2)
        XCTAssertEqual(rows.count, 1)
        XCTAssertLessThanOrEqual(rows[0].widgets[0].size.columns, 2)
    }

    func testDisabledWidgetsReserveNoSpace() {
        var layout = IslandWidgetLayout.standard
        for widget in layout.widgets { layout.setEnabled(id: widget.id, false) }
        XCTAssertTrue(layout.rows(columns: 4).isEmpty)
        XCTAssertEqual(IslandGeometry.gridHeight(rows: []), 0)
    }

    func testReorderingSurvivesASaveAndLoad() throws {
        var layout = IslandWidgetLayout.standard
        let moved = layout.widgets[0]
        layout.move(id: moved.id, to: 3)
        XCTAssertEqual(layout.widgets[3].id, moved.id)
        let restored = try JSONDecoder().decode(IslandWidgetLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(restored, layout)
    }

    func testSavedLayoutRegainsWidgetKindsAddedByANewerBuild() {
        let saved = IslandWidgetLayout(widgets: [IslandWidget(kind: .clipboard, size: .medium, isEnabled: true)])
        let merged = saved.merging()
        XCTAssertEqual(merged.widgets.first?.kind, .clipboard)
        XCTAssertEqual(merged.widgets.count, IslandWidgetKind.allCases.count)
    }

    func testPanelStaysInsideTheDisplayAndKeepsWholeColumns() {
        for screenWidth in [1180, 1512, 1728, 2056].map(CGFloat.init) {
            let width = IslandGeometry.expandedWidth(screenWidth: screenWidth)
            XCTAssertLessThanOrEqual(width, screenWidth - IslandGeometry.displayMargin)
            XCTAssertGreaterThanOrEqual(width, screenWidth * 0.70)
            let columns = IslandGeometry.columns(forWidth: width)
            XCTAssertGreaterThanOrEqual(columns, IslandGeometry.minimumColumns)
            let columnWidth = IslandGeometry.columnWidth(forWidth: width, columns: columns)
            let spanned = IslandGeometry.widgetWidth(columnWidth: columnWidth, span: columns)
            XCTAssertEqual(spanned, width - IslandGeometry.horizontalPadding * 2, accuracy: 0.5)
        }
    }

    func testNarrowDisplayStillRendersEveryEnabledWidget() {
        let width = IslandGeometry.expandedWidth(screenWidth: 1180)
        let layout = IslandWidgetLayout.standard
        let rows = layout.rows(columns: IslandGeometry.columns(forWidth: width))
        XCTAssertEqual(rows.reduce(0) { $0 + $1.widgets.count }, layout.enabledWidgets.count)
        XCTAssertGreaterThan(IslandGeometry.expandedHeight(bodyHeight: IslandGeometry.gridHeight(rows: rows)), 0)
    }

    func testEveryWidgetInTheCatalogIsBrowsable() {
        let layout = IslandWidgetLayout.standard
        XCTAssertEqual(layout.widgets.count, IslandWidgetKind.allCases.count)
        let listed = layout.groups.flatMap(\.widgets).map(\.kind)
        XCTAssertEqual(Set(listed), Set(IslandWidgetKind.allCases))
        XCTAssertEqual(listed.count, IslandWidgetKind.allCases.count)
        for kind in IslandWidgetKind.allCases {
            XCTAssertFalse(kind.title.isEmpty, "\(kind) has no title")
            XCTAssertFalse(kind.summary.isEmpty, "\(kind) has no summary")
            XCTAssertFalse(kind.symbol.isEmpty, "\(kind) has no symbol")
        }
    }

    func testLibraryGroupsAreNeverEmpty() {
        for group in IslandWidgetLayout.standard.groups {
            XCTAssertFalse(group.widgets.isEmpty, "\(group.category) is listed but empty")
        }
    }

    func testAddingFromTheLibraryLandsAtTheEndOfTheStrip() {
        var layout = IslandWidgetLayout.standard
        guard let target = layout.widgets.first(where: { $0.kind == .worldClock }) else {
            return XCTFail("world clock missing from the catalog")
        }
        layout.add(id: target.id)
        XCTAssertEqual(layout.enabledWidgets.last?.kind, .worldClock)
        XCTAssertEqual(layout.enabledWidgets.last?.size, IslandWidgetKind.worldClock.defaultSize)
    }

    func testAddingRestoresTheIntendedSizeAfterAResize() {
        var layout = IslandWidgetLayout.standard
        guard let target = layout.widgets.first(where: { $0.kind == .notes }) else {
            return XCTFail("notes missing from the catalog")
        }
        layout.resize(id: target.id, to: .small)
        layout.add(id: target.id)
        XCTAssertEqual(layout.widgets.first { $0.kind == .notes }?.size, IslandWidgetKind.notes.defaultSize)
    }

    func testSettingsArrowsStepOverHiddenWidgets() {
        var layout = IslandWidgetLayout.standard
        guard let second = layout.enabledWidgets.dropFirst().first else {
            return XCTFail("the shipped strip has fewer than two widgets")
        }
        layout.moveVisible(id: second.id, by: -1)
        XCTAssertEqual(layout.enabledWidgets.first?.id, second.id)
        layout.moveVisible(id: second.id, by: -1)
        XCTAssertEqual(layout.enabledWidgets.first?.id, second.id)
        guard let last = layout.enabledWidgets.last else { return XCTFail("the strip lost its widgets") }
        layout.moveVisible(id: last.id, by: 1)
        XCTAssertEqual(layout.enabledWidgets.last?.id, last.id)
        XCTAssertEqual(layout.widgets.count, IslandWidgetKind.allCases.count)
    }

    func testOpeningTheLibraryGrowsThePanelWithoutMovingTheStrip() {
        let rows = IslandWidgetLayout.standard.rows(columns: 11)
        let closed = IslandGeometry.homeHeight(rows: rows, isEditing: false)
        let open = IslandGeometry.homeHeight(rows: rows, isEditing: true)
        XCTAssertEqual(closed, IslandGeometry.gridHeight(rows: rows))
        XCTAssertEqual(open, closed + IslandGeometry.gap + IslandGeometry.libraryHeight())
    }

    func testLibraryWidensANarrowStripSoCardsAreReadable() {
        let screenWidth: CGFloat = 1440
        let closed = IslandGeometry.homeWidth(unitCount: 1, isEditing: false, screenWidth: screenWidth)
        let open = IslandGeometry.homeWidth(unitCount: 1, isEditing: true, screenWidth: screenWidth)
        XCTAssertGreaterThan(open, closed)
        XCTAssertGreaterThanOrEqual(open, IslandGeometry.libraryCardWidth * 3)
        XCTAssertLessThanOrEqual(open, IslandGeometry.expandedWidth(screenWidth: screenWidth))
    }

    func testLibraryNeverNarrowsAFullStrip() {
        let screenWidth: CGFloat = 1512
        let full = IslandGeometry.homeWidth(unitCount: 16, isEditing: false, screenWidth: screenWidth)
        XCTAssertEqual(IslandGeometry.homeWidth(unitCount: 16, isEditing: true, screenWidth: screenWidth), full)
    }

    func testEmptyStripWithTheLibraryOpenStillReservesTheLibrary() {
        let height = IslandGeometry.homeHeight(rows: [], isEditing: true)
        XCTAssertEqual(height, IslandGeometry.libraryHeight())
        XCTAssertGreaterThan(IslandGeometry.expandedHeight(bodyHeight: height), height)
    }

    func testLevelEventReplacesItsOwnKind() {
        let first = IslandEvent.volume(0.3, isMuted: false)
        let second = IslandEvent.volume(0.4, isMuted: false)
        XCTAssertTrue(second.supersedes(first))
        XCTAssertTrue(second.outranks(first))
    }

    func testQuietEventCannotInterruptALouderOne() {
        let volume = IslandEvent.volume(0.5, isMuted: false)
        let track = IslandEvent.nowPlaying(title: "Kill Bill", artist: "SZA")
        XCTAssertFalse(track.outranks(volume))
        XCTAssertTrue(volume.outranks(track))
        XCTAssertTrue(IslandEvent.batteryLow(8).outranks(volume))
    }

    func testMutingReadsAsMute() {
        let muted = IslandEvent.volume(0.7, isMuted: true)
        XCTAssertEqual(muted.kind, .mute)
        XCTAssertEqual(muted.progress, 0)
        XCTAssertEqual(IslandEvent.volume(0, isMuted: false).kind, .mute)
    }

    func testEventLevelsStayInRange() {
        for raw in [-3.0, 0.0, 0.42, 1.0, 7.5] {
            guard let progress = IslandEvent.volume(raw, isMuted: false).progress else { continue }
            XCTAssertTrue(progress >= 0 && progress <= 1, "Volume \(raw) produced \(progress)")
        }
    }

    func testEventStripIsSizedByItsContent() {
        let short = IslandGeometry.eventWidth(title: "Ses", detail: "40%", hasProgress: true)
        let long = IslandGeometry.eventWidth(title: "Çok uzun bir şarkı adı burada",
                                             detail: "Bir sanatçı", hasProgress: false)
        XCTAssertLessThan(short, long)
        XCTAssertLessThanOrEqual(long, IslandGeometry.peekMaximumWidth)
        XCTAssertGreaterThanOrEqual(short, 220)
    }

    func testQuickAccessWidensByTileNotByDisplay() {
        let two = IslandGeometry.launcherWidth(itemCount: 2, screenWidth: 1440)
        let six = IslandGeometry.launcherWidth(itemCount: 6, screenWidth: 1440)
        let many = IslandGeometry.launcherWidth(itemCount: 40, screenWidth: 1440)
        XCTAssertLessThanOrEqual(two, six)
        XCTAssertLessThan(six, IslandGeometry.expandedWidth(screenWidth: 1440))
        XCTAssertEqual(many, IslandGeometry.expandedWidth(screenWidth: 1440))
        XCTAssertGreaterThanOrEqual(two, IslandGeometry.navigationMinimumWidth)
    }

    func testQuickAccessStaysOneTileRow() {
        let height = IslandGeometry.launcherHeight()
        XCTAssertEqual(height, IslandGeometry.launcherTileHeight)
        let panel = IslandGeometry.expandedHeight(bodyHeight: height)
        XCTAssertGreaterThan(panel, height)
        XCTAssertLessThan(panel, 260)
    }
}
