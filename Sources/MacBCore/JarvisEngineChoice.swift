import Foundation

/// Which voice MacB talks with.
///
/// There are two, and they are not the same thing pretending to be one. The
/// live engine is OpenAI's speech-to-speech: it hears you while you are still
/// talking, it can be interrupted mid-sentence, and it is the good one. It is
/// also billed by the second of audio in both directions, including the
/// seconds nobody is speaking.
///
/// The free engine is the Mac's own: macOS turns speech into text on the
/// device, a free provider answers it, and macOS reads the answer back. It
/// takes its turn rather than sharing one — you finish, then it starts — and
/// it cannot be cut off mid-word. Nothing about it costs anything.
///
/// Automatic is the one to leave it on: the good voice while there is a key
/// and an allowance for it, the free one the moment there is not, without a
/// conversation ever failing to start over money.
public enum JarvisEngineChoice: String, CaseIterable, Codable, Sendable, Identifiable {
    case automatic
    case live
    case free

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Otomatik"
        case .live: return "Canlı (OpenAI)"
        case .free: return "Ücretsiz (bu Mac)"
        }
    }

    public var note: String {
        switch self {
        case .automatic:
            return "Bütçe ve anahtar elverdiğinde canlı ses, elvermediğinde ücretsiz mod. Konuşma para yüzünden hiç başlamamazlık etmez."
        case .live:
            return "En iyisi: sözünü kesebilirsin, sen konuşurken dinler. Saniyesi ücretlidir, sessizlik de sayılır."
        case .free:
            return "Bedava: konuşma bu Mac'te yazıya çevrilir, cevabı ücretsiz sağlayıcı yazar, macOS okur. Sıra sende–sıra onda; sözünü kesemezsin."
        }
    }

    /// Which engine actually runs, given what is available right now.
    ///
    /// Pure so the rule is testable: the interesting cases are the ones where
    /// something is missing, and none of them should ever produce "nothing".
    public static func resolve(choice: JarvisEngineChoice, hasPaidKey: Bool,
                               isOverBudget: Bool, hasFreeKey: Bool) -> Resolved {
        let liveUsable = hasPaidKey && !isOverBudget
        switch choice {
        case .live:
            if liveUsable { return .live }
            // Asked for the good one and it is not available: take the free one
            // rather than refusing, and say why.
            if hasFreeKey { return isOverBudget ? .freeBecauseBudget : .freeBecauseNoKey }
            return isOverBudget ? .blockedByBudget : .blockedNoKey
        case .free:
            return hasFreeKey ? .free : .blockedNoKey
        case .automatic:
            if liveUsable { return .live }
            if hasFreeKey { return isOverBudget ? .freeBecauseBudget : .freeBecauseNoKey }
            return isOverBudget ? .blockedByBudget : .blockedNoKey
        }
    }

    public enum Resolved: Equatable, Sendable {
        case live
        case free
        /// The free engine, because the day's allowance is gone.
        case freeBecauseBudget
        /// The free engine, because there is no key for the paid one.
        case freeBecauseNoKey
        case blockedByBudget
        case blockedNoKey

        public var isFree: Bool {
            switch self {
            case .free, .freeBecauseBudget, .freeBecauseNoKey: return true
            default: return false
            }
        }

        public var isBlocked: Bool {
            switch self {
            case .blockedByBudget, .blockedNoKey: return true
            default: return false
            }
        }

        /// What the island says about the switch, or nothing when there was no
        /// switch worth mentioning.
        public var note: String? {
            switch self {
            case .freeBecauseBudget: return "Günlük sınır doldu — ücretsiz moda geçtim."
            case .freeBecauseNoKey: return "OpenAI anahtarı yok — ücretsiz moddayım."
            case .blockedByBudget:
                return "Günlük sınır doldu ve ücretsiz sağlayıcı anahtarı yok. Ayarlar › Maliyet'ten sınırı değiştir."
            case .blockedNoKey:
                return "Önce Ayarlar › Araçlar'dan bir anahtar gir."
            default: return nil
            }
        }
    }
}
