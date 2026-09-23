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
/// Every listing numbers what it found, and a number is the surest way to
/// press something: a name can be read three ways, "3" cannot. The numbers
/// belong to the listing that produced them and are checked against the window
/// before anything is pressed, so a stale number is refused rather than
/// pressing whatever has since moved into that place.
///
/// What it will not do is the point of most of this file. It never acts while
/// the screen is locked: MacB does not unlock the Mac and never types at the
/// login window. It never types while a password field anywhere has the
/// keyboard (macOS's secure input), never into a password field, and never
/// into a password manager. Those are refusals, not confirmations: there is
/// no way to talk it into them.
@MainActor final class ScreenControlService {
    struct Control {
        /// What to call it when asking for this one: stable inside a listing.
        var number: Int
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
        case notFound(String, [String])
        case staleNumber
        case offScreen
        case secureField
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noAccessibility:
                return "Erişilebilirlik izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Erişilebilirlik'ten MacB'yi aç."
            case .locked: return "Ekran kilitli; kilitliyken hiçbir şeye dokunmam."
            case .secureInput: return "Şu an bir parola alanı klavyeyi tutuyor; o sırada yazı ya da tuş göndermem."
            case .protectedApp(let name): return "\(name) bir parola uygulaması; ona dokunmam."
            case .noApp: return "Önde bir uygulama yok. Önce hedef uygulamayı aç."
            case .notFound(let target, let nearby):
                guard !nearby.isEmpty else { return "Ekranda “\(target)” diye bir şey bulamadım." }
                return "Ekranda “\(target)” yok. Şunlar var: " + nearby.joined(separator: ", ")
                    + ". Doğrusunu numarasıyla söyle."
            case .staleNumber:
                return "O numara artık bu pencereye ait değil. screen_controls'ü yeniden çağır."
            case .offScreen: return "O nokta ekranın dışında."
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

    /// Roles that are a control whatever else is true of them.
    private static let interactiveRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXTextField",
        "AXTextArea", "AXComboBox", "AXLink", "AXSlider", "AXIncrementor", "AXDisclosureTriangle",
        "AXSegment", "AXMenuItem", "AXTab", "AXSearchField", "AXToolbarButton", "AXSwitch"
    ]

    /// Roles that are a control only when the application says they can be
    /// pressed. A web page is mostly these: a row that opens a message, an
    /// image that is really a button, a word with a click handler on it.
    private static let pressableRoles: Set<String> = [
        "AXStaticText", "AXImage", "AXGroup", "AXCell", "AXRow", "AXOutlineRow", "AXHeading",
        "AXUnknown", "AXMenuBarItem", "AXList", "AXTextGroup"
    ]

    private static let fieldRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// Parts of a window that are the application's own furniture rather than
    /// what the user is looking at: the toolbar, the tab strip, the menu bar.
    ///
    /// They are read last. A browser's toolbar and tab strip hold a hundred
    /// controls before the page begins, and a listing that stops at eighty
    /// would be all tabs and close buttons — the assistant could see the page
    /// in a screenshot and never find a single thing on it in the list.
    private static let furnitureRoles: Set<String> = ["AXToolbar", "AXTabGroup", "AXMenuBar", "AXRuler"]

    private static let roleNames: [String: String] = [
        "AXButton": "button", "AXCheckBox": "checkbox", "AXRadioButton": "option", "AXPopUpButton": "popup",
        "AXMenuButton": "menu", "AXTextField": "field", "AXTextArea": "text area", "AXComboBox": "field",
        "AXSearchField": "field", "AXLink": "link", "AXSlider": "slider", "AXIncrementor": "stepper",
        "AXDisclosureTriangle": "disclosure", "AXSegment": "segment", "AXTab": "segment",
        "AXMenuItem": "menu item", "AXToolbarButton": "button", "AXSwitch": "checkbox"
    ]

    /// The last listing, so a number means something. Kept only in memory and
    /// only until the next listing replaces it.
    private var listing: [Control] = []
    private var listingApp: pid_t = 0
    private var listedAt = Date.distantPast

    // MARK: - Reading

