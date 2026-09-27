import Foundation

/// Single façade for every ERCOT / load-zone consumer in the app. When we later swap the bundled
/// sample for a live ERCOT feed, only this file changes — callers keep the same shape.
enum GridService {
    /// Resolve the ERCOT load zone from a free-form property identifier.
    static func zone(for propertyIdentifier: String) -> ERCOTLoadZone? {
        LoadZoneLookup.zone(for: propertyIdentifier)
    }

    /// The bundled sample day of ERCOT prices. Later: `currentPrices(for:) async` without changing callers.
    static var sampleDay: ERCOTSampleDay { .bundled }

    /// Convenience: prices for one zone on the bundled sample day.
    static func zonePrice(for zone: ERCOTLoadZone) -> ZonePrice? {
        sampleDay.prices[zone]
    }
}
