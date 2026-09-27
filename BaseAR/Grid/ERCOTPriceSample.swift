import Foundation

/// Prices in one ERCOT load zone for one sample day. Room to grow (`intradaySeries`, `forecast`,
/// `historicalMedian`) by adding optional keys — old code decodes the subset it needs.
struct ZonePrice: Sendable, Codable, Equatable {
    let cheapHourPriceUSDPerMWh: Double
    let expensiveHourPriceUSDPerMWh: Double
    let cheapHourLabel: String
    let expensiveHourLabel: String
}

/// One day of bundled ERCOT sample prices keyed by load zone. The JSON schema is intentionally
/// simple so a future live feed can adapt to it (or vice versa) without breaking callers.
struct ERCOTSampleDay: Sendable, Codable {
    let date: Date
    let prices: [ERCOTLoadZone: ZonePrice]

    /// Memoized bundled sample. Safe to read repeatedly; the JSON is parsed once.
    static let bundled: ERCOTSampleDay = load()

    private enum CodingKeys: String, CodingKey {
        case sampleDate
        case zones
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .sampleDate)
        guard let parsed = Self.dateFormatter.date(from: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .sampleDate, in: container, debugDescription: "expected yyyy-MM-dd")
        }
        date = parsed
        // Zones is a String → ZonePrice dict in JSON; convert to ERCOTLoadZone keys, dropping unknown codes.
        let rawZones = try container.decode([String: ZonePrice].self, forKey: .zones)
        var mapped: [ERCOTLoadZone: ZonePrice] = [:]
        for (code, price) in rawZones {
            if let zone = ERCOTLoadZone(rawValue: code) {
                mapped[zone] = price
            }
        }
        prices = mapped
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.dateFormatter.string(from: date), forKey: .sampleDate)
        var rawZones: [String: ZonePrice] = [:]
        for (zone, price) in prices {
            rawZones[zone.rawValue] = price
        }
        try container.encode(rawZones, forKey: .zones)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Chicago")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func load() -> ERCOTSampleDay {
        guard let url = Bundle.main.url(forResource: "ERCOTPricesSample", withExtension: "json") else {
            return empty
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ERCOTSampleDay.self, from: data)
        } catch {
            return empty
        }
    }

    /// Fallback used only when the bundle is missing the resource. Keeps callers non-optional
    /// so the card can render its non-price lines even in a broken configuration.
    private static let empty = ERCOTSampleDay(date: Date(), prices: [:])

    private init(date: Date, prices: [ERCOTLoadZone: ZonePrice]) {
        self.date = date
        self.prices = prices
    }
}
