import Foundation

/// Single façade for every ERCOT / load-zone consumer in the app. Prices come from a
/// swappable `PricingSource`; callers never touch it directly.
///
/// To go live: set `livePriceURL` to a URL that serves JSON in the same shape as
/// `ERCOTPricesSample.json`, then call `try await GridService.refresh()` once on app
/// boot. Everything else — the decision card, the Review summary, the survey.json
/// export — keeps working unchanged.
enum GridService {
    /// Set to a URL to enable a live `URLPricingSource`. Nil (default) uses the bundled
    /// sample only. See `PricingSource.swift` for the expected JSON shape.
    private static let livePriceURL: URL? = nil

    private static let source: PricingSource = {
        if let url = livePriceURL {
            return URLPricingSource(url: url)
        }
        return BundledPricingSource()
    }()

    /// Resolve the ERCOT load zone from a free-form property identifier.
    static func zone(for propertyIdentifier: String) -> ERCOTLoadZone? {
        LoadZoneLookup.zone(for: propertyIdentifier)
    }

    /// The current price snapshot. Bundled today; a live-fetch cache once `livePriceURL`
    /// is set. Never nil — falls back to bundled when a live source hasn't landed yet.
    static var sampleDay: ERCOTSampleDay { source.current }

    /// Convenience: prices for one zone in the current snapshot.
    static func zonePrice(for zone: ERCOTLoadZone) -> ZonePrice? {
        sampleDay.prices[zone]
    }

    /// Force the underlying source to pull fresh prices. `BundledPricingSource` no-ops;
    /// `URLPricingSource` fetches and updates its cache. Safe to call at app boot; safe
    /// to ignore.
    static func refresh() async throws {
        try await source.refresh()
    }
}
