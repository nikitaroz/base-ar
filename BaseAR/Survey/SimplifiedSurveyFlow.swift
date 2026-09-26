import SwiftUI

/// Simplified two-step survey flow: Step 1 (basic info) → Realtime feedback screen (AR + live scanning + rules + Jev)
struct SimplifiedSurveyFlow: View {
    var store: SurveyStore
    var onOpen: (HubRoute) -> Void
    
    @State private var showingRealtimeScreen = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Survey")
                    .font(.largeTitle.bold())
                
                Text("Fill out your info, then scan your equipment live.")
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
                        
                        Text("Your contact info and home details")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Button {
                            onOpen(.home)
                        } label: {
                            Text(step1Complete ? "Edit Info" : "Fill Out")
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
                        
                        Text("Point your camera at equipment and see results live")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if step1Complete {
                            Button {
                                showingRealtimeScreen = true
                            } label: {
                                HStack {
                                    Image(systemName: "arkit")
                                    Text("Start Live Scan")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        } else {
                            Button {} label: {
                                Text("Fill out Step 1 first")
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
                        
                        Text("See what you captured and share results")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Button {
                            onOpen(.review)
                        } label: {
                            Text("View Results")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(4)
                }
                
                Text("This is a prototype. An engineer must confirm your site.")
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
