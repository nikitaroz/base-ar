import MapKit

struct AddressSuggestion: Identifiable, Equatable, Sendable {
    var title: String
    var subtitle: String

    var id: String { "\(title)|\(subtitle)" }

    var singleLine: String {
        let detail = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty { return title }
        return "\(title), \(detail)"
    }
}

/// Address query completions for the property identifier. This is not the battery position.
@MainActor
@Observable
final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [AddressSuggestion] = []

    private let completer = MKLocalSearchCompleter()
    private var query = ""
    private var showsSuggestions = true

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func updateQuery(_ text: String) {
        if text == query, !showsSuggestions {
            return
        }
        showsSuggestions = true
        query = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            completer.queryFragment = ""
            return
        }
        completer.queryFragment = text
    }

    func accept(_ suggestion: AddressSuggestion) -> String {
        showsSuggestions = false
        suggestions = []
        query = suggestion.singleLine
        return suggestion.singleLine
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let fragment = completer.queryFragment
        let lines = completer.results.prefix(5).map {
            AddressSuggestion(title: $0.title, subtitle: $0.subtitle)
        }
        Task { @MainActor in
            guard self.showsSuggestions, fragment == self.query else { return }
            self.suggestions = lines
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
        }
    }
}
