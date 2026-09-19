import Combine
import Foundation

struct WeatherSnapshot: Equatable {
    var place: String
    var temperature: Int
    var feelsLike: Int
    var condition: String
    var symbol: String
    var isDay: Bool
}

/// Weather from Open-Meteo. No account, no API key, and no location permission:
/// the place is a name the user types, resolved through the same service.
///
/// This is MacB's only outbound request besides Spotify artwork, so it stays off
/// until the user enables it and never runs while the panel is hidden.
@MainActor final class WeatherService: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let session: URLSession
    private var task: Task<Void, Never>?
    private var lastFetch: Date?
    private var isVisible = false
    private var refreshTimer: Timer?

    /// Open-Meteo asks for at most one call every few minutes for a single location.
    private let minimumInterval: TimeInterval = 900

    var placeQuery: String {
        didSet {
            guard placeQuery != oldValue else { return }
            UserDefaults.standard.set(placeQuery, forKey: "weatherPlace")
            snapshot = nil
            lastFetch = nil
            if isVisible { refresh(force: true) }
        }
    }

    init(session: URLSession = .shared) {
        self.session = session
        placeQuery = UserDefaults.standard.string(forKey: "weatherPlace") ?? ""
    }

    func setPanelVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            refresh()
            let timer = Timer(timeInterval: minimumInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            refreshTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            task?.cancel()
            task = nil
        }
    }

    func refresh(force: Bool = false) {
        let place = placeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else {
            errorMessage = nil
            return
        }
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < minimumInterval { return }
        task?.cancel()
        isLoading = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let location = try await Self.geocode(place, session: session)
                let current = try await Self.currentWeather(location, session: session)
                guard !Task.isCancelled else { return }
                snapshot = current
                errorMessage = nil
                lastFetch = Date()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                // Open-Meteo did not answer. Ask the second source, if there is
                // one, before telling the user there is no weather.
                if let fallback = await WeatherFallback.current(place: place, session: session) {
                    guard !Task.isCancelled else { return }
                    snapshot = fallback
                    errorMessage = nil
                    lastFetch = Date()
                } else {
                    errorMessage = "Hava durumu alınamadı."
                }
            }
            isLoading = false
        }
    }

    // MARK: - Requests

    private struct Location {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    private static func geocode(_ place: String, session: URLSession) async throws -> Location {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: place),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "tr"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]],
              let first = results.first,
              let latitude = first["latitude"] as? Double,
              let longitude = first["longitude"] as? Double else {
            throw URLError(.cannotParseResponse)
        }
        return Location(name: first["name"] as? String ?? place, latitude: latitude, longitude: longitude)
    }

    private static func currentWeather(_ location: Location, session: URLSession) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = object["current"] as? [String: Any],
              let temperature = current["temperature_2m"] as? Double,
              let code = current["weather_code"] as? Int else {
            throw URLError(.cannotParseResponse)
        }
        let isDay = (current["is_day"] as? Int ?? 1) == 1
        let description = WeatherCode.describe(code, isDay: isDay)
        return WeatherSnapshot(
            place: location.name,
            temperature: Int(temperature.rounded()),
            feelsLike: Int((current["apparent_temperature"] as? Double ?? temperature).rounded()),
            condition: description.text,
            symbol: description.symbol,
            isDay: isDay)
    }
}

/// WMO weather codes as Open-Meteo reports them.
enum WeatherCode {
    static func describe(_ code: Int, isDay: Bool) -> (text: String, symbol: String) {
        switch code {
        case 0: return ("Açık", isDay ? "sun.max.fill" : "moon.stars.fill")
        case 1, 2: return ("Parçalı bulutlu", isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3: return ("Kapalı", "cloud.fill")
        case 45, 48: return ("Sisli", "cloud.fog.fill")
        case 51, 53, 55, 56, 57: return ("Çiseleme", "cloud.drizzle.fill")
        case 61, 63, 65, 66, 67: return ("Yağmurlu", "cloud.rain.fill")
        case 71, 73, 75, 77, 85, 86: return ("Karlı", "cloud.snow.fill")
        case 80, 81, 82: return ("Sağanak", "cloud.heavyrain.fill")
        case 95, 96, 99: return ("Gök gürültülü", "cloud.bolt.rain.fill")
        default: return ("Bilinmiyor", "cloud.fill")
        }
    }
}
