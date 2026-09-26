import AVFoundation
import SwiftUI

/// A thin coordinator around the team's existing capture and AR screens.
struct GuidedSurveyView: View {
    var store: SurveyStore
    var onOpen: (HubRoute) -> Void
    @State private var editor: HubRoute?
    @State private var photoSlot: ContextPhoto?
    @State private var cameraDenied = false
    @State private var deferReason = ""
    @State private var showDeferral = false

    private var progress: GuidedSurveyProgress { store.session.guidedProgress ?? GuidedSurveyProgress() }
    private var step: SurveyStep { progress.currentStep }
    private var index: Int { SurveyStep.allCases.firstIndex(of: step) ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Step \(index + 1) of \(SurveyStep.allCases.count)")
                    .font(.subheadline).foregroundStyle(.secondary)
                ProgressView(value: Double(index + 1), total: Double(SurveyStep.allCases.count))
                Text(step.title).font(.largeTitle.bold())
                Text(step.instruction).font(.body)
                if let error = store.draftSaveError {
                    Label("Draft not saved: \(error)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                if let error = store.lastExportError {
                    Label("Photo or export could not be saved: \(error)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                stepContent
                let issues = SurveyWorkflow.issues(for: step, session: store.session)
                if !issues.isEmpty {
                    GroupBox("What is still needed") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(issues, id: \.self) { Text($0) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let reason = progress.deferred[step.rawValue] {
                    Text("Needs human review: \(reason)").foregroundStyle(.orange)
                    Button("Remove deferral and finish this step") { store.deferStep(step, reason: nil) }
                }
                if step != .review {
                    Button("Continue") { move(1) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!SurveyWorkflow.canContinue(step, session: store.session))
                    if step != .safety {
                        Button("Can't safely finish / need help") {
                            deferReason = progress.deferred[step.rawValue] ?? ""
                            showDeferral = true
                        }
                    }
                }
                if index > 0 { Button("Back one step") { move(-1) } }
                DisclosureGroup("All steps and feedback loops") {
                    ForEach(SurveyStep.allCases) { item in
                        Button {
                            store.setGuidedStep(item)
                        } label: {
                            HStack {
                                Text(item.title)
                                Spacer()
                                Text(status(item)).font(.caption)
                            }.padding(.vertical, 6)
                        }
                        .disabled(!progress.safetyAcknowledged && item != .safety)
                    }
                }
                Text("Saved on this phone when no save error is shown. Share only with a recipient you choose. Preliminary evidence, not installation approval.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }
        .id(step)
        .navigationTitle("Guided survey")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editor) { route in
            NavigationStack {
                editorContent(route)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Return to guide") { editor = nil }
                        }
                    }
            }
        }
        .fullScreenCover(item: $photoSlot) { slot in
            CameraImagePicker(instruction: "\(slot.title). \(slot.instruction)") { store.attachContextPhoto($0, slot: slot) }
                .ignoresSafeArea()
        }
        .alert("Camera access is off", isPresented: $cameraDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable Camera access, or record why this step needs help. No photo is required when it is unsafe.")
        }
        .sheet(isPresented: $showDeferral) {
            NavigationStack {
                Form {
                    Section("Why does this need review?") {
                        TextField("For example: label hidden, locked gate, camera denied", text: $deferReason, axis: .vertical)
                        Text("A deferral lets you continue but does not mark the evidence complete or pass any check.")
                    }
                    Button("Save reason and continue") {
                        store.deferStep(step, reason: deferReason)
                        showDeferral = false
                        move(1)
                    }.disabled(deferReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .navigationTitle("Leave for human review")
                .toolbar { Button("Cancel") { showDeferral = false } }
            }
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .safety:
            Text("Photos and answers remain in this app's local draft until you use Share. Camera and location permission are requested only when needed. Address search uses Apple's map service; GPS is optional.")
            Toggle("I understand and will only capture safely visible equipment", isOn: Binding(
                get: { progress.safetyAcknowledged }, set: { value in store.updateGuided { $0.safetyAcknowledged = value } }
            ))
        case .home: openButton("Enter home and contact details", route: .home)
        case .program:
            Picker("Utility / service", selection: Binding(
                get: { progress.program },
                set: { value in store.updateGuided { $0.program = value; $0.programAnswered = false } }
            )) {
                ForEach(UtilityProgram.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
            TextField("Utility name from bill (optional)", text: Binding(
                get: { progress.utilityName },
                set: { value in store.updateGuided { $0.utilityName = value; $0.programAnswered = false } }
            )).textFieldStyle(.roundedBorder)
            Button("Save utility answer") { store.updateGuided { $0.programAnswered = true } }
                .buttonStyle(.bordered)
            Text("Self-reported, not verified against a service territory. Unknown and other programs require review. This app does not decide meter replacement or connection topology.")
                .font(.footnote).foregroundStyle(.secondary)
        case .meter: openButton("Capture and confirm meter ID", route: .meter)
        case .breaker: openButton("Capture and confirm main rating", route: .breaker)
        case .meterContext, .panelContext:
            if step == .meterContext {
                Picker("Is there a fence obstructing the area?", selection: Binding(
                    get: { progress.fencePresent.map { $0 ? 1 : 0 } ?? -1 },
                    set: { value in store.updateGuided { $0.fencePresent = value == -1 ? nil : value == 1 } }
                )) {
                    Text("Not answered").tag(-1)
                    Text("No").tag(0)
                    Text("Yes").tag(1)
                }.pickerStyle(.menu)
            }
            ForEach(SurveyWorkflow.photos(for: step, session: store.session)) { slot in
                photoCard(slot)
            }
        case .placement:
            Text("A saved placement from an earlier app launch is a record only. Reopening AR starts a new spatial scan; old world anchors are not restored.")
                .font(.footnote).foregroundStyle(.secondary)
            openButton("Start guided AR walkthrough", route: .placement)
        case .review:
            ForEach(SurveyStep.allCases.filter { $0 != .review }) { item in
                let issues = SurveyWorkflow.issues(for: item, session: store.session)
                if !issues.isEmpty || progress.deferred[item.rawValue] != nil {
                    Button("Revisit: \(item.title)") { store.setGuidedStep(item) }
                    if let reason = progress.deferred[item.rawValue] {
                        Text("Deferred: \(reason)").font(.footnote)
                    }
                }
            }
            Text("Utility/program, equipment compatibility, local clearances, windows/vents, and any unresolved measurements require qualified review, even if the photo checklist is complete.")
            Button("Open review and share packet") { onOpen(.review) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    @ViewBuilder private func editorContent(_ route: HubRoute) -> some View {
        switch route {
        case .home: HomeInformationView(store: store)
        case .meter: ElectricalCaptureView(store: store, focus: .meter)
        case .breaker: ElectricalCaptureView(store: store, focus: .breaker)
        case .placement: PlacementARView(store: store) { editor = nil }
        case .review, .guide: EmptyView()
        }
    }

    private func openButton(_ title: String, route: HubRoute) -> some View {
        Button(title) { editor = route }.buttonStyle(.borderedProminent).controlSize(.large)
    }

    private func photoCard(_ slot: ContextPhoto) -> some View {
        GroupBox(slot.title) {
            VStack(alignment: .leading, spacing: 10) {
                Text(slot.instruction).font(.subheadline)
                if let image = store.contextImage(slot) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                        .accessibilityLabel(slot.title)
                    Toggle("I checked: sharp, correct area, nothing important cropped", isOn: Binding(
                        get: { progress.contextPhotos[slot.rawValue]?.accepted == true },
                        set: { store.acceptContextPhoto(slot, accepted: $0) }
                    ))
                }
                Button(progress.contextPhotos[slot.rawValue] == nil ? "Take photo" : "Retake photo") {
                    let status = AVCaptureDevice.authorizationStatus(for: .video)
                    if (status == .denied || status == .restricted) && UIImagePickerController.isSourceTypeAvailable(.camera) {
                        cameraDenied = true
                    } else { photoSlot = slot }
                }.buttonStyle(.bordered)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func move(_ offset: Int) {
        let target = min(max(index + offset, 0), SurveyStep.allCases.count - 1)
        store.setGuidedStep(SurveyStep.allCases[target])
    }

    private func status(_ item: SurveyStep) -> String {
        if progress.deferred[item.rawValue] != nil { return "Needs review" }
        if item == .review { return "Share draft" }
        return SurveyWorkflow.issues(for: item, session: store.session).isEmpty ? "Captured" : "To do"
    }
}
