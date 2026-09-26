import SwiftUI

/// Single unified realtime feedback screen: live AR + equipment detection + rules + Jev coaching.
/// Replaces the verbose 9-step guided photo checklist with continuous observation.
struct RealtimeSurveyView: View {
    var store: SurveyStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingJevCoaching = false
    @State private var jevNextAction: String?
    @State private var isLoadingJev = false
    
    var body: some View {
        ZStack(alignment: .top) {
            // Full-screen AR with embedded equipment detection and placement
            PlacementARView(store: store) {
                // onContinue: user can save and exit from AR controls
            }
            
            // Overlay: Status chips + Jev coaching
            VStack(spacing: 12) {
                // Live status chips
                HStack(spacing: 8) {
                    statusChip(
                        icon: "location.circle.fill",
                        text: locationStatus,
                        color: store.session.propertyLocation != nil ? .green : .orange
                    )
                    statusChip(
                        icon: "bolt.circle.fill",
                        text: electricalStatus,
                        color: electricalColor
                    )
                    statusChip(
                        icon: "cube.box.fill",
                        text: placementStatus,
                        color: placementColor
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Jev coaching chip (when available)
                if let action = jevNextAction {
                    Button {
                        showingJevCoaching.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text(action)
                                .font(.subheadline)
                                .lineLimit(2)
                            Spacer()
                            Image(systemName: showingJevCoaching ? "chevron.up" : "chevron.down")
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 16)
                }
                
                Spacer()
            }
        }
        .navigationTitle("Live Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("View Results") {
                        // Navigate to minimal review screen
                    }
                    Button("Get Tips") {
                        fetchJevCoaching()
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
        .onAppear {
            // Fetch initial Jev coaching after a short delay
            Task {
                try? await Task.sleep(for: .seconds(2))
                fetchJevCoaching()
            }
        }
    }
    
    private func statusChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.gradient, in: Capsule())
    }
    
    private var locationStatus: String {
        store.session.propertyLocation != nil ? "Located" : "Tap for location"
    }
    
    private var electricalStatus: String {
        let hasMeter = store.session.electrical.meterNumber != nil
        let hasBreaker = store.session.electrical.mainBreakerAmperage != nil
        if hasMeter && hasBreaker { return "Scanned" }
        if hasMeter || hasBreaker { return "Partial" }
        return "Point at meter"
    }
    
    private var electricalColor: Color {
        let hasMeter = store.session.electrical.meterNumber != nil
        let hasBreaker = store.session.electrical.mainBreakerAmperage != nil
        if hasMeter && hasBreaker { return .green }
        if hasMeter || hasBreaker { return .yellow }
        return .orange
    }
    
    private var placementStatus: String {
        if store.session.placement.batteryPlaced {
            return "Placed"
        }
        return "Preview battery"
    }
    
    private var placementColor: Color {
        guard store.session.placement.batteryPlaced else { return .orange }
        switch store.session.placementTone {
        case .clear: return .green
        case .conflict: return .red
        case .incomplete, .attested: return .yellow
        }
    }
    
    private func fetchJevCoaching() {
        guard !isLoadingJev else { return }
        guard let apiKey = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"] else { return }
        
        isLoadingJev = true
        Task {
            defer { isLoadingJev = false }
            do {
                let client = TypeSafeJevClient(apiKey: apiKey)
                let response = try await client.fetchAdvisory(session: store.session)
                
                // Extract next action from response
                if let nextAction = response.nextAction {
                    await MainActor.run {
                        jevNextAction = nextActionDescription(nextAction)
                    }
                }
            } catch {
                // Silently degrade - coaching is optional
                print("Jev coaching unavailable: \(error)")
            }
        }
    }
    
    private func nextActionDescription(_ action: String) -> String {
        switch action {
        case "proceed": return "Looking good! Continue when ready"
        case "need_more_photos": return "Capture additional evidence"
        case "conflict": return "Check placement conflicts"
        default: return "Review findings"
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