    /// The controls in the target app's windows, named as the user would name
    /// them and numbered so they can be asked for without ambiguity.
    @discardableResult
    func controls(limit: Int = 80) throws -> (app: String, window: String, controls: [Control], menus: [String]) {
        let target = try targetApp(forTyping: false, activating: false)
        let app = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 2.0)
        let chromium = Self.enableRichTree(app)
        let windows = Self.windows(of: app)
        guard !windows.isEmpty else {
            throw Failure.failed("\(target.localizedName ?? "Uygulama") için açık pencere yok.")
        }
        var sawPage = false
        var found = Self.collect(in: windows, limit: limit, sawPage: &sawPage)
        // Chromium builds the page's half of the tree only once it has been
        // asked, and it takes a moment. Asked and not waited for, the listing
        // is the browser's own toolbar and nothing of the page — which is
        // exactly the case where the assistant could see a button in a
        // screenshot and swear there was none on screen.
        if chromium, !sawPage {
            usleep(500_000)
            found = Self.collect(in: windows, limit: limit, sawPage: &sawPage)
        }
        for index in found.indices { found[index].number = index + 1 }
        listing = found
        listingApp = target.processIdentifier
        listedAt = Date()
        let title = Self.string(windows[0], kAXTitleAttribute) ?? ""
        return (target.localizedName ?? "", title, found, Self.menuTitles(app))
    }

    /// The listing as it was last read, for anything that wants to draw on top
    /// of the screen rather than ask again.
    var lastListing: [Control] { listing }

    // MARK: - Acting

    /// Presses the control called `target`, or the one with that `number`.
    /// "Dosya > Kaydet" walks the menu bar instead.
    func press(_ target: String, role: String? = nil, number: Int? = nil) throws -> String {
        let app = try targetApp(forTyping: false, activating: true)
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 2.0)
        if let number { return try press(control: try control(number: number, of: app)) }
        if target.contains(">") { return try pressMenu(path: target, in: element) }
        let windows = Self.windows(of: element)
        let candidates = Self.collect(in: windows, limit: 400)
        guard let control = Self.best(candidates, matching: target, role: role) else {
            // A name that is nowhere in the window may still be a menu item —
            // "Yeni Sekme" lives in the menu bar, not on screen.
            if let message = try? pressMenu(path: target, in: element) { return message }
            throw Failure.notFound(target, Self.nearest(candidates, to: target))
        }
        return try press(control: control)
    }

    private func press(control: Control) throws -> String {
        highlight(control)
        if Self.fieldRoles.contains(control.role) {
            AXUIElementSetAttributeValue(control.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            return "Alana geçildi: \(control.label)"
        }
        if AXUIElementPerformAction(control.element, kAXPressAction as CFString) == .success {
            return "Basıldı: \(control.label)"
        }
        // Some controls answer only to a real click.
        guard let frame = control.frame, frame.width > 0, frame.height > 0 else {
            throw Failure.failed("“\(control.label)” basılamadı.")
        }
        Self.click(at: CGPoint(x: frame.midX, y: frame.midY))
        return "Tıklandı: \(control.label)"
    }

    /// Clicks a point on screen, in the coordinates of the picture the
    /// assistant was shown: top-left origin, the same points the marks use.
    ///
    /// The last resort, for the things the Accessibility tree does not
    /// describe — a canvas, a drawing, a video. The same refusals apply: not
    /// while the screen is locked, not in a password application.
    func click(x: CGFloat, y: CGFloat, doubleClick: Bool = false) throws -> String {
        try targetApp(forTyping: false, activating: true)
        let point = CGPoint(x: x, y: y)
        guard Self.screens.contains(where: { $0.contains(point) }) else { throw Failure.offScreen }
        if let owner = Self.application(at: point), let bundle = owner.bundleIdentifier,
           Self.protectedBundles.contains(bundle) {
            throw Failure.protectedApp(owner.localizedName ?? bundle)
        }
        AgentFocusOverlay.shared.highlight(topLeftRect: CGRect(x: x - 14, y: y - 14, width: 28, height: 28))
        Self.click(at: point, count: doubleClick ? 2 : 1)
        return doubleClick ? "Çift tıklandı: \(Int(x)), \(Int(y))" : "Tıklandı: \(Int(x)), \(Int(y))"
    }

    /// Scrolls the window under the pointer, or at a point, so that what the
    /// user is asking about can come into view.
    func scroll(direction: String, amount: Int, at point: CGPoint? = nil) throws -> String {
        try targetApp(forTyping: false, activating: true)
        let steps = max(1, min(30, amount))
        var vertical = 0
        var horizontal = 0
        switch direction.lowercased() {
        case "up": vertical = steps
        case "down": vertical = -steps
        case "left": horizontal = steps
        case "right": horizontal = -steps
        default: throw Failure.failed("“\(direction)” bir yön değil: up, down, left, right.")
        }
        if let point { Self.move(to: point) }
        let source = CGEventSource(stateID: .hidSystemState)
        for _ in 0..<steps {
            CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2,
                    wheel1: Int32(vertical == 0 ? 0 : (vertical > 0 ? 3 : -3)),
                    wheel2: Int32(horizontal == 0 ? 0 : (horizontal > 0 ? 3 : -3)), wheel3: 0)?
                .post(tap: .cghidEventTap)
            usleep(20_000)
        }
        return "Kaydırıldı: \(direction)"
    }

    /// Types `text` where the cursor is, or into the field called `field` — or
    /// the field with that number.
    func type(_ text: String, into field: String?, number: Int? = nil) throws -> String {
        let app = try targetApp(forTyping: true, activating: true)
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 2.0)
        if let number {
            let control = try self.control(number: number, of: app)
            try focus(control)
        } else if let field, !field.isEmpty {
            let candidates = Self.collect(in: Self.windows(of: element), limit: 400)
            guard let control = Self.best(candidates, matching: field, role: nil, preferFields: true) else {
                throw Failure.notFound(field, Self.nearest(candidates, to: field))
            }
            try focus(control)
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

    private func focus(_ control: Control) throws {
        guard Self.string(control.element, kAXSubroleAttribute) != "AXSecureTextField" else {
            throw Failure.secureField
        }
        highlight(control)
        AXUIElementSetAttributeValue(control.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        // A web page's field often ignores AXFocused and wants the click it
        // would have got from a person.
        if (Self.attribute(control.element, kAXFocusedAttribute) as Bool?) != true,
           let frame = control.frame, frame.width > 0 {
            Self.click(at: CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    /// Sends a shortcut or a key, e.g. "cmd+s", "return", "cmd+shift+t".
    func press(keys combo: String, times: Int = 1) throws -> String {
        let app = try targetApp(forTyping: true, activating: true)
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
    ///
    /// Not simply "the frontmost application": MacB's own panel takes the
    /// keyboard the moment a question is typed, and on some paths the front as
    /// well, which used to leave the assistant answering "there is no app in
    /// front" to a screen full of them. The window list settles it — its order
    /// is front to back — so the app that owns the frontmost ordinary window
    /// that is not MacB's is the one the user means.
    @discardableResult
    private func targetApp(forTyping: Bool, activating: Bool) throws -> NSRunningApplication {
        guard AXIsProcessTrusted() else { throw Failure.noAccessibility }
        if Self.screenIsLocked { throw Failure.locked }
        guard let app = Self.frontApplication() else { throw Failure.noApp }
        if let bundle = app.bundleIdentifier, Self.protectedBundles.contains(bundle) {
            throw Failure.protectedApp(app.localizedName ?? bundle)
        }
        if forTyping { try checkSecureInput() }
        // A click at a point, and typing in most applications, land where the
        // keyboard is; bring the window forward first so they land there.
        if activating, !app.isActive {
            app.activate()
            usleep(120_000)
        }
        return app
    }

    /// The application in front that is not MacB.
    static func frontApplication() -> NSRunningApplication? {
        let mine = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != mine,
           front.activationPolicy == .regular {
            return front
        }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in windows {
            // Layer zero is an ordinary window; panels, menus and the island
            // itself float above it.
            guard window[kCGWindowLayer as String] as? Int == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != mine,
                  let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular else { continue }
            return app
        }
        return nil
    }

    /// Which application owns the window under a point, for the guard on a
    /// click by coordinates.
    private static func application(at point: CGPoint) -> NSRunningApplication? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in windows {
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                              width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if rect.contains(point) { return NSRunningApplication(processIdentifier: pid) }
        }
        return nil
    }

    /// Every screen, in the top-left coordinates the Accessibility API and a
    /// screenshot both use.
    private static var screens: [CGRect] {
        guard let primary = NSScreen.screens.first else { return [] }
        return NSScreen.screens.map { screen in
            CGRect(x: screen.frame.minX,
                   y: primary.frame.maxY - screen.frame.maxY,
                   width: screen.frame.width, height: screen.frame.height)
        }
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

    /// The control a number refers to, checked rather than trusted: the
    /// listing must be this application's, recent, and the element must still
    /// be there with the same name.
    private func control(number: Int, of app: NSRunningApplication) throws -> Control {
        guard listingApp == app.processIdentifier, Date().timeIntervalSince(listedAt) < 180,
              let control = listing.first(where: { $0.number == number }) else { throw Failure.staleNumber }
        guard let role = Self.string(control.element, kAXRoleAttribute), role == control.role,
              Self.label(of: control.element) == control.label else { throw Failure.staleNumber }
        return control
    }

    // MARK: - Tree

    /// The windows worth looking in: the one with the keyboard first, then the
    /// main one, then the rest.
    ///
    /// All of them, not just the focused one, because MacB's own panel holds
    /// the keyboard while the user is asking — the application they mean often
    /// has no focused window at that moment, and asking only for that one is
    /// what used to make the assistant say there was nothing on screen.
    private static func windows(of app: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        func add(_ window: AXUIElement?) {
            guard let window, !result.contains(where: { CFEqual($0, window) }) else { return }
            result.append(window)
        }
        add(attribute(app, kAXFocusedWindowAttribute))
        add(attribute(app, kAXMainWindowAttribute))
        for window in (attribute(app, kAXWindowsAttribute) as [AXUIElement]?) ?? [] {
            guard (attribute(window, "AXMinimized") as Bool?) != true else { continue }
            add(window)
        }
        return Array(result.prefix(4))
    }

    /// Asks a Chromium or Electron application to build the full tree, the way
    /// a screen reader does. Answers whether this is such an application: no
    /// other kind has the attribute at all.
    @discardableResult
    static func enableRichTree(_ app: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success
    }

    private static func collect(in roots: [AXUIElement], limit: Int) -> [Control] {
        var ignored = false
        return collect(in: roots, limit: limit, sawPage: &ignored)
    }

    private static func collect(in roots: [AXUIElement], limit: Int, sawPage: inout Bool) -> [Control] {
        var result: [Control] = []
        var queue: [(AXUIElement, Int)] = roots.map { ($0, 0) }
        var later: [(AXUIElement, Int)] = []
        /// How many controls carry each name, so a row of seven identical
        /// close buttons does not fill the listing.
        var counts: [String: Int] = [:]
        var visited = 0
        let deadline = Date().addingTimeInterval(2.5)
        while result.count < limit, visited < 12_000, Date() < deadline {
            if queue.isEmpty {
                guard !later.isEmpty else { break }
                queue = later
                later = []
            }
            let (element, depth) = queue.removeFirst()
            visited += 1
            let role = string(element, kAXRoleAttribute) ?? ""
            if role == "AXWebArea" { sawPage = true }
            let interactive = interactiveRoles.contains(role)
            if interactive || pressableRoles.contains(role),
               (attribute(element, kAXEnabledAttribute) as Bool?) != false {
                let label = label(of: element)
                // A pressable-only role earns its place by actually being
                // pressable; asking every element costs a round trip each.
                if !label.isEmpty, interactive || canPress(element) {
                    let secure = string(element, kAXSubroleAttribute) == "AXSecureTextField"
                    let isField = fieldRoles.contains(role)
                    let value = isField && !secure ? string(element, kAXValueAttribute).map { String($0.prefix(80)) } : nil
                    let control = Control(number: result.count + 1, element: element, role: role, label: label,
                                          value: secure ? "(parola alanı)" : value, frame: frame(of: element))
                    let key = role + "\u{1}" + label
                    let sameName = counts[key] ?? 0
                    let duplicate = result.contains { $0.label == control.label && $0.role == control.role
                        && $0.frame == control.frame }
                    if !duplicate, sameName < 2 {
                        counts[key] = sameName + 1
                        result.append(control)
                    }
                }
            }
            guard depth < 18, let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) else { continue }
            for child in children {
                let childRole = string(child, kAXRoleAttribute) ?? ""
                if furnitureRoles.contains(childRole) {
                    later.append((child, depth + 1))
                } else {
                    queue.append((child, depth + 1))
                }
            }
        }
        return result
    }

    /// Whether the application says this element can be pressed at all.
    private static func canPress(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let actions = names as? [String] else { return false }
        return actions.contains(kAXPressAction as String)
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
        // A static text or a cell is named by what it says.
        if role == "AXStaticText" || role == "AXCell" || role == "AXHeading",
           let text = string(element, kAXValueAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return String(text.prefix(80))
        }
        if let children: [AXUIElement] = attribute(element, kAXChildrenAttribute), children.count <= 8 {
            let text = children.prefix(4).compactMap {
                string($0, kAXValueAttribute) ?? string($0, kAXTitleAttribute)
            }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(80)) }
        }
        return ""
    }

    // MARK: - Matching

    /// The closest name. Exact wins, then a prefix, then every word of the
    /// request appearing somewhere in the name, then a near-miss — because
    /// what the user says out loud and what is written on the button agree
    /// about as often as not: "kaydet" for "Kaydet…", "gönder" for "Gönder ⌘↩".
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
            var score = match(normalise(control.label), wanted)
            // A field is often found by what is written in it rather than by
            // its own name.
            if let value = control.value { score = max(score, match(normalise(value), wanted) - 10) }
            guard score > 0 else { continue }
            if fieldRoles.contains(control.role) == preferFields { score += 3 }
            if control.frame != nil { score += 2 }
            if score > bestScore { bestScore = score; best = control }
        }
        return best
    }

    /// How well one name answers to another, 0 when it does not at all.
    static func match(_ name: String, _ wanted: String) -> Int { ControlMatching.match(name, wanted) }

    static func editDistance(_ first: String, _ second: String) -> Int {
        ControlMatching.editDistance(first, second)
    }

    /// The names closest to what was asked for, to say back when none matched.
    /// A wrong guess that lists the real names is one turn from being right.
    private static func nearest(_ controls: [Control], to target: String, limit: Int = 12) -> [String] {
        let wanted = normalise(target)
        return controls
            .map { ($0, editDistance(normalise($0.label), wanted)) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { "\($0.0.number). \($0.0.label)" }
    }

    static func normalise(_ text: String) -> String { ControlMatching.normalise(text) }

    // MARK: - Menus

    private static func menuTitles(_ app: AXUIElement) -> [String] {
        guard let bar: AXUIElement = attribute(app, kAXMenuBarAttribute),
              let items: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else { return [] }
        return items.dropFirst().compactMap { string($0, kAXTitleAttribute) }.filter { !$0.isEmpty }
    }

    private func pressMenu(path: String, in app: AXUIElement) throws -> String {
        let parts = path.split(separator: ">").map { Self.normalise(String($0)) }.filter { !$0.isEmpty }
        guard !parts.isEmpty, var current: AXUIElement = Self.attribute(app, kAXMenuBarAttribute) else {
            throw Failure.notFound(path, [])
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
            else { throw Failure.notFound(path, []) }
            if index == parts.count - 1 {
                guard (Self.attribute(next, kAXEnabledAttribute) as Bool?) != false else {
                    throw Failure.failed("“\(path)” şu an seçilemiyor.")
                }
                AXUIElementPerformAction(next, kAXPressAction as CFString)
                return "Menüden seçildi: \(path)"
            }
            current = next
        }
        throw Failure.notFound(path, [])
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

    private static func move(to point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(20_000)
    }

    private static func click(at point: CGPoint, count: Int = 1) {
        let source = CGEventSource(stateID: .hidSystemState)
        move(to: point)
        for step in 1...max(1, count) {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                          mouseCursorPosition: point, mouseButton: .left) else { continue }
                event.setIntegerValueField(.mouseEventClickState, value: Int64(step))
                event.post(tap: .cghidEventTap)
            }
            usleep(40_000)
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
    static func frame(of element: AXUIElement) -> CGRect? {
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
