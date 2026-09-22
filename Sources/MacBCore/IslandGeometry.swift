import CoreGraphics
import Foundation

/// Panel sizing rules shared by the controller and the tests.
///
/// Everything here is derived from the display and from how much content is
/// actually present, so an empty section never reserves vertical space.
public enum IslandGeometry {
    public static let horizontalPadding: CGFloat = 20
    public static let gap: CGFloat = 12
    public static let navigationHeight: CGFloat = 40
    public static let topPadding: CGFloat = 10
    public static let bottomPadding: CGFloat = 16

    /// Every widget shares one height; size changes width only, as in the reference layout.
    ///
    /// Kept tight on purpose: a card that reserves room its content never uses
    /// reads as empty, and the strip is the first thing the panel shows.
    public static let widgetHeight: CGFloat = 100

    /// Narrowest a grid unit may become before the strip drops to fewer units.
    /// A small widget is one unit, medium two, wide four.
    public static let minimumColumnWidth: CGFloat = 76
    public static let maximumColumns = 16
    public static let minimumColumns = 2

    /// The panel follows its content. This fraction is only a ceiling for a full strip.
    public static let expandedWidthFraction: CGFloat = 0.82
    public static let navigationMinimumWidth: CGFloat = 360
    public static let displayMargin: CGFloat = 48
    public static let preferredColumnWidth: CGFloat = 84

    public static func expandedWidth(screenWidth: CGFloat) -> CGFloat {
        let usable = max(240, screenWidth - displayMargin)
        return min(usable, screenWidth * expandedWidthFraction)
    }

    /// Width of a widget strip with `unitCount` occupied grid units. Empty and
    /// short strips no longer inherit the width of a full dashboard.
    public static func gridWidth(unitCount: Int, screenWidth: CGFloat) -> CGFloat {
        let maximum = expandedWidth(screenWidth: screenWidth)
        let usableColumns = max(1, columns(forWidth: maximum))
        let columns = min(usableColumns, max(1, unitCount))
        let content = CGFloat(columns) * preferredColumnWidth + CGFloat(max(0, columns - 1)) * gap
        return min(maximum, max(min(navigationMinimumWidth, maximum), content + horizontalPadding * 2))
    }

    /// Applies the common display bounds to a section-specific preferred width.
    public static func sectionWidth(_ preferred: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let maximum = expandedWidth(screenWidth: screenWidth)
        return min(maximum, max(min(navigationMinimumWidth, maximum), preferred))
    }

    public static func columns(forWidth width: CGFloat) -> Int {
        let content = width - horizontalPadding * 2
        guard content > 0 else { return minimumColumns }
        let fitted = Int(floor((content + gap) / (minimumColumnWidth + gap)))
        return max(minimumColumns, min(maximumColumns, fitted))
    }

    public static func columnWidth(forWidth width: CGFloat, columns: Int) -> CGFloat {
        let count = CGFloat(max(1, columns))
        let content = width - horizontalPadding * 2
        return max(0, (content - gap * (count - 1)) / count)
    }

    /// Width of a widget spanning `span` columns, including the gaps it swallows.
    public static func widgetWidth(columnWidth: CGFloat, span: Int) -> CGFloat {
        let count = CGFloat(max(1, span))
        return columnWidth * count + gap * (count - 1)
    }

