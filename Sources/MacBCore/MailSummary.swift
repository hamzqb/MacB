import Foundation

/// One message, as much of it as MacB ever looks at.
///
/// The sender, the subject, when it arrived, and whether it is flagged or
/// unread. Not the body. A briefing that says "three important messages" needs
/// nothing more than this, and a body is where the private part of somebody's
/// mail actually lives — reading it to decide whether to mention it would be
/// paying the whole privacy cost for a sentence.
public struct MailHeader: Equatable, Sendable, Identifiable {
    public var sender: String
    public var subject: String
    public var date: Date
    public var isFlagged: Bool
    public var isUnread: Bool
    public var mailbox: String

    public init(sender: String, subject: String, date: Date,
                isFlagged: Bool = false, isUnread: Bool = true, mailbox: String = "") {
        self.sender = sender
        self.subject = subject
        self.date = date
        self.isFlagged = isFlagged
        self.isUnread = isUnread
        self.mailbox = mailbox
    }

    public var id: String { sender + "|" + subject + "|" + String(date.timeIntervalSince1970) }

    /// The sender without the address: "Ahmet Yılmaz <a@b.com>" is a name and
    /// an address, and the name is the part somebody recognises.
    public var senderName: String {
        guard let open = sender.firstIndex(of: "<") else {
            let bare = sender.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            // A header that is only an address: the part before the @ is closer
            // to a name than the whole thing, and it is what fits on a chip.
            guard bare.contains("@") else { return bare }
            return bare.split(separator: "@").first.map(String.init) ?? bare
        }
        let name = sender[sender.startIndex..<open]
            .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        if !name.isEmpty { return name }
        // Only an address: the part before the @ is closer to a name than the
        // whole thing is.
        let address = sender[sender.index(after: open)...].prefix { $0 != ">" }
        return address.split(separator: "@").first.map(String.init) ?? String(address)
    }
}

/// Which unread mail is worth a sentence in the morning.
///
/// Deliberately dumb and deliberately explainable. There is no model here and
/// no learning: a flag is important because the user flagged it, a name on the
/// user's own list is important because they put it there, and everything else
/// is mail. A clever ranker that quietly decided what mattered would be wrong
/// in a way nobody could see, in the one place — "did I miss anything?" — where
/// being wrong costs the most.
public enum MailImportance {
    /// Senders the user named. Matched on the whole header, so either the name
    /// or the address finds it.
    public static func isImportant(_ header: MailHeader, senders: [String]) -> Bool {
        if header.isFlagged { return true }
        let haystack = ScenarioMatching.normalise(header.sender)
        return senders.contains { name in
            let needle = ScenarioMatching.normalise(name)
            return !needle.isEmpty && haystack.contains(needle)
        }
    }

    /// The unread mail worth mentioning, newest first, and never more than a
    /// handful: a briefing that lists ten things is a briefing nobody hears the
    /// end of.
    public static func important(in headers: [MailHeader], senders: [String],
                                 limit: Int = 3) -> [MailHeader] {
        headers
            .filter { $0.isUnread && isImportant($0, senders: senders) }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    /// What the briefing says about the inbox, or nothing when there is
    /// genuinely nothing to say.
    ///
    /// "No important mail" is worth saying — it is the answer to the question
    /// somebody actually has in the morning. "No mail at all" is not, and a
    /// count on its own never is: forty unread is the ordinary state of an
    /// inbox, not news.
    public static func chip(unread: Int, important: [MailHeader]) -> Briefing.Chip? {
        if !important.isEmpty {
            let first = important[0].senderName
            let more = important.count > 1 ? " +\(important.count - 1)" : ""
            return Briefing.Chip(symbol: "envelope.badge", text: first + more, isUrgent: true)
        }
        guard unread > 0 else { return nil }
        return Briefing.Chip(symbol: "envelope", text: "Önemli mail yok")
    }

    /// The same thing, said aloud.
    public static func line(unread: Int, important: [MailHeader]) -> String? {
        if important.isEmpty {
            guard unread > 0 else { return nil }
            return unread == 1 ? "Bir okunmamış mail var, önemli görünmüyor."
                               : "\(unread) okunmamış mail var, önemli bir şey yok."
        }
        let names = important.map(\.senderName).joined(separator: ", ")
        return important.count == 1 ? "\(names)'dan önemli bir mail var."
                                    : "Önemli mailler: \(names)."
    }

    /// At most this many headers are ever read out of Mail at once.
    public static let maximumHeaders = 40
}


/// Turning Apple Mail's answer back into headers.
///
/// Pure, and separate from the service that asks the question, because this is
/// the part worth being sure about: every byte of it is somebody else's text.
/// A subject line is written by whoever sent the message, and it may contain
/// the field separator's neighbours, a newline, or a sentence addressed to a
/// model. All of it is carried as data and none of it is obeyed — proving that
/// needs strings, not a mailbox.
public enum MailParsing {
    /// The two separators. Unit and record separator: control characters no
    /// subject line contains, so a subject cannot split a row or invent one.
    public static let field = "\u{001F}"
    public static let record = "\u{001E}"

    public static func headers(_ raw: String) -> [MailHeader] {
        let rows = raw.components(separatedBy: record)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var headers: [MailHeader] = []
        for row in rows {
            let fields = row.components(separatedBy: field)
            guard fields.count >= 4 else { continue }
            headers.append(MailHeader(sender: fields[0],
                                      subject: clip(fields[1]),
                                      date: date(fields[2]),
                                      isFlagged: fields[3].lowercased().contains("true"),
                                      isUnread: true))
        }
        return headers.sorted { $0.date > $1.date }
    }

    /// A subject is a line, not a document. One that arrives as a paragraph is
    /// cut here rather than in the island, and its newlines come out: a subject
    /// that is three lines tall would push everything else off the card.
    public static func clip(_ subject: String) -> String {
        let flattened = subject
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flattened.count <= 160 ? flattened : String(flattened.prefix(160)) + "…"
    }

    /// AppleScript hands dates back as whatever the user's locale writes, so
    /// several shapes are tried.
    public static func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEEE, MMMM d, yyyy 'at' h:mm:ss a", "d MMMM yyyy EEEE HH:mm:ss",
                       "EEEE d MMMM yyyy HH:mm:ss", "d MMMM yyyy 'tarihinde saat' HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        // An unparsed date is still a message; treating it as just-arrived
        // keeps it in the list rather than sorting it to the bottom of 1970.
        return Date()
    }
}
