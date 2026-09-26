import Foundation

/// Rules/review export boundary. Writes the local survey packet. No network.
protocol SurveyExporting: Sendable {
    func write(_ session: SurveySession, to directory: URL) throws -> URL
}

struct JSONSurveyExporter: SurveyExporting {
    func write(_ session: SurveySession, to directory: URL) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let url = directory.appendingPathComponent("survey.json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
