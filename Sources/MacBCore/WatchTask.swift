import Foundation

public enum WatchKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case websitePrice
    case websiteText
    case githubRelease
    case systemMetric

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .websitePrice: return "Fiyat"
        case .websiteText: return "Web değişimi"
        case .githubRelease: return "GitHub release"
        case .systemMetric: return "Sistem"
        }
    }

    public var symbol: String {
        switch self {
        case .websitePrice: return "tag"
        case .websiteText: return "text.page"
        case .githubRelease: return "shippingbox"
        case .systemMetric: return "gauge.with.dots.needle.67percent"
        }
    }
}

public enum WatchMetric: String, Codable, CaseIterable, Sendable, Identifiable {
    case cpuPercent
    case memoryPercent
    case batteryPercent
    case appCPUPercent
    case appMemoryMB

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpuPercent: return "CPU"
        case .memoryPercent: return "Bellek"
        case .batteryPercent: return "Pil"
        case .appCPUPercent: return "Uygulama CPU"
        case .appMemoryMB: return "Uygulama RAM"
        }
    }

    public var unit: String {
        switch self {
        case .cpuPercent, .memoryPercent, .batteryPercent, .appCPUPercent: return "%"
        case .appMemoryMB: return "MB"
        }
    }
}

public enum WatchCondition: Codable, Equatable, Sendable {
    case priceBelow(Double)
    case priceAbove(Double)
    case textContains(String)
    case textChanged
    case versionChanged
    case metricAbove(WatchMetric, Double)
    case metricBelow(WatchMetric, Double)

    private enum CodingKeys: String, CodingKey { case type, value, text, metric }
    private enum Kind: String, Codable {
        case priceBelow, priceAbove, textContains, textChanged, versionChanged, metricAbove, metricBelow
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Kind.self, forKey: .type)
        switch type {
        case .priceBelow: self = .priceBelow(try container.decode(Double.self, forKey: .value))
        case .priceAbove: self = .priceAbove(try container.decode(Double.self, forKey: .value))
        case .textContains: self = .textContains(try container.decode(String.self, forKey: .text))
        case .textChanged: self = .textChanged
        case .versionChanged: self = .versionChanged
        case .metricAbove:
            self = .metricAbove(try container.decode(WatchMetric.self, forKey: .metric),
                                try container.decode(Double.self, forKey: .value))
        case .metricBelow:
            self = .metricBelow(try container.decode(WatchMetric.self, forKey: .metric),
                                try container.decode(Double.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .priceBelow(let value):
            try container.encode(Kind.priceBelow, forKey: .type)
            try container.encode(value, forKey: .value)
        case .priceAbove(let value):
            try container.encode(Kind.priceAbove, forKey: .type)
            try container.encode(value, forKey: .value)
        case .textContains(let text):
            try container.encode(Kind.textContains, forKey: .type)
            try container.encode(text, forKey: .text)
        case .textChanged:
            try container.encode(Kind.textChanged, forKey: .type)
        case .versionChanged:
            try container.encode(Kind.versionChanged, forKey: .type)
        case .metricAbove(let metric, let value):
            try container.encode(Kind.metricAbove, forKey: .type)
            try container.encode(metric, forKey: .metric)
            try container.encode(value, forKey: .value)
        case .metricBelow(let metric, let value):
            try container.encode(Kind.metricBelow, forKey: .type)
            try container.encode(metric, forKey: .metric)
            try container.encode(value, forKey: .value)
        }
    }

    public var title: String {
        switch self {
        case .priceBelow(let value): return "fiyat \(WatchFormatting.number(value)) altına inince"
        case .priceAbove(let value): return "fiyat \(WatchFormatting.number(value)) üstüne çıkınca"
        case .textContains(let text): return "\(text) görünce"
        case .textChanged: return "metin değişince"
        case .versionChanged: return "yeni sürüm çıkınca"
        case .metricAbove(let metric, let value): return "\(metric.title) \(WatchFormatting.number(value))\(metric.unit) üstüne çıkınca"
        case .metricBelow(let metric, let value): return "\(metric.title) \(WatchFormatting.number(value))\(metric.unit) altına inince"
        }
    }
}

public enum WatchStatus: String, Codable, Sendable {
    case idle
    case checking
    case ok
    case triggered
    case failed

    public var title: String {
        switch self {
        case .idle: return "Bekliyor"
        case .checking: return "Bakıyor"
        case .ok: return "Sakin"
        case .triggered: return "Yakalandı"
        case .failed: return "Hata"
        }
    }
}

public struct WatchTask: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: WatchKind
    public var target: String
    public var condition: WatchCondition
    public var intervalMinutes: Int
    public var isEnabled: Bool
    public var lastValue: String?
    public var lastNumericValue: Double?
    public var baseline: String?
    public var lastCheckedAt: Date?
    public var lastTriggeredAt: Date?
    public var status: WatchStatus
    public var errorMessage: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, kind: WatchKind, target: String,
                condition: WatchCondition, intervalMinutes: Int = 30, isEnabled: Bool = true,
                lastValue: String? = nil, lastNumericValue: Double? = nil, baseline: String? = nil,
                lastCheckedAt: Date? = nil, lastTriggeredAt: Date? = nil, status: WatchStatus = .idle,
                errorMessage: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.kind = kind
        self.target = target
        self.condition = condition
        self.intervalMinutes = max(5, min(1440, intervalMinutes))
        self.isEnabled = isEnabled
        self.lastValue = lastValue
        self.lastNumericValue = lastNumericValue
        self.baseline = baseline
        self.lastCheckedAt = lastCheckedAt
        self.lastTriggeredAt = lastTriggeredAt
        self.status = status
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }

    public var isDue: Bool {
        guard isEnabled else { return false }
        guard let lastCheckedAt else { return true }
        return Date().timeIntervalSince(lastCheckedAt) >= TimeInterval(intervalMinutes * 60)
    }
}