    /// Height of the home strip for the given rows. Returns zero when there is nothing to show.
    public static func gridHeight(rows: [IslandWidgetRow]) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        return widgetHeight * CGFloat(rows.count) + gap * CGFloat(rows.count - 1)
    }

    /// The whole open island while a conversation runs. There is no navigation
    /// row: the sections are one step away once the conversation ends, and a
    /// row of house and grid icons under a voice says the wrong thing.
    ///
    /// At rest it is the strip beside the camera and a sliver under it — a
    /// wider notch with an orb on one side and a word on the other. The text
    /// field appears only while the pointer is over the island or the user is
    /// typing; subtitles and a question add themselves below.
    public static func assistantPanelHeight(cameraHeight: CGFloat, showsInput: Bool,
                                            showsDetail: Bool, hasConfirmation: Bool) -> CGFloat {
        let top = cameraHeight > 0 ? cameraHeight : assistantPresenceTop + assistantPresenceHeight
        var parts: [CGFloat] = []
        if showsInput { parts.append(assistantInputHeight) }
        if showsDetail { parts.append(captionHeight) }
        if hasConfirmation { parts.append(assistantConfirmationHeight) }
        guard !parts.isEmpty else { return top + assistantRestBottom }
        return top + assistantSpacing + parts.reduce(0, +)
            + CGFloat(parts.count - 1) * assistantSpacing + assistantBodyBottom
    }

    /// Rounder when it is only a strip, so the bottom corners never reach
    /// higher than the strip is tall.
    public static func assistantPanelRadius(hasBody: Bool) -> CGFloat { hasBody ? 20 : 14 }

    public static let assistantInputHeight: CGFloat = 30
    public static let assistantPresenceTop: CGFloat = 8
    public static let assistantRestBottom: CGFloat = 6
    public static let assistantBodyBottom: CGFloat = 12

    /// The orb-and-word row, only on displays without a notch to sit beside.
    public static let assistantPresenceHeight: CGFloat = 24
    /// Two lines of subtitles at most, for anyone who wants to read along.
    public static let captionHeight: CGFloat = 30
    public static let assistantConfirmationHeight: CGFloat = 88
    public static let assistantSpacing: CGFloat = 6

    /// Room the status word gets beside the notch. "internette arıyor…" is the
    /// longest common one; anything longer truncates and shows in full on hover.
    public static let assistantEarText: CGFloat = 104
    /// Clearance between an ear's content and the camera housing.
    public static let assistantEarGap: CGFloat = 12

    /// Without a notch: narrow, a badge.
    public static let assistantWidth: CGFloat = 300
    /// Wider when it asks for permission so the question can breathe instead of
    /// becoming a legal sentence squeezed into a badge.
    public static let assistantConfirmationWidth: CGFloat = 392

    /// With a notch the panel has to be wide enough that each strip beside the
    /// camera holds its content.
    public static func assistantWidth(hasConfirmation: Bool, notchWidth: CGFloat = 0) -> CGFloat {
        let resting = notchWidth > 0
            ? notchWidth + 2 * (assistantEarText + assistantEarGap + horizontalPadding)
            : assistantWidth
        return max(resting, hasConfirmation ? assistantConfirmationWidth : 0)
    }

    /// Width of one strip beside the camera, edge padding and clearance
    /// removed: what the orb or the status word actually gets.
    public static func assistantEarContentWidth(panelWidth: CGFloat, notchWidth: CGFloat) -> CGFloat {
        max(0, (panelWidth - notchWidth) / 2 - horizontalPadding - assistantEarGap)
    }

    /// The morning briefing: a greeting, a row of chips when there is anything
    /// worth a chip, and the two buttons under them.
    ///
    /// It used to reserve a line's height per spoken sentence, which meant a
    /// card of three short facts opened a panel with an empty half. The chips
    /// sit on one row whatever they say, so the height is now two fixed rows
    /// and an optional one.
    public static func briefingHeight(chipCount: Int) -> CGFloat {
        let greeting: CGFloat = 32
        let chips: CGFloat = chipCount > 0 ? 8 + 26 : 0
        let actions: CGFloat = 8 + 28
        return greeting + chips + actions
    }

    /// Narrower than it was: chips are short, and a wide card of short chips is
    /// mostly gap.
    public static let briefingWidth: CGFloat = 380

    /// The card a background job leaves behind: what it found, then a row per
    /// thing waiting for a yes.
    public static func agentHeight(reportLines: Int, proposals: Int) -> CGFloat {
        let header: CGFloat = 30
        let report: CGFloat = 8 + CGFloat(min(3, max(1, reportLines))) * 16
        let rows: CGFloat = proposals > 0 ? CGFloat(min(3, proposals)) * 34 + 8 : 0
        let actions: CGFloat = 8 + 28
        return header + report + rows + actions
    }

    public static let agentWidth: CGFloat = 520

    public static func expandedHeight(bodyHeight: CGFloat, navigationInEars: Bool = false) -> CGFloat {
        // Beside a camera the tabs sit in its ears, in the row the camera
        // already takes, and the body starts straight under it.
        if navigationInEars { return topPadding + max(bodyHeight, 0) + bottomPadding }
        guard bodyHeight > 0 else { return navigationHeight + topPadding + bottomPadding }
        return navigationHeight + gap + bodyHeight + topPadding + bottomPadding
    }

    /// Room each ear needs for its half of the navigation: five tabs on the
    /// left, three tools on the right, with the panel's own margin.
    public static let earNavigationWidth: CGFloat = 240

    /// The narrowest an open panel may be beside a camera `cameraWidth` wide,
    /// so the tabs always fit in its ears.
    public static func expandedMinimumWidth(cameraWidth: CGFloat) -> CGFloat {
        cameraWidth > 0 ? cameraWidth + 2 * earNavigationWidth : navigationMinimumWidth
    }

    /// The home player: a large cover beside the title, a progress bar and
    /// the transport.
    public static let playerHeight: CGFloat = 132
    public static let playerWidth: CGFloat = 640
    /// Three graphs over two.
    public static let statsHeight: CGFloat = 272
    public static let statsWidth: CGFloat = 680

    /// Body heights for the sections that are not the widget strip.
    /// Each one reports what its current state actually draws, so nothing is clipped
    /// and an empty section still leaves room for its own empty message.
    public static let dropTargetHeight: CGFloat = 148
    /// The hover strip: one compact line of live status, never a second panel.
    public static let peekHeight: CGFloat = 44
    public static let peekMaximumWidth: CGFloat = 560

    /// A drop needs two targets, not the whole strip, so the panel narrows while files hover.
    public static func dropWidth(screenWidth: CGFloat) -> CGFloat {
        let usable = max(240, screenWidth - displayMargin)
        return min(usable, min(620, max(460, screenWidth * 0.40)))
    }
    public static let timerHeight: CGFloat = 132
    public static let emptyActionHeight: CGFloat = 64
    public static let filterRowHeight: CGFloat = 28
    public static let clipboardCardHeight: CGFloat = 104
    public static let clipboardCardWidth: CGFloat = 132
    public static let emptyMessageHeight: CGFloat = 20
    public static let launcherTileHeight: CGFloat = 74
    public static let fileRowHeight: CGFloat = 32
    /// A locked section draws its own unlock panel, so it reserves that instead of its content.
    public static let lockedSectionHeight: CGFloat = 112

    /// The seven clipboard filters plus the delete button need this much room to
    /// sit on one line. Below it they scroll, which is why it is a floor and not
    /// a requirement.
    public static let clipboardFilterRowWidth: CGFloat = 690

    /// Width of the clipboard section: wide enough for the filter row, then as
    /// many cards as fit, then the panel ceiling.
    public static func clipboardWidth(itemCount: Int, screenWidth: CGFloat) -> CGFloat {
        let cards = CGFloat(min(6, max(0, itemCount)))
        let gallery = cards * (clipboardCardWidth + 10) + horizontalPadding * 2
        return sectionWidth(max(clipboardFilterRowWidth, gallery), screenWidth: screenWidth)
    }

    /// Filters, search and one gallery row. The section used to count only the
    /// filters and cards, so the search field ate the bottom of the cards.
    public static func clipboardHeight(isEmpty: Bool) -> CGFloat {
        _ = isEmpty
        let searchHeight: CGFloat = 26
        return filterRowHeight + gap + searchHeight + gap + clipboardCardHeight + 2
    }

    /// Quick access is a single scrolling row of pinned tiles, so its height is
    /// one tile whether the user pinned two apps or twenty. The add tile is
    /// always present, which is why an empty list is not a special case.
    public static func launcherHeight() -> CGFloat { launcherTileHeight }

    public static let launcherTileWidth: CGFloat = 74
    public static let launcherTileGap: CGFloat = 10
    /// Width of the quick-access section: the tiles the user pinned plus the add
    /// tile, and no further. Two pinned apps must not open a panel sized for
    /// twenty, which is the whole point of dropping the application library.
    public static func launcherWidth(itemCount: Int, screenWidth: CGFloat) -> CGFloat {
        let tiles = CGFloat(max(0, itemCount) + 1)
        let content = tiles * launcherTileWidth + (tiles - 1) * launcherTileGap
        let ideal = content + horizontalPadding * 2
        return sectionWidth(ideal, screenWidth: screenWidth)
    }

    public static func fileStripHeight(rows: Int) -> CGFloat {
        guard rows > 0 else { return emptyActionHeight }
        return min(4, CGFloat(rows)) * fileRowHeight + CGFloat(min(4, rows) - 1) * 6 + 26
    }

    /// The widget library, which opens under the strip while editing.
    ///
    /// It is a fixed shelf rather than a grid that grows with the catalog: a
    /// library tall enough to list fifteen widgets at once would push the panel
    /// past the bottom of the screen, so it scrolls sideways instead.
    public static let libraryCardHeight: CGFloat = 78
    public static let libraryCardWidth: CGFloat = 196
    public static let libraryCardGap: CGFloat = 10
    public static let libraryMinimumWidth: CGFloat = 668

    public static func libraryHeight() -> CGFloat {
        filterRowHeight + gap + libraryCardHeight
    }

    /// Home is normally as wide as its widgets. While the library is open it
    /// also has to hold the category pills and at least three cards, otherwise
    /// browsing happens through a keyhole.
    public static func homeWidth(unitCount: Int, isEditing: Bool, screenWidth: CGFloat) -> CGFloat {
        let grid = gridWidth(unitCount: unitCount, screenWidth: screenWidth)
        guard isEditing else { return grid }
        return max(grid, sectionWidth(libraryMinimumWidth, screenWidth: screenWidth))
    }

    public static func homeHeight(rows: [IslandWidgetRow], isEditing: Bool) -> CGFloat {
        let grid = gridHeight(rows: rows)
        guard isEditing else { return grid }
        return grid + (grid > 0 ? gap : 0) + libraryHeight()
    }

    /// Collapsed width. Matches the hardware notch when the display reports one.
    public static func collapsedWidth(notchWidth: CGFloat?, indicatorWidth: CGFloat) -> CGFloat {
        let base = notchWidth ?? 190
        return max(base, indicatorWidth)
    }
}
