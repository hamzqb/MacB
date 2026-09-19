import AppKit
import ApplicationServices
import Carbon

/// Reads the text selected in the application in front, and can put a
/// replacement in its place.
///
/// The ring never takes focus, so when a slice fires the application the user
/// was working in is still frontmost with its selection intact. The text is
/// read through Accessibility first, which touches nothing. Only when an
/// application does not expose its selection that way (web content in some
/// browsers, Electron editors) is ⌘C sent to that one application, exactly as
/// if the user had pressed it — to that process only, never to the system as
/// a whole, never to a password field, and never while the screen is locked.
@MainActor final class SelectedTextService {
    struct Selection {
        let text: String
        /// The focused element the text came from, when it was read through
        /// Accessibility. Only then can a replacement be written back.
        let element: AXUIElement?
        let appName: String
        /// Whether a result can be put back where the selection was. Asked
        /// once, when the text is read: it is an IPC round trip to the other
        /// application, which a view redrawing must not wait on.
        let canReplace: Bool
    }

    enum Failure: Error {
        case noAccessibility
        case nothingSelected
        case secureField

        var message: String {
            switch self {
            case .noAccessibility: return "Seçili metni okumak için Erişilebilirlik izni gerekiyor."
            case .nothingSelected: return "Seçili metin yok. Önce bir metin seç."
            case .secureField: return "Parola alanındaki metin okunmaz."
            }
        }
    }

    func read() async -> Result<Selection, Failure> {
        guard AXIsProcessTrusted() else { return .failure(.noAccessibility) }
        guard !Self.screenIsLocked else { return .failure(.nothingSelected) }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return .failure(.nothingSelected)
        }
        let name = app.localizedName ?? "Uygulama"
        let focused = focusedElement(of: app.processIdentifier)
        if let focused, isSecure(focused) { return .failure(.secureField) }
        if let focused,
           let text = axAttribute(focused, kAXSelectedTextAttribute) as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .success(Selection(text: text, element: focused, appName: name,
                                      canReplace: Self.isSelectionSettable(focused)))
        }
        // A secure-input field anywhere means a password is being typed; no
        // synthetic keystroke goes near it.
        guard !IsSecureEventInputEnabled() else { return .failure(.secureField) }
        guard let copied = await copyViaCommandC(to: app.processIdentifier) else {
            return .failure(.nothingSelected)
        }
        return .success(Selection(text: copied, element: nil, appName: name, canReplace: false))
    }

    /// Puts `text` in place of the selection it was read from.
    ///
    /// Only if that same text is still selected. The panel stays open while
    /// the user reads, and if they have since moved the cursor or selected
    /// something else, writing now would overwrite the wrong words.
    func replace(_ selection: Selection, with text: String) -> Bool {
        guard let element = selection.element, selection.canReplace, !Self.screenIsLocked,
              let current = axAttribute(element, kAXSelectedTextAttribute) as? String,
              current == selection.text else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    private static func isSelectionSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    /// Nothing is read from, or typed into, a locked session.
    static var screenIsLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    private func focusedElement(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        guard let value = axAttribute(app, kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.4)
        return element
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        (axAttribute(element, kAXSubroleAttribute) as? String) == (kAXSecureTextFieldSubrole as String)
    }

    /// Sends ⌘C to one process and waits briefly for the pasteboard to change.
    ///
    /// Anything a password manager marks as concealed is refused, the same
    /// rule the clipboard history follows. Whatever was on the clipboard
    /// before is put back afterwards, so borrowing it to read a selection
    /// does not cost the user what they had copied.
    private func copyViaCommandC(to pid: pid_t) async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = Self.snapshot(pasteboard)
        defer { if pasteboard.changeCount != saved.changeCount { Self.restore(saved, to: pasteboard) } }
        let before = saved.changeCount
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = 8
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false) else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if pasteboard.changeCount != before { break }
        }
        guard pasteboard.changeCount != before else { return nil }
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        if pasteboard.types?.contains(concealed) == true { return nil }
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private struct PasteboardSnapshot {
        let changeCount: Int
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        return PasteboardSnapshot(changeCount: pasteboard.changeCount, items: items)
    }

    /// Puts the earlier clipboard back, marked transient so a clipboard
    /// history does not record it a second time.
    private static func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        let items = snapshot.items.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            item.setData(Data(), forType: transient)
            return item
        }
        pasteboard.writeObjects(items)
    }
}
