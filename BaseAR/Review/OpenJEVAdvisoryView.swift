import SwiftUI

/// Optional OpenJEV advisory panel for the Review screen.
/// This is strictly advisory and does NOT override measured rule-based checks.
struct OpenJEVAdvisoryView: View {
    var session: SurveySession
    var client: OpenJEVClient
    
    @State private var advisory: OpenJEVAdvisoryResponse?
    @State private var isLoading = false
    @State private var error: String?
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                header
                
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let error {
                    errorView(error)
                } else if let advisory {
                    advisoryContent(advisory)
                } else {
                    Text("Tap to fetch OpenJEV advisory")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
                
                if !isLoading && advisory == nil && error == nil {
                    Button("Fetch Advisory") {
                        Task {
                            await fetchAdvisory()
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                
                if advisory != nil || error != nil {
                    Button("Refresh") {
                        Task {
                            await fetchAdvisory()
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("OpenJEV Advisory", systemImage: "sparkles")
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This is optional advisory guidance only.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Placement color stays on measured rule-based checks.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Advisory unavailable")
                    .font(.subheadline.weight(.semibold))
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
    
    private func advisoryContent(_ response: OpenJEVAdvisoryResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(response.answers) { answer in
                answerRow(answer)
            }
        }
    }
    
    private func answerRow(_ answer: AdvisoryAnswer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(humanReadableKey(answer.key))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let confidence = answer.confidence {
                    Text(answer.displayConfidence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }
            Text(humanReadableValue(key: answer.key, value: answer.displayValue))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
    
    private func humanReadableKey(_ key: String) -> String {
        switch key {
        case "visit_ready": return "Visit Ready"
        case "next_action": return "Next Action"
        case "blocking_gap": return "Priority Gap"
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    private func humanReadableValue(key: String, value: String) -> String {
        switch key {
        case "visit_ready":
            return value == "true" ? "Survey appears ready for engineer visit" : "Survey may need more work"
        case "next_action":
            switch value {
            case "proceed": return "Proceed with current survey"
            case "need_more_photos": return "Need more photos"
            case "conflict": return "Resolve conflicts first"
            default: return value
            }
        case "blocking_gap":
            switch value {
            case "footprint": return "Footprint clearance measurement needed"
            case "transfer_switch": return "Transfer switch clearance needed"
            case "ocr": return "OCR or manual entry needed"
            case "photos": return "Additional photos needed"
            case "form": return "Form fields incomplete"
            case "none": return "No blocking gaps"
            default: return value
            }
        default:
            return value
        }
    }
    
    private func fetchAdvisory() async {
        isLoading = true
        error = nil
        advisory = nil
        
        do {
            let response = try await client.queryAdvisory(session: session)
            await MainActor.run {
                advisory = response
                isLoading = false
            }
        } catch let openJEVError as OpenJEVError {
            await MainActor.run {
                error = openJEVError.localizedDescription
                isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Network error: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}