public struct WatchReading: Equatable, Sendable {
    public var displayValue: String
    public var numericValue: Double?
    public var rawValue: String

    public init(displayValue: String, numericValue: Double? = nil, rawValue: String) {
        self.displayValue = displayValue
        self.numericValue = numericValue
        self.rawValue = rawValue
    }
}

public struct WatchEvaluation: Equatable, Sendable {
    public var triggered: Bool
    public var baseline: String?
    public var message: String

    public init(triggered: Bool, baseline: String?, message: String) {
        self.triggered = triggered
        self.baseline = baseline
        self.message = message
    }

    public static func evaluate(task: WatchTask, reading: WatchReading) -> WatchEvaluation {
        let raw = normalized(reading.rawValue)
        switch task.condition {
        case .priceBelow(let threshold):
            guard let price = reading.numericValue else { return .init(triggered: false, baseline: task.baseline, message: "Fiyat bulunamadı") }
            return .init(triggered: price <= threshold, baseline: task.baseline,
                         message: "\(reading.displayValue) · hedef \(WatchFormatting.number(threshold)) altı")
        case .priceAbove(let threshold):
            guard let price = reading.numericValue else { return .init(triggered: false, baseline: task.baseline, message: "Fiyat bulunamadı") }
            return .init(triggered: price >= threshold, baseline: task.baseline,
                         message: "\(reading.displayValue) · hedef \(WatchFormatting.number(threshold)) üstü")
        case .textContains(let text):
            let found = raw.localizedCaseInsensitiveContains(normalized(text))
            return .init(triggered: found, baseline: task.baseline, message: found ? "Metin bulundu" : "Henüz yok")
        case .textChanged:
            guard let baseline = task.baseline else {
                return .init(triggered: false, baseline: raw, message: "İlk metin kaydedildi")
            }
            return .init(triggered: raw != baseline, baseline: raw,
                         message: raw == baseline ? "Değişiklik yok" : "Sayfa değişti")
        case .versionChanged:
            guard let baseline = task.baseline else {
                return .init(triggered: false, baseline: raw, message: "İlk sürüm kaydedildi")
            }
            return .init(triggered: raw != baseline, baseline: raw,
                         message: raw == baseline ? "Yeni release yok" : "Yeni release: \(reading.displayValue)")
        case .metricAbove(_, let threshold):
            let value = reading.numericValue ?? 0
            return .init(triggered: value >= threshold, baseline: task.baseline,
                         message: "\(reading.displayValue) · eşik \(WatchFormatting.number(threshold))")
        case .metricBelow(_, let threshold):
            let value = reading.numericValue ?? 0
            return .init(triggered: value <= threshold, baseline: task.baseline,
                         message: "\(reading.displayValue) · eşik \(WatchFormatting.number(threshold))")
        }
    }

    public static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum PriceExtractor {
    public static func firstPrice(in text: String) -> Double? {
        let patterns = [
            #"(?:₺|TL|TRY|\$|€|£)\s*([0-9][0-9\.,\s]{0,18})"#,
            #"([0-9][0-9\.,\s]{0,18})\s*(?:₺|TL|TRY|USD|EUR|\$|€|£)"#
        ]
        for pattern in patterns {
            if let value = match(pattern, in: text).flatMap(parseNumber) { return value }
        }
        return nil
    }

    private static func match(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[swiftRange])
    }

    public static func parseNumber(_ raw: String) -> Double? {
        var value = raw.replacingOccurrences(of: " ", with: "")
        let commaCount = value.filter { $0 == "," }.count
        let dotCount = value.filter { $0 == "." }.count
        if commaCount > 0, dotCount > 0 {
            if value.lastIndex(of: ",")! > value.lastIndex(of: ".")! {
                value = value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                value = value.replacingOccurrences(of: ",", with: "")
            }
        } else if commaCount == 1, let comma = value.firstIndex(of: ",") {
            let decimals = value.distance(from: value.index(after: comma), to: value.endIndex)
            value = decimals == 3 ? value.replacingOccurrences(of: ",", with: "") : value.replacingOccurrences(of: ",", with: ".")
        } else if dotCount == 1, let dot = value.firstIndex(of: ".") {
            let decimals = value.distance(from: value.index(after: dot), to: value.endIndex)
            if decimals == 3 { value = value.replacingOccurrences(of: ".", with: "") }
        } else if commaCount > 1 {
            value = value.replacingOccurrences(of: ",", with: "")
        } else if dotCount > 1 {
            value = value.replacingOccurrences(of: ".", with: "")
        }
        return Double(value)
    }
}

public enum WatchFormatting {
    public static func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
