import SwiftUI

/// Optional TypeSafe Jev card for Review. Renders nothing without a key.
/// Advisory only: it never changes a check, the placement tone, or its color, so it uses no tone colors.
struct TypeSafeJevAdvisoryView: View {
    let session: SurveySession
    var client = TypeSafeJevClient()

    @State private var advisory: JevAdvisory?
    @State private var askedAbout: SurveySession?
    @State private var isLoading = false
    @State private var isExpanded = false

    var body: some View {
        if client.isAvailable {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    Text("Advisory only. It never changes the checks or the placement color, and it is not installation approval. Asking sends a summary of the checks and your home answers to TypeSafe. No name, contact details, address, location, meter number, or photos are sent.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    content
                    Button {
                        Task { await ask() }
                    } label: {
                        Label(advisory == nil ? "Ask for advice" : "Ask again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                }
                .padding(.top, 8)
            } label: {
                Label("Jev advisory", systemImage: "brain.head.profile")
                    .font(.headline)
            }
            .tint(.primary)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .onChange(of: isExpanded) { _, expanded in
                if expanded, advisory == nil, !isLoading {
                    Task { await ask() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Asking Jev…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if let advisory {
            switch advisory.status {
            case .unavailable:
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Advisory unavailable")
                            .font(.subheadline.weight(.semibold))
                        Text(advisory.reason ?? "Try again later. The survey is unaffected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(.secondary)
                }
            case .available:
                answers(advisory)
            }
            if askedAbout != session {
                Text("The survey changed since this advice. Ask again for an update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func answers(_ advisory: JevAdvisory) -> some View {
        let answers = advisory.answers ?? [:]
        VStack(alignment: .leading, spacing: 10) {
            if let visitReady = advisory.visitReady {
                // noul carries the probability of "yes"; show how sure Jev is of the word it lands on.
                let sureness = advisory.visitReadyProbability.map { visitReady == "yes" ? $0 : 1 - $0 }
                row("Ready for engineer review?", value: words(visitReady), confidence: sureness)
            }
            if let nextAction = advisory.nextAction {
                row("Next step", value: words(nextAction), confidence: answers["next_action"]?.confidence)
            }
            if let gap = advisory.blockingGap, gap != "none" {
                row("Biggest gap", value: words(gap), confidence: answers["blocking_gap"]?.confidence)
            }
            if let score = advisory.readinessScore {
                row("Readiness", value: "\(score.formatted(.number.precision(.fractionLength(1)))) of 3", confidence: answers["readiness_score"]?.confidence)
            }
            if advisory.visitReady == nil, advisory.nextAction == nil, advisory.blockingGap == nil, advisory.readinessScore == nil {
                Text("Jev sent no answers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ title: String, value: String, confidence: Double?) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                Text(value)
                    .foregroundStyle(.primary)
                if let confidence {
                    Text(confidence.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Text(title)
        }
        .font(.subheadline)
    }

    private func words(_ raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    private func ask() async {
        guard client.isAvailable, !isLoading else { return }
        isLoading = true
        let snapshot = session
        let result = await client.advisory(for: snapshot)
        advisory = result
        askedAbout = snapshot
        isLoading = false
    }
}
