import AppKit
import Combine
import Foundation
import MacBCore

/// Reads the headers of unread mail out of Apple Mail, and nothing else.
///
/// Through AppleScript, which means macOS asks the user once whether MacB may
/// control Mail and they can take it back in System Settings › Privacy &
/// Security › Automation. Nothing is fetched over the network by MacB: Mail
/// already has the messages, and this only asks it what is unread.
///
/// Only the sender, the subject, the date and the flag are read. Never a body,
/// never an attachment, never a recipient list. That is enough to say whether
/// the morning has anything in it, and it is the line past which reading
/// somebody's mail starts being reading somebody's mail.
///
/// Nothing read here is stored. It lives in memory for as long as the briefing
/// or the answer that asked for it.
@MainActor final class MailService: ObservableObject {
    struct Summary: Equatable {
        var unread: Int = 0
        var headers: [MailHeader] = []
        /// Mail is not running, or MacB was not allowed to ask it.
        var isUnavailable = false
        var note: String?
    }

    @Published private(set) var summary = Summary()
    @Published private(set) var isReading = false

    /// Senders the user called important, from Settings.
    var importantSenders: () -> [String] = { [] }

    private var lastRead: Date?
    /// Asking Mail is not free — it wakes an application and runs a script —
    /// so a repeated question inside this window is answered from what was
    /// already read.
    private static let freshness: TimeInterval = 120

    var isMailInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail") != nil
    }

    var important: [MailHeader] {
        MailImportance.important(in: summary.headers, senders: importantSenders())
    }

    /// Reads the inbox, or hands back what was read a moment ago.
    @discardableResult
    func refresh(force: Bool = false) async -> Summary {
        if !force, let lastRead, Date().timeIntervalSince(lastRead) < Self.freshness { return summary }
        guard isMailInstalled else {
            summary = Summary(isUnavailable: true, note: "Bu Mac'te Mail uygulaması yok.")
            return summary
        }
        isReading = true
        defer { isReading = false }
        let outcome = await Self.read()
        lastRead = Date()
        summary = outcome
        return outcome
    }

    /// What the briefing says about the mail.
    func chip() -> Briefing.Chip? {
        guard !summary.isUnavailable else { return nil }
        return MailImportance.chip(unread: summary.unread, important: important)
    }

    func line() -> String? {
        guard !summary.isUnavailable else { return nil }
        return MailImportance.line(unread: summary.unread, important: important)
    }

    // MARK: - Apple Mail

    /// The script. It asks only for the four fields, only for unread messages,
    /// and only for the newest `maximumHeaders` of them.
    ///
    /// Written as a list of records rather than as a sentence of text so that
    /// nothing in a subject — a quote, a newline, a separator — can change the
    /// shape of what comes back. The fields are joined with a delimiter no
    /// subject line contains and split back out here.
    nonisolated private static let script = """
        set sep to (ASCII character 31)
        set rowSep to (ASCII character 30)
        set out to ""
        on addUnreadFrom(boxName, messagesList, sep, rowSep, currentOut)
            repeat with m in messagesList
                try
                    set currentOut to currentOut & (sender of m) & sep & (subject of m) & sep & ¬
                        ((date received of m) as string) & sep & ((flagged status of m) as string) & sep & boxName & rowSep
                end try
            end repeat
            return currentOut
        end addUnreadFrom
        tell application "Mail"
            try
                set out to my addUnreadFrom("Inbox", (messages of inbox whose read status is false), sep, rowSep, out)
            end try
            repeat with acc in accounts
                try
                    set accountName to name of acc
                    set accountInbox to mailbox "INBOX" of acc
                    set out to my addUnreadFrom(accountName, (messages of accountInbox whose read status is false), sep, rowSep, out)
                end try
            end repeat
        end tell
        return out
        """

    nonisolated private static let probeScript = """
        set out to ""
        tell application "Mail"
            set accountCount to 0
            set mailboxCount to 0
            set unreadInbox to 0
            try
                set accountCount to count of accounts
            end try
            try
                set unreadInbox to count of (messages of inbox whose read status is false)
            end try
            repeat with acc in accounts
                try
                    set mailboxCount to mailboxCount + (count of mailboxes of acc)
                end try
            end repeat
            set out to "accounts=" & accountCount & return & "mailboxes=" & mailboxCount & return & "unified_unread=" & unreadInbox
        end tell
        return out
        """

    private static func read() async -> Summary {
        await withCheckedContinuation { continuation in
            // Off the main actor: an AppleScript to another application can
            // block for seconds, and the island must not stop while it does.
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&error)
                let outcome: Summary
                if let error {
                    outcome = Summary(isUnavailable: true, note: Self.message(for: error))
                } else {
                    outcome = Self.parse(descriptor?.stringValue ?? "")
                }
                continuation.resume(returning: outcome)
            }
        }
    }

    static func probe() async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let descriptor = NSAppleScript(source: probeScript)?.executeAndReturnError(&error)
                if let error {
                    continuation.resume(returning: "error=\(Self.message(for: error))")
                } else {
                    continuation.resume(returning: descriptor?.stringValue ?? "")
                }
            }
        }
    }

    /// Turns the script's output back into headers. The reading of it is in
    /// `MailParsing`, where it can be proved against strings.
    nonisolated static func parse(_ raw: String) -> Summary {
        let headers = MailParsing.headers(raw)
        return Summary(unread: headers.count,
                       headers: Array(headers.prefix(MailImportance.maximumHeaders)))
    }

    nonisolated private static func message(for error: NSDictionary) -> String {
        let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
        switch code {
        case -1743, -1744:
            return "Mail'e erişim izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Otomasyon'dan MacB'ye Mail'i aç."
        case -600, -609:
            return "Mail açık değil."
        default:
            return "Mail okunamadı."
        }
    }
}
