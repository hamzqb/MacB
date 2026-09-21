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

    /// Full expanded panel height: navigation, body, and padding, with empty bodies collapsing away.
    /// The voice assistant: the orb and its line, plus room for what has
    /// been said and for a question waiting to be allowed.
    /// The assistant is a badge until it is asked to be more.
    ///
    /// On its own it is an orb and a word — no keyboard, no subtitles, no
    /// transcript. Each of those appears because the user asked for it, and the
    /// island grows by exactly that much.
    public static func assistantHeight(showsInput: Bool, showsCaptions: Bool,
                                       hasConfirmation: Bool) -> CGFloat {
        let base: CGFloat = 44
        return base
            + (showsInput ? 30 : 0)
            + (showsCaptions ? captionHeight : 0)
            + (hasConfirmation ? 88 : 0)
    }

    /// Two lines of subtitles, for anyone who wants to read along.
    public static let captionHeight: CGFloat = 34

    /// Narrow at rest, wider when it asks for permission so the question can
    /// breathe instead of becoming a legal sentence squeezed into a badge.
    public static let assistantWidth: CGFloat = 300
    public static let assistantConfirmationWidth: CGFloat = 392

    public static func assistantWidth(hasConfirmation: Bool) -> CGFloat {
        hasConfirmation ? assistantConfirmationWidth : assistantWidth
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

    public static func expandedHeight(bodyHeight: CGFloat) -> CGFloat {
        guard bodyHeight > 0 else { return navigationHeight + topPadding + bottomPadding }
        return navigationHeight + gap + bodyHeight + topPadding + bottomPadding
    }

    /// Body heights for the sections that are not the widget strip.
    /// Each one reports what its current state actually draws, so nothing is clipped
    /// and an empty section still leaves room for its own empty message.
    public static let dropTargetHeight: CGFloat = 148
    /// The hover strip: one compact line of live status, never a second panel.
    public static let peekHeight: CGFloat = 44
    public static let peekMaximumWidth: CGFloat = 460

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
