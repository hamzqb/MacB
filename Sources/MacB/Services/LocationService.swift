import CoreLocation
import Foundation

struct WeatherLocation: Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
}

/// One-shot location for weather. It does not track movement and does not write
/// coordinates to disk: the coordinate lives only long enough to ask the weather
/// service, then a human-readable city name is kept on the snapshot.
@MainActor final class LocationService: NSObject, CLLocationManagerDelegate {
    enum Failure: Error, LocalizedError {
        case unavailable
        case denied
        case noFix

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Konum bu Mac'te kullanılamıyor."
            case .denied: return "Konum izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Konum Servisleri'nden MacB'yi aç."
            case .noFix: return "Konum alınamadı."
            }
        }
    }

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var continuation: CheckedContinuation<WeatherLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 5_000
    }

    func requestCurrentLocation() async throws -> WeatherLocation {
        guard CLLocationManager.locationServicesEnabled() else { throw Failure.unavailable }
        if continuation != nil { throw Failure.noFix }
        switch manager.authorizationStatus {
        case .restricted, .denied:
            throw Failure.denied
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .restricted, .denied:
                finish(.failure(Failure.denied))
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            Task { @MainActor in finish(.failure(Failure.noFix)) }
            return
        }
        Task { @MainActor in
            let name = await displayName(for: location)
            finish(.success(WeatherLocation(name: name,
                                            latitude: location.coordinate.latitude,
                                            longitude: location.coordinate.longitude)))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(.failure(error)) }
    }

    private func displayName(for location: CLLocation) async -> String {
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return "Yakınımda"
        }
        if let locality = placemark.locality, !locality.isEmpty { return locality }
        if let area = placemark.administrativeArea, !area.isEmpty { return area }
        if let country = placemark.country, !country.isEmpty { return country }
        return "Yakınımda"
    }

    private func finish(_ result: Result<WeatherLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let location): continuation.resume(returning: location)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}
