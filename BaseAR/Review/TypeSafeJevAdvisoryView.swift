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
    #if DEBUG
    @State private var debugOutput: String?
    @State private var debugRunning = false
    #endif

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
                    #if DEBUG
                    liveLaneDebug
                    #endif
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
            // Readiness itself comes from the checks (the card at the top of Review), not from Jev.
            if let nextAction = advisory.nextAction {
                row("Next step", value: words(nextAction), confidence: answers["next_action"]?.confidence)
            }
            if let gap = advisory.blockingGap, gap != "none" {
                row("Biggest gap", value: words(gap), confidence: answers["blocking_gap"]?.confidence)
            }
            if let score = advisory.readinessScore {
                row("Readiness", value: "\(score.formatted(.number.precision(.fractionLength(1)))) of 3", confidence: answers["readiness_score"]?.confidence)
            }
            if advisory.nextAction == nil, advisory.blockingGap == nil, advisory.readinessScore == nil {
                Text("Jev sent no answers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            #if DEBUG
            Text("\(advisory.model ?? "model ?") · \(advisory.usage?.inputTokens.map { "\($0) tokens in" } ?? "tokens ?")"
                + (advisory.roundTrip.map { " · \(JevTransport.milliseconds($0)) ms" } ?? "")
                + (advisory.requestID.map { " · \($0)" } ?? ""))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            #endif
        }
    }

    private func row(_ title: String, value: String, confidence: Double?) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                Text(value)
                    .foregroundStyle(.primary)
                // Choice and Score `confidence` (how peaked Jev's own distribution is), not a probability of yes.
                if let confidence {
                    Text("\(confidence.formatted(.percent.precision(.fractionLength(0)))) confidence")
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

    #if DEBUG
    /// Test hooks for the Live Survey's Jev lane. Reports also print to the Xcode console.
    private var liveLaneDebug: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Live lane (DEBUG)")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                debugButton("Self-check") { JevLiveDebug.selfCheck() }
                debugButton("Replay") { await JevLiveDebug.replay() }
            }
            HStack(spacing: 8) {
                debugButton("Probe") { await JevLiveDebug.probe() }
                debugButton("Latency ×20") { await JevLiveDebug.latency() }
            }
            if debugRunning {
                ProgressView()
                    .controlSize(.small)
            }
            if let debugOutput {
                ScrollView(.horizontal) {
                    Text(debugOutput)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private func debugButton(_ title: String, _ run: @escaping @MainActor () async -> String) -> some View {
        Button(title) {
            Task {
                debugRunning = true
                debugOutput = await run()
                debugRunning = false
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(debugRunning)
    }
    #endif

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
