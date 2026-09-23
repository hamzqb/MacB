import AppKit
import Carbon
import Foundation

private enum AgentBrowserKind: Sendable { case chromium, safari }

private struct AgentBrowser: Sendable {
    let bundleID: String
    let name: String
    let kind: AgentBrowserKind
}

struct BrowserAgentPage: Decodable, Sendable {
    struct Field: Decodable, Sendable {
        let label: String
        let placeholder: String
        let name: String
        let type: String
        let value: String
    }

    struct Control: Decodable, Sendable {
        let text: String
        let kind: String
    }

    let browser: String
    let title: String
    let url: String
    let text: String
    let fields: [Field]
    let buttons: [Control]
    let links: [Control]
}

struct BrowserAgentActionResult: Decodable, Sendable {
    /// Where the element was on screen, top-left origin, in points.
    struct Box: Decodable, Sendable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
        var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    }

    let ok: Bool
    let message: String
    let title: String?
    let url: String?
    let box: Box?
}

@MainActor
final class BrowserAgentService {
    enum Failure: LocalizedError {
        case noBrowser
        case noPermission(String)
        case script(String)
        case badResult

        var errorDescription: String? {
            switch self {
            case .noBrowser:
                return "Önce Safari, Chrome, Brave, Edge veya Arc aç."
            case .noPermission(let browser):
                return "\(browser) için otomasyon izni yok. MacB bu sayfayı local okuyabilmek için tarayıcıya Apple Events izni ister."
            case .script(let message):
                return message
            case .badResult:
                return "Tarayıcıdan okunabilir sonuç gelmedi."
            }
        }
    }

    private static let supportedBrowsers = [
        AgentBrowser(bundleID: "com.apple.Safari", name: "Safari", kind: .safari),
        AgentBrowser(bundleID: "com.google.Chrome", name: "Google Chrome", kind: .chromium),
        AgentBrowser(bundleID: "com.google.Chrome.beta", name: "Google Chrome Beta", kind: .chromium),
        AgentBrowser(bundleID: "com.google.Chrome.dev", name: "Google Chrome Dev", kind: .chromium),
        AgentBrowser(bundleID: "com.brave.Browser", name: "Brave Browser", kind: .chromium),
        AgentBrowser(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge", kind: .chromium),
        AgentBrowser(bundleID: "company.thebrowser.Browser", name: "Arc", kind: .chromium)
    ]

    /// Whether an application is one of the browsers this can read. Asked by
    /// the screen tools, because a browser's page is the one place where the
    /// Accessibility API sees nothing and the page itself has to be asked.
    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return supportedBrowsers.contains { $0.bundleID == bundleID }
    }

    func readActivePage(maxTextCharacters: Int = 8_000) async throws -> BrowserAgentPage {
        let browser = try activeBrowser(prompt: true)
        let limit = max(500, min(12_000, maxTextCharacters))
        let json = try execute(Self.readJavaScript(limit: limit), in: browser, timeout: 4)
        guard let data = json.data(using: .utf8) else { throw Failure.badResult }
        var page = try JSONDecoder().decode(BrowserAgentPage.self, from: data)
        page = BrowserAgentPage(browser: browser.name, title: page.title, url: page.url, text: page.text,
                                fields: page.fields, buttons: page.buttons, links: page.links)
        return page
    }

    func perform(action: String, target: String, value: String?) async throws -> BrowserAgentActionResult {
        let browser = try activeBrowser(prompt: true)
        let js: String
        switch action {
        case "fill":
            js = Self.fillJavaScript(target: target, value: value ?? "")
        case "click":
            js = Self.clickJavaScript(target: target)
        default:
            throw Failure.script("Bilinmeyen tarayıcı işlemi.")
        }
        let json = try execute(js, in: browser, timeout: 3)
        guard let data = json.data(using: .utf8) else { throw Failure.badResult }
        return try JSONDecoder().decode(BrowserAgentActionResult.self, from: data)
    }

    private func activeBrowser(prompt: Bool) throws -> AgentBrowser {
        let running = Self.supportedBrowsers.filter {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty
        }
        guard !running.isEmpty else { throw Failure.noBrowser }
        // The application the user is in, which is not always the one macOS
        // calls frontmost: MacB's own panel takes the keyboard while they ask.
        let frontID = ScreenControlService.frontApplication()?.bundleIdentifier
        let browser = running.first(where: { $0.bundleID == frontID }) ?? running[0]
        guard Self.permissionStatus(for: browser, prompt: prompt) == noErr else {
            throw Failure.noPermission(browser.name)
        }
        return browser
    }

