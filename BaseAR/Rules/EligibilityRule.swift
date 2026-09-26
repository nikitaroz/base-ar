import Foundation

/// One configurable check. `evaluate` may only use evidence already on the session.
/// The evaluator combines the outcome with the rule's id, title, and requirement.
struct EligibilityRule: Sendable, Identifiable {
    var id: String
    var title: String
    var requirement: String
    var isRequired: Bool
    var evaluate: @Sendable (SurveySession) -> RuleOutcome
}

/// What a rule found. `pass` and `conflict` always come from captured evidence; `unknown` never does.
struct RuleOutcome: Sendable, Equatable {
    var status: CheckStatus
    var usedMeasuredEvidence: Bool
    var explanation: String

    static func pass(_ explanation: String) -> RuleOutcome {
        RuleOutcome(status: .pass, usedMeasuredEvidence: true, explanation: explanation)
    }

    static func conflict(_ explanation: String) -> RuleOutcome {
        RuleOutcome(status: .conflict, usedMeasuredEvidence: true, explanation: explanation)
    }

    static func unknown(_ explanation: String) -> RuleOutcome {
        RuleOutcome(status: .unknown, usedMeasuredEvidence: false, explanation: explanation)
    }
}

struct SurveyAssessment: Sendable, Equatable {
    var results: [RuleResult]
    var placementTone: PlacementTone
    var missingInformation: [String]
}

enum PlacementTonePolicy {
    static func tone(for results: [RuleResult]) -> PlacementTone {
        let required = results.filter(\.isRequired)
        if required.contains(where: { $0.status == .conflict }) {
            return .conflict
        }
        guard !required.isEmpty, required.allSatisfy({ $0.status == .pass }) else {
            return .incomplete
        }
        // At least one required pass used a user attestation instead of a measurement: distinct tone so the JSON and UI are honest.
        let anyAttested = required.contains { !$0.usedMeasuredEvidence }
        return anyAttested ? .attested : .clear
    }
}
