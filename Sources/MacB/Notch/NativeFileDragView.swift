import AppKit
import SwiftUI

struct NativeFileDragView: NSViewRepresentable {
    var item: ShelfItem
    func makeNSView(context: Context) -> FileDragSourceView {
        let view = FileDragSourceView()
        view.update(item)
        return view
    }
    func updateNSView(_ nsView: FileDragSourceView, context: Context) { nsView.update(item) }
}

final class FileDragSourceView: NSView, NSDraggingSource {
    private var item: ShelfItem?
    private var origin: NSPoint?
    private var dragging = false
    override var isFlipped: Bool { true }

    func update(_ item: ShelfItem) {
        self.item = item
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(item.name + (item.isAvailable ? "" : ", dosyaya erişilemiyor"))
        setAccessibilityHelp("Dosyayı başka bir pencereye sürükleyin. Klavyeyle aktarmak için yanındaki kopyala düğmesini kullanın.")
        toolTip = item.url?.path ?? item.name
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let item else { return }
        let icon = item.url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        icon?.draw(in: NSRect(x: 4, y: 6, width: 23, height: 23), from: .zero, operation: .sourceOver,
                   fraction: item.isAvailable ? 1 : 0.4, respectFlipped: true, hints: nil)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(item.isAvailable ? 0.88 : 0.4),
            .paragraphStyle: paragraph
        ]
        (item.name as NSString).draw(in: NSRect(x: 35, y: 10, width: max(0, bounds.width - 40), height: 20), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) { origin = convert(event.locationInWindow, from: nil) }
    override func mouseUp(with event: NSEvent) { origin = nil }
    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let origin, let item, item.isAvailable, let url = item.url else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - origin.x, point.y - origin.y) >= 4 else { return }
        let dragItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        dragItem.setDraggingFrame(NSRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32), contents: icon)
        dragging = true
        NotificationCenter.default.post(name: Notification.Name("MacBShelfDragBegan"), object: nil)
        let session = beginDraggingSession(with: [dragItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        origin = nil
        NotificationCenter.default.post(name: Notification.Name("MacBShelfDragEnded"), object: nil)
    }
}
