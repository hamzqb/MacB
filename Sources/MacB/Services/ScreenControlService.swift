import AppKit
import ApplicationServices
import Carbon
import MacBCore

/// Small things on screen, done on the Mac: press a button, type into a field,
/// send a shortcut, pick a menu item.
///
/// Everything goes through the Accessibility API — the same one VoiceOver
/// uses — so the assistant finds a control by what it is called, not by
/// looking at pixels. Nothing is captured, nothing is sent anywhere, and it
/// costs nothing.
///
/// What it will not do is the point of most of this file. It never acts while
/// the screen is locked: MacB does not unlock the Mac and never types at the
/// login window. It never types while a password field anywhere has the
/// keyboard (macOS's secure input), never into a password field, and never
/// into a password manager. Those are refusals, not confirmations: there is
/// no way to talk it into them.
@MainActor final class ScreenControlService {
    struct Control {
        let element: AXUIElement
        let role: String
        let label: String
        let value: String?
        let frame: CGRect?
    }

    enum Failure: LocalizedError {
        case noAccessibility
        case locked
        case secureInput
        case protectedApp(String)
        case noApp
        case notFound(String)
        case secureField
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noAccessibility:
                return "Erişilebilirlik izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Erişilebilirlik'ten MacB'yi aç."
            case .locked: return "Ekran kilitli; kilitliyken hiçbir şeye dokunmam."
            case .secureInput: return "Şu an bir parola alanı klavyeyi tutuyor; o sırada yazı ya da tuş göndermem."
            case .protectedApp(let name): return "\(name) bir parola uygulaması; ona dokunmam."
            case .noApp: return "Önde bir uygulama yok. MacB'nin kendi penceresi öndeyse önce hedef uygulamaya geç."
            case .notFound(let target): return "Ekranda “\(target)” diye bir şey bulamadım."
            case .secureField: return "Bu bir parola alanı; parolayı sen yaz."
            case .failed(let message): return message
            }
        }
    }

    /// Apps whose windows are never touched, whatever is asked.
    private static let protectedBundles: Set<String> = [
        "com.apple.loginwindow", "com.apple.SecurityAgent", "com.apple.keychainaccess", "com.apple.Passwords",
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.lastpass.LastPass", "com.dashlane.dashlanephonefinal", "in.sinew.Enpass-Desktop"
    ]

    private static let interactiveRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXTextField",
        "AXTextArea", "AXComboBox", "AXLink", "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXSegment"
    ]

    private static let roleNames: [String: String] = [
        "AXButton": "button", "AXCheckBox": "checkbox", "AXRadioButton": "option", "AXPopUpButton": "popup",
        "AXMenuButton": "menu", "AXTextField": "field", "AXTextArea": "text area", "AXComboBox": "field",
        "AXLink": "link", "AXSlider": "slider", "AXIncrementor": "stepper",
        "AXDisclosureTriangle": "disclosure", "AXSegment": "segment", "AXMenuItem": "menu item"
    ]

    // MARK: - Reading

    /// The controls in the front window, named as the user would name them.
    func controls(limit: Int = 60) throws -> (app: String, window: String, controls: [Control], menus: [String]) {
        let target = try frontApp(forTyping: false)
        let app = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1.0)
        // Chromium and Electron build their tree only for assistive apps
        // that ask; this is how one asks.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let window: AXUIElement = Self.attribute(app, kAXFocusedWindowAttribute)
                ?? Self.attribute(app, kAXMainWindowAttribute) else {
            throw Failure.failed("\(target.localizedName ?? "Uygulama") için açık pencere yok.")
        }
        let found = Self.collect(in: window, limit: limit)
        let menus = Self.menuTitles(app)
        return (target.localizedName ?? "", Self.string(window, kAXTitleAttribute) ?? "", found, menus)
    }

    // MARK: - Acting

    /// Presses the control called `target`. "Dosya > Kaydet" walks the menu bar.
    func press(_ target: String, role: String? = nil) throws -> String {
        let app = try frontApp(forTyping: false)
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 1.0)
        if target.contains(">") { return try pressMenu(path: target, in: element) }
        guard let window: AXUIElement = Self.attribute(element, kAXFocusedWindowAttribute)
                ?? Self.attribute(element, kAXMainWindowAttribute),
              let control = Self.best(Self.collect(in: window, limit: 400), matching: target, role: role) else {
            throw Failure.notFound(target)
        }
        highlight(control)
        if ["AXTextField", "AXTextArea", "AXComboBox"].contains(control.role) {
            AXUIElementSetAttributeValue(control.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            return "Alana geçildi: \(control.label)"
        }
        if AXUIElementPerformAction(control.element, kAXPressAction as CFString) == .success {
            return "Basıldı: \(control.label)"
        }
        // Some controls answer only to a real click.
        guard let frame = control.frame else { throw Failure.failed("“\(control.label)” basılamadı.") }
        Self.click(at: CGPoint(x: frame.midX, y: frame.midY))
        return "Tıklandı: \(control.label)"
    }

    /// Types `text` where the cursor is, or into the field called `field`.
    func type(_ text: String, into field: String?) throws -> String {
        let app = try frontApp(forTyping: true)
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 1.0)
        if let field, !field.isEmpty {
            guard let window: AXUIElement = Self.attribute(element, kAXFocusedWindowAttribute),
                  let control = Self.best(Self.collect(in: window, limit: 400), matching: field,
                                          role: nil, preferFields: true) else {
                throw Failure.notFound(field)
            }
            guard Self.string(control.element, kAXSubroleAttribute) != "AXSecureTextField" else { throw Failure.secureField }
            highlight(control)
            AXUIElementSetAttributeValue(control.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        // Whatever ended up with the keyboard, checked again: a field that
        // hides what is typed into it is a password field.
        if let focused: AXUIElement = Self.attribute(element, kAXFocusedUIElementAttribute) {
            guard Self.string(focused, kAXSubroleAttribute) != "AXSecureTextField" else { throw Failure.secureField }
        }
        try checkSecureInput()
        let clipped = String(text.prefix(2_000))
        Self.typeUnicode(clipped, to: app.processIdentifier)
        return "Yazıldı (\(clipped.count) karakter)"
    }

    /// Sends a shortcut or a key, e.g. "cmd+s", "return", "cmd+shift+t".
    func press(keys combo: String, times: Int = 1) throws -> String {
        let app = try frontApp(forTyping: true)
        try checkSecureInput()
        guard let (code, flags) = Self.parse(combo) else { throw Failure.failed("“\(combo)” tanımadığım bir tuş.") }
        for _ in 0..<max(1, min(20, times)) {
            Self.post(key: code, flags: flags, to: app.processIdentifier)
        }
        return "Gönderildi: \(combo)"
    }

    // MARK: - Guards

    /// The app the user is working in — never MacB, never a password app,
    /// never while the screen is locked.
    private func frontApp(forTyping: Bool) throws -> NSRunningApplication {
        guard AXIsProcessTrusted() else { throw Failure.noAccessibility }
        if Self.screenIsLocked { throw Failure.locked }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw Failure.noApp }
        if let bundle = app.bundleIdentifier, Self.protectedBundles.contains(bundle) {
            throw Failure.protectedApp(app.localizedName ?? bundle)
        }
        if forTyping { try checkSecureInput() }
        return app
    }

    private func checkSecureInput() throws {
        if Self.screenIsLocked { throw Failure.locked }
        if IsSecureEventInputEnabled() { throw Failure.secureInput }
    }

    static var screenIsLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        return session["CGSSessionScreenIsLocked"] as? Bool == true
            || session[kCGSessionOnConsoleKey as String] as? Bool == false
    }

    // MARK: - Tree

    private static func collect(in root: AXUIElement, limit: Int) -> [Control] {
        var result: [Control] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        let deadline = Date().addingTimeInterval(1.2)
        while !queue.isEmpty, result.count < limit, visited < 2_500, Date() < deadline {
            let (element, depth) = queue.removeFirst()
            visited += 1
            let role = string(element, kAXRoleAttribute) ?? ""
            if interactiveRoles.contains(role), (attribute(element, kAXEnabledAttribute) as Bool?) != false {
                let label = label(of: element)
                if !label.isEmpty {
                    let secure = string(element, kAXSubroleAttribute) == "AXSecureTextField"
                    let isField = ["AXTextField", "AXTextArea", "AXComboBox"].contains(role)
                    let value = isField && !secure ? string(element, kAXValueAttribute).map { String($0.prefix(80)) } : nil
                    result.append(Control(element: element, role: role, label: label,
                                          value: secure ? "(parola alanı)" : value, frame: frame(of: element)))
                }
            }
            guard depth < 14, let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) else { continue }
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return result
    }

    private static func label(of element: AXUIElement) -> String {
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, "AXPlaceholderValue", kAXHelpAttribute] {
            if let text = string(element, name)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return String(text.prefix(80))
            }
        }
        if let title: AXUIElement = attribute(element, kAXTitleUIElementAttribute),
           let text = string(title, kAXValueAttribute), !text.isEmpty { return String(text.prefix(80)) }
        let role = string(element, kAXRoleAttribute)
        if role == "AXLink" || role == "AXButton",
           let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) {
            let text = children.compactMap { string($0, kAXValueAttribute) }.joined(separator: " ")
            return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        }
        return ""
    }

    /// The closest name: exact beats prefix beats contains; a field wins ties
    /// when typing, a button otherwise.
    private static func best(_ controls: [Control], matching target: String, role: String?,
                             preferFields: Bool = false) -> Control? {
        let wanted = normalise(target)
        guard !wanted.isEmpty else { return nil }
        let roleWanted = role.map(normalise)
        var bestScore = 0
        var best: Control?
        for control in controls {
            if let roleWanted, !roleWanted.isEmpty,
               normalise(roleNames[control.role] ?? control.role) != roleWanted { continue }
            let name = normalise(control.label)
            var score = name == wanted ? 30 : name.hasPrefix(wanted) ? 20 : name.contains(wanted) ? 10 : 0
            guard score > 0 else { continue }
            let isField = ["AXTextField", "AXTextArea", "AXComboBox"].contains(control.role)
            if isField == preferFields { score += 2 }
            if score > bestScore { bestScore = score; best = control }
        }
        return best
    }

    static func normalise(_ text: String) -> String {
        text.replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "İ", with: "i")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    // MARK: - Menus

    private static func menuTitles(_ app: AXUIElement) -> [String] {
        guard let bar: AXUIElement = attribute(app, kAXMenuBarAttribute),
              let items: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else { return [] }
        return items.dropFirst().compactMap { string($0, kAXTitleAttribute) }.filter { !$0.isEmpty }
    }

    private func pressMenu(path: String, in app: AXUIElement) throws -> String {
        let parts = path.split(separator: ">").map { Self.normalise(String($0)) }.filter { !$0.isEmpty }
        guard !parts.isEmpty, var current: AXUIElement = Self.attribute(app, kAXMenuBarAttribute) else {
            throw Failure.notFound(path)
        }
        for (index, part) in parts.enumerated() {
            var children: [AXUIElement] = Self.attribute(current, kAXChildrenAttribute) ?? []
            // A menu bar item holds one AXMenu, which holds the items.
            if children.count == 1, Self.string(children[0], kAXRoleAttribute) == "AXMenu" {
                children = Self.attribute(children[0], kAXChildrenAttribute) ?? []
            }
            guard let next = children.first(where: {
                let title = Self.normalise(Self.string($0, kAXTitleAttribute) ?? "")
                return title == part || title.hasPrefix(part)
            }) ?? children.first(where: { Self.normalise(Self.string($0, kAXTitleAttribute) ?? "").contains(part) })
            else { throw Failure.notFound(path) }
            if index == parts.count - 1 {
                guard (Self.attribute(next, kAXEnabledAttribute) as Bool?) != false else {
                    throw Failure.failed("“\(path)” şu an seçilemiyor.")
                }
                AXUIElementPerformAction(next, kAXPressAction as CFString)
                return "Menüden seçildi: \(path)"
            }
            current = next
        }
        throw Failure.notFound(path)
    }

    // MARK: - Input

    private func highlight(_ control: Control) {
        if let frame = control.frame { AgentFocusOverlay.shared.highlight(topLeftRect: frame) }
    }

    private static func typeUnicode(_ text: String, to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for line in text.components(separatedBy: "\n").enumerated() {
            if line.offset > 0 { post(key: CGKeyCode(kVK_Return), flags: [], to: pid) }
            let characters = Array(line.element.utf16)
            var index = 0
            while index < characters.count {
                let chunk = Array(characters[index..<min(index + 16, characters.count)])
                for down in [true, false] {
                    guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                    event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                    event.postToPid(pid)
                }
                index += 16
                usleep(6_000)
            }
        }
    }

    private static func post(key: CGKeyCode, flags: CGEventFlags, to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            event.postToPid(pid)
        }
        usleep(8_000)
    }

    private static func click(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }

    /// "cmd+shift+t" → the T key with command and shift.
    static func parse(_ combo: String) -> (CGKeyCode, CGEventFlags)? {
        let parts = combo.lowercased().replacingOccurrences(of: " ", with: "")
            .split(separator: "+").map(String.init)
        guard let keyName = parts.last else { return nil }
        var flags: CGEventFlags = []
        for modifier in parts.dropLast() {
            switch modifier {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default: return nil
            }
        }
        guard let code = keyCodes[keyName] else { return nil }
        return (CGKeyCode(code), flags)
    }

    private static let keyCodes: [String: Int] = {
        var map: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
            "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
            "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "space": kVK_Space,
            "escape": kVK_Escape, "esc": kVK_Escape, "delete": kVK_Delete, "backspace": kVK_Delete,
            "forwarddelete": kVK_ForwardDelete, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "home": kVK_Home, "end": kVK_End,
            "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
            ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal,
            "/": kVK_ANSI_Slash, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                            kVK_F11, kVK_F12]
        for (index, code) in functionKeys.enumerated() { map["f\(index + 1)"] = code }
        return map
    }()

    // MARK: - AX helpers

    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) }

    /// Global, top-left-origin frame, as the Accessibility API reports it.
    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
        // swiftlint:disable:next force_cast
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
}
