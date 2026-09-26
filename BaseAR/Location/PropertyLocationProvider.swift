import CoreLocation
import Foundation

/// One-shot property fix. Callers must not treat this as the battery coordinate.
@MainActor
final class PropertyLocationProvider: NSObject, CLLocationManagerDelegate {
    var onFix: ((GeoFix) -> Void)?
    var onStatus: ((String?) -> Void)?

    /// Matches `NSLocationTemporaryUsageDescriptionDictionary` in Info.plist.
    private let precisePurposeKey = "PropertyFix"
    private let manager = CLLocationManager()
    private var didRequestFix = false
    private var userRequestedLocation = false
    private nonisolated static let deniedMessage = "Location access is off. Allow location for Base Site Survey in Settings, then try again."
    private nonisolated static let failedMessage = "The property fix failed. Try again."

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func request() {
        userRequestedLocation = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestSingleFix()
        case .denied, .restricted:
            onStatus?(Self.deniedMessage)
        @unknown default:
            onStatus?(Self.failedMessage)
        }
    }

    func retry() {
        didRequestFix = false
        onStatus?(nil)
        request()
    }

    private func requestSingleFix() {
        guard !didRequestFix else { return }
        didRequestFix = true
        onStatus?(nil)
        if manager.accuracyAuthorization == .reducedAccuracy {
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: precisePurposeKey) { [weak self] _ in
                Task { @MainActor in
                    self?.manager.requestLocation()
                }
            }
            return
        }
        manager.requestLocation()
    }

    private func noteFailure(_ message: String) {
        didRequestFix = false
        onStatus?(message)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.userRequestedLocation else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                self.requestSingleFix()
            case .denied, .restricted:
                self.noteFailure(Self.deniedMessage)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Core Location uses 0 or negative for "no accuracy available"; > 500 m is too coarse for a property fix.
        guard location.horizontalAccuracy > 0, location.horizontalAccuracy <= 500 else {
            Task { @MainActor in
                self.noteFailure(Self.failedMessage)
            }
            return
        }
        let fix = GeoFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            horizontalAccuracyMeters: location.horizontalAccuracy
        )
        Task { @MainActor in
            self.onFix?(fix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = Self.failureMessage(for: error)
        Task { @MainActor in
            self.noteFailure(message)
        }
    }

    private nonisolated static func failureMessage(for error: Error) -> String {
        guard let code = (error as? CLError)?.code else { return failedMessage }
        switch code {
        case .denied:
            return deniedMessage
        default:
            return failedMessage
        }
    }
}
