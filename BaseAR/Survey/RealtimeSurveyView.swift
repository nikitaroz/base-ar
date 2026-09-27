import SwiftUI

/// Live scan: AR find meter → panel → placement. The AR view owns the only two lines of text on the camera.
/// TypeSafe Jev coaching stays behind the menu so it never competes with them.
struct RealtimeSurveyView: View {
    var store: SurveyStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingJevCoaching = false

    var body: some View {
        PlacementARView(store: store) {
            dismiss()
        }
        .navigationTitle("Live Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Back to survey") {
                        dismiss()
                    }
                    Button("Get Tips") {
                        showingJevCoaching = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingJevCoaching) {
            NavigationStack {
                TypeSafeJevCoachingView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingJevCoaching = false }
                        }
                    }
            }
        }
    }

}

/// Minimal coaching detail view (replaces verbose advisory panel)
struct TypeSafeJevCoachingView: View {
    var store: SurveyStore
    @State private var response: TypeSafeJevResponse?
    @State private var isLoading = false
    @State private var error: String?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Analyzing survey...")
            } else if let error {
                ContentUnavailableView {
                    Label("Coaching Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else if let response {
                List {
                    Section("Readiness") {
                        HStack {
                            Text("Visit Ready")
                            Spacer()
                            Text(response.visitReady?.description ?? "unknown")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Readiness Score")
                            Spacer()
                            Text("\(Int(response.readinessScore ?? 0))/3")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if let nextAction = response.nextAction {
                        Section("Next Action") {
                            Text(nextActionDescription(nextAction))
                        }
                    }
                    
                    if let gap = response.blockingGap, gap != "none" {
                        Section("Priority") {
                            Text(gapDescription(gap))
                        }
                    }
                    
                    Section {
                        Text("Advisory only — does not override measured placement color or rule outcomes.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Coaching Available",
                    systemImage: "sparkles",
                    description: Text("Complete the survey to receive guidance.")
                )
            }
        }
        .navigationTitle("Survey Coaching")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCoaching()
        }
    }
    
    private func loadCoaching() async {
        guard let apiKey = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"] else {
            error = "API key not configured"
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let client = TypeSafeJevClient(apiKey: apiKey)
            response = try await client.fetchAdvisory(session: store.session)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func nextActionDescription(_ action: String) -> String {
        switch action {
        case "proceed": return "Survey looks complete. Ready for engineer review."
        case "need_more_photos": return "Capture additional photos for evidence."
        case "conflict": return "Review placement conflicts and clearances."
        default: return "Review current findings."
        }
    }
    
    private func gapDescription(_ gap: String) -> String {
        switch gap {
        case "footprint": return "Check 3×3 ft battery footprint clearance"
        case "transfer_switch": return "Verify transfer switch space beside meter"
        case "ocr": return "Confirm meter number and breaker amperage"
        case "photos": return "Add context photos for evidence"
        case "form": return "Complete home information"
        case "distances": return "Check clearance distances"
        default: return gap
        }
    }
}
