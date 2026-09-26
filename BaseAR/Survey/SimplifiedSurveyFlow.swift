import SwiftUI

/// Simplified two-step survey flow: Step 1 (basic info) → Realtime feedback screen (AR + live scanning + rules + Jev)
struct SimplifiedSurveyFlow: View {
    var store: SurveyStore
    var onOpen: (HubRoute) -> Void
    
    @State private var showingRealtimeScreen = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Site Survey")
                    .font(.largeTitle.bold())
                
                Text("Complete step 1, then use the live feedback screen to scan equipment and preview placement in AR.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                
                // Step 1: Basic info
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Step 1: Home Information", systemImage: "house.fill")
                                .font(.headline)
                            Spacer()
                            if step1Complete {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        
                        Text("Name, address, ownership, and energy setup")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Button {
                            onOpen(.home)
                        } label: {
                            Text(step1Complete ? "Review Information" : "Complete Step 1")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(4)
                }
                
                // Realtime feedback screen (enabled after step 1)
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Live Survey", systemImage: "camera.metering.multispot")
                                .font(.headline)
                            Spacer()
                            if !step1Complete {
                                Text("Complete Step 1")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Text("Scan equipment, preview AR placement, see live rule checks and coaching")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if step1Complete {
                            Button {
                                showingRealtimeScreen = true
                            } label: {
                                HStack {
                                    Image(systemName: "arkit")
                                    Text("Open Live Survey")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        } else {
                            Button {} label: {
                                Text("Complete Step 1 First")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(true)
                        }
                    }
                    .padding(4)
                }
                
                // Review (always available)
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Review & Export", systemImage: "square.and.arrow.up")
                            .font(.headline)
                        
                        Text("Check captured evidence and share survey.json")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Button {
                            onOpen(.review)
                        } label: {
                            Text("Review Survey")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(4)
                }
                
                Text(SurveySession.prototypeDisclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Survey")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingRealtimeScreen) {
            NavigationStack {
                RealtimeSurveyView(store: store)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                showingRealtimeScreen = false
                            }
                        }
                    }
            }
        }
    }
    
    private var step1Complete: Bool {
        let session = store.session
        let e = session.electrical
        return !session.contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            session.email.contains("@") && session.email.contains(".") &&
            session.phone.filter(\.isNumber).count >= 7 &&
            !session.propertyIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            session.homeownership != nil &&
            e.hasSolar != nil &&
            e.hasPortableGenerator != nil &&
            e.hasStandbyGenerator != nil &&
            e.hasExistingWholeHomeBattery != nil &&
            e.plannedBatteryCount != nil
    }
}