    private func execute(_ javascript: String, in browser: AgentBrowser, timeout: Int) throws -> String {
        let source = Self.appleScriptString(javascript)
        let execution: String
        switch browser.kind {
        case .chromium:
            execution = "execute active tab of front window javascript \(source)"
        case .safari:
            execution = "do JavaScript \(source) in current tab of front window"
        }
        let script = """
        with timeout of \(timeout) seconds
            tell application id "\(browser.bundleID)" to \(execution)
        end timeout
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue ?? ""
        if let number = error?[NSAppleScript.errorNumber] as? Int {
            if [-10000, -1708].contains(number) {
                let message = browser.kind == .safari
                    ? "Safari → Ayarlar → Geliştirici bölümünde Apple Events’ten JavaScript’e izin ver."
                    : "Tarayıcının Geliştirici menüsünde Apple Events’ten JavaScript’e izin ver."
                throw Failure.script(message)
            }
            throw Failure.script(error?[NSAppleScript.errorMessage] as? String ?? "Tarayıcı işlemi başarısız.")
        }
        guard !result.isEmpty else { throw Failure.badResult }
        return result
    }

    private static func permissionStatus(for browser: AgentBrowser, prompt: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: browser.bundleID)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, prompt)
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func jsString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private static func readJavaScript(limit: Int) -> String {
        """
        (() => {
          const visible = (el) => {
            if (!el) return false;
            const s = getComputedStyle(el), r = el.getBoundingClientRect();
            return s.visibility !== 'hidden' && s.display !== 'none' && r.width > 2 && r.height > 2;
          };
          const clean = (s) => (s || '').replace(/\\s+/g, ' ').trim();
          const labelFor = (el) => {
            const id = el.id;
            const byFor = id ? document.querySelector(`label[for="${CSS.escape(id)}"]`) : null;
            const parent = el.closest('label');
            const aria = el.getAttribute('aria-label') || el.getAttribute('aria-labelledby');
            return clean((byFor && byFor.innerText) || (parent && parent.innerText) || aria || '');
          };
          const fields = [...document.querySelectorAll('input, textarea, select')]
            .filter(visible)
            .filter((el) => !['hidden', 'password'].includes((el.type || '').toLowerCase()))
            .slice(0, 30)
            .map((el) => ({
              label: labelFor(el),
              placeholder: clean(el.getAttribute('placeholder')),
              name: clean(el.getAttribute('name') || el.id),
              type: clean(el.type || el.tagName.toLowerCase()),
              value: clean(el.value || '')
            }));
          const buttons = [...document.querySelectorAll('button, input[type="button"], input[type="submit"], [role="button"]')]
            .filter(visible)
            .map((el) => ({ text: clean(el.innerText || el.value || el.getAttribute('aria-label')), kind: el.tagName.toLowerCase() }))
            .filter((x) => x.text)
            .slice(0, 40);
          const links = [...document.querySelectorAll('a[href]')]
            .filter(visible)
            .map((el) => ({ text: clean(el.innerText || el.getAttribute('aria-label')), kind: 'link' }))
            .filter((x) => x.text)
            .slice(0, 40);
          const text = clean(document.body ? document.body.innerText : '').slice(0, \(limit));
          return JSON.stringify({ browser: '', title: document.title || '', url: location.href, text, fields, buttons, links });
        })()
        """
    }

    private static func fillJavaScript(target: String, value: String) -> String {
        let target = jsString(target)
        let value = jsString(value)
        return """
        (() => {
          const wanted = \(target).toLocaleLowerCase('tr').trim();
          const value = \(value);
          const clean = (s) => (s || '').replace(/\\s+/g, ' ').trim();
          const visible = (el) => {
            const s = getComputedStyle(el), r = el.getBoundingClientRect();
            return s.visibility !== 'hidden' && s.display !== 'none' && r.width > 2 && r.height > 2;
          };
          const boxOf = (el) => {
            const r = el.getBoundingClientRect();
            const chrome = Math.max(0, window.outerHeight - window.innerHeight);
            return { x: window.screenX + r.left, y: window.screenY + chrome + r.top, w: r.width, h: r.height };
          };
          const labelFor = (el) => {
            const id = el.id;
            const byFor = id ? document.querySelector(`label[for="${CSS.escape(id)}"]`) : null;
            const parent = el.closest('label');
            return clean((byFor && byFor.innerText) || (parent && parent.innerText) || el.getAttribute('aria-label') || '');
          };
          const score = (el) => [labelFor(el), el.placeholder, el.name, el.id].map(clean).join(' ').toLocaleLowerCase('tr');
          const fields = [...document.querySelectorAll('input, textarea, select')]
            .filter(visible)
            .filter((el) => !['hidden', 'password'].includes((el.type || '').toLowerCase()));
          const el = fields.find((field) => score(field).includes(wanted));
          if (!el) return JSON.stringify({ ok: false, message: 'Alan bulunamadı.', title: document.title, url: location.href });
          const box = boxOf(el);
          el.focus();
          el.value = value;
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return JSON.stringify({ ok: true, message: `Alan dolduruldu: ${labelFor(el) || el.placeholder || el.name || el.id}`, title: document.title, url: location.href, box });
        })()
        """
    }

    private static func clickJavaScript(target: String) -> String {
        let target = jsString(target)
        return """
        (() => {
          const wanted = \(target).toLocaleLowerCase('tr').trim();
          const clean = (s) => (s || '').replace(/\\s+/g, ' ').trim();
          const visible = (el) => {
            const s = getComputedStyle(el), r = el.getBoundingClientRect();
            return s.visibility !== 'hidden' && s.display !== 'none' && r.width > 2 && r.height > 2;
          };
          const boxOf = (el) => {
            const r = el.getBoundingClientRect();
            const chrome = Math.max(0, window.outerHeight - window.innerHeight);
            return { x: window.screenX + r.left, y: window.screenY + chrome + r.top, w: r.width, h: r.height };
          };
          const controls = [...document.querySelectorAll('button, a[href], input[type="button"], input[type="submit"], [role="button"]')]
            .filter(visible);
          const textOf = (el) => clean(el.innerText || el.value || el.getAttribute('aria-label') || el.title || '');
          const el = controls.find((control) => textOf(control).toLocaleLowerCase('tr').includes(wanted));
          if (!el) return JSON.stringify({ ok: false, message: 'Tıklanacak öğe bulunamadı.', title: document.title, url: location.href });
          const label = textOf(el);
          const box = boxOf(el);
          el.click();
          return JSON.stringify({ ok: true, message: `Tıklandı: ${label}`, title: document.title, url: location.href, box });
        })()
        """
    }
}
