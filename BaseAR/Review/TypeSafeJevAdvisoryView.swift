import SwiftUI

/// TypeSafe Jev advisory panel for the review screen. Advisory only — never overrides placement color.
struct TypeSafeJevAdvisoryView: View {
    let session: SurveySession
    let client: TypeSafeJevClient
    
    @State private var advisory: JevAdvisory?
    @State private var isLoading = false
    @State private var isExpanded = false
    @State private var isAvailable = false
    
    var body: some View {
        if isAvailable {
            advisoryPanel
        }
    }
    
    private var advisoryPanel: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                
                if isLoading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking advisory...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let advisory {
                    advisoryContent(advisory)
                } else {
                    Text("Tap Refresh to check readiness advisory")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh advisory", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }
            .padding(.top, 8)
        } label: {
            Label("Jev Advisory", systemImage: "brain.head.profile")
                .font(.headline)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .task {
            isAvailable = await client.isAvailable
        }
    }
    
    @ViewBuilder
    private func advisoryContent(_ advisory: JevAdvisory) -> some View {
        switch advisory.status {
        case .unavailable:
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Advisory unavailable")
                        .font(.subheadline.weight(.semibold))
                    if let reason = advisory.reason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            
        case .available:
            if let answers = advisory.answers {
                VStack(alignment: .leading, spacing: 10) {
                    if let visitReady = advisory.visitReady {
                        answerRow(
                            title: "Visit ready",
                            value: visitReady,
                            confidence: answers["visit_ready"]?.confidence
                        )
                    }
                    
                    if let nextAction = advisory.nextAction {
                        answerRow(
                            title: "Next action",
                            value: formatChoice(nextAction),
                            confidence: answers["next_action"]?.confidence
                        )
                    }
                    
                    if let blockingGap = advisory.blockingGap, blockingGap != "none" {
                        answerRow(
                            title: "Blocking gap",
                            value: formatChoice(blockingGap),
                            confidence: answers["blocking_gap"]?.confidence,
                            highlight: true
                        )
                    }
                    
                    if let score = advisory.readinessScore {
                        HStack {
                            Text("Readiness score")
                                .font(.subheadline)
                            Spacer()
                            Text("\(score)/3")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(scoreColor(score))
                        }
                    }
                }
            }
        }
    }
    
    private func answerRow(title: String, value: String, confidence: Double?, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                Text(value)
                    .font(.subheadline.weight(highlight ? .semibold : .regular))
                    .foregroundStyle(highlight ? .orange : .primary)
                
                if let confidence {
                    Spacer()
                    Text(String(format: "%.0f%%", confidence * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func formatChoice(_ choice: String) -> String {
        choice.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 0...1: .red
        case 2: .orange
        case 3: .green
        default: .secondary
        }
    }
    
    private func refresh() async {
        isLoading = true
        let result = await client.advisory(for: session)
        advisory = result
        isLoading = false
    }
}
