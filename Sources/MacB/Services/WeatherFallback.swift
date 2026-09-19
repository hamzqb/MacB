import Foundation
import Security

/// A second place to ask about the weather, for when Open-Meteo does not answer.
///
/// Open-Meteo is the first choice and needs no account, no key and no location
/// permission, which is why MacB uses it. It is also a free service that can be
/// slow or briefly unreachable, and an island widget that says nothing is worse
/// than one that says it is cold. OpenWeatherMap fills that gap when a key is
/// stored, and is never asked otherwise.
///
/// The key lives in the Keychain like every other key MacB holds, and goes
/// nowhere but OpenWeatherMap. What leaves is a place name or a pair of
/// coordinates for the place the user typed into Settings — no identifier, and
/// nothing about the Mac.
enum WeatherFallback {
    static let service = "dev.hamzababal.MacB.ai"
    static let account = "openweather"

    static func hasKey() -> Bool {
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    @discardableResult
    static func save(_ raw: String) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // An OpenWeatherMap key is 32 hexadecimal characters and nothing else.
        guard key.count == 32, key.allSatisfy(\.isHexDigit), let data = key.data(using: .utf8) else {
            return false
        }
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecAttrLabel as String] = "MacB — OpenWeatherMap"
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func remove() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// The weather now, for a place name. `nil` when there is no key, so the
    /// caller can keep Open-Meteo's own error rather than invent one.
    static func current(place: String, session: URLSession) async -> WeatherSnapshot? {
        guard let key = read() else { return nil }
        var components = URLComponents(string: "https://api.openweathermap.org/data/2.5/weather")
        components?.queryItems = [
            URLQueryItem(name: "q", value: place),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "lang", value: "tr"),
            URLQueryItem(name: "appid", value: key)
        ]
        guard let url = components?.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let main = object["main"] as? [String: Any],
              let temperature = main["temp"] as? Double else { return nil }
        let weather = (object["weather"] as? [[String: Any]])?.first ?? [:]
        let icon = weather["icon"] as? String ?? ""
        let isDay = icon.hasSuffix("d")
        return WeatherSnapshot(
            place: object["name"] as? String ?? place,
            temperature: Int(temperature.rounded()),
            feelsLike: Int((main["feels_like"] as? Double ?? temperature).rounded()),
            condition: (weather["description"] as? String ?? "").capitalized(with: Locale(identifier: "tr_TR")),
            symbol: symbol(for: icon),
            isDay: isDay)
    }

    /// OpenWeatherMap's icon codes, as SF Symbols.
    private static func symbol(for icon: String) -> String {
        let night = icon.hasSuffix("n")
        switch icon.prefix(2) {
        case "01": return night ? "moon.stars.fill" : "sun.max.fill"
        case "02": return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case "03", "04": return "cloud.fill"
        case "09": return "cloud.drizzle.fill"
        case "10": return night ? "cloud.moon.rain.fill" : "cloud.sun.rain.fill"
        case "11": return "cloud.bolt.rain.fill"
        case "13": return "cloud.snow.fill"
        case "50": return "cloud.fog.fill"
        default: return "cloud.fill"
        }
    }
}
