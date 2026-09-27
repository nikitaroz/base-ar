import Foundation

/// Pure ZIP → ERCOT load-zone mapping. Bundled sample only — not a full Texas coverage.
/// Unknown or non-Texas ZIPs return nil so the caller can gracefully omit the price line.
enum LoadZoneLookup {
    /// Bundled Texas ZIP → zone map. Two to three ZIPs per zone, enough to demo, honest about being a sample.
    private static let byZIP: [String: ERCOTLoadZone] = [
        // LZ_AEN (Central / Austin)
        "78701": .aen,
        "78753": .aen,
        // LZ_NORTH (Dallas / Fort Worth)
        "75201": .north,
        "76102": .north,
        // LZ_SOUTH (San Antonio / Corpus Christi)
        "78201": .south,
        "78401": .south,
        // LZ_HOUSTON
        "77002": .houston,
        "77494": .houston,
        // LZ_WEST (El Paso / Abilene)
        "79901": .west,
        "79601": .west
    ]

    static func zone(for propertyIdentifier: String) -> ERCOTLoadZone? {
        guard let zip = extractZIP(from: propertyIdentifier) else { return nil }
        return byZIP[zip]
    }

    /// Pulls the first 5-digit sequence out of a free-form address string.
    /// Accepts either a raw ZIP or a full street address; ignores 9-digit ZIP+4 by taking only the first five digits.
    static func extractZIP(from text: String) -> String? {
        // Match a 5-digit sequence not immediately preceded or followed by another digit.
        // This avoids catching 4-digit house numbers or the second half of a ZIP+4.
        guard let regex = try? NSRegularExpression(pattern: "(?<!\\d)\\d{5}(?!\\d)") else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
