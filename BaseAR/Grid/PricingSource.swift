import Foundation
import os

/// A source of ERCOT price snapshots. `current` is a sync accessor that always returns
/// something (falling back to the bundled sample when nothing else is available), so the
/// UI stays synchronous. `refresh()` is the seam for a live implementation to pull fresh
/// data in the background; a bundled implementation just no-ops it.
protocol PricingSource: Sendable {
    var current: ERCOTSampleDay { get }
    func refresh() async throws
}

/// Reads the ERCOT sample day from the bundled JSON. `refresh()` is a no-op because the
/// data is static; the JSON is parsed once by `ERCOTSampleDay.bundled` on first access.
struct BundledPricingSource: PricingSource {
    var current: ERCOTSampleDay { .bundled }
    func refresh() async throws {}
}

/// A live `PricingSource` that pulls JSON matching the bundled schema from a URL and caches
/// the result in memory. Before the first successful `refresh()` — or after a failure —
/// `current` transparently falls back to the bundled sample, so the card always renders.
///
/// The URL must serve JSON with the same shape as `ERCOTPricesSample.json` (a `sampleDate`
/// string plus a `zones` dict). Update it on whatever cadence you like — a nightly script
/// writing a static file or a Gist works. The app never needs to know how the file is
/// produced.
final class URLPricingSource: PricingSource {
    private let url: URL
    private let session: URLSession
    private let cached = OSAllocatedUnfairLock<ERCOTSampleDay?>(initialState: nil)

    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    var current: ERCOTSampleDay {
        cached.withLock { $0 ?? .bundled }
    }

    func refresh() async throws {
        let (data, _) = try await session.data(from: url)
        let snapshot = try JSONDecoder().decode(ERCOTSampleDay.self, from: data)
        cached.withLock { $0 = snapshot }
    }
}
