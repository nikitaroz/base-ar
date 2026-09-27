import AVFoundation
import SwiftUI
import UIKit

enum PhotoSlot: String, Identifiable {
    case meter

    var id: String { rawValue }
}

struct ElectricalCaptureView: View {
    var store: SurveyStore

    @State private var activeSlot: PhotoSlot?
    @State private var scanTarget: LabelScanTarget?
    @State private var scanMessage: String?
    @State private var amperageText = ""
    @State private var busRatingText = ""
    @State private var showCameraDeniedAlert = false
    @State private var showsManualMeterEntry = false
    @FocusState private var focusedField: Field?

    private enum Field { case meterNumber, amperage, busRating }

    var body: some View {
        Form {
            meterSection
            breakerSection
        }
        .navigationTitle("Electrical")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if amperageText.isEmpty, let amps = store.session.electrical.mainBreakerAmperage {
                amperageText = String(amps)
            }
            if busRatingText.isEmpty, let rating = store.session.electrical.panelBusRatingAmps {
                busRatingText = String(rating)
            }
        }
        .onChange(of: store.session.electrical.mainBreakerAmperage) { _, amps in
            guard let amps else { return }
            let text = String(amps)
            if amperageText != text {
                amperageText = text
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .fullScreenCover(item: $activeSlot) { slot in
            CameraImagePicker { image in
                switch slot {
                case .meter:
                    store.attachMeterPhoto(image)
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $scanTarget) { target in
            LiveLabelScanner(target: target) { read, image in
                applyScan(read, image: image, target: target)
                scanTarget = nil
            } onCancel: {
                scanTarget = nil
            } onManualEntry: {
                scanTarget = nil
                showsManualMeterEntry = true
                // Focus once the cover has gone, or the keyboard request is dropped.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    focusedField = .meterNumber
                }
            }
            .ignoresSafeArea()
        }
        .alert("Camera access is off", isPresented: $showCameraDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Allow Camera access for Base Site Survey in Settings, then try again.")
        }
    }

    private func requestPhoto(for slot: PhotoSlot) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized, .notDetermined:
            activeSlot = slot
        case .denied, .restricted:
            // Simulator has no camera; the picker falls back to the library, so let it through.
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                showCameraDeniedAlert = true
            } else {
                activeSlot = slot
            }
        @unknown default:
            activeSlot = slot
        }
    }

    private var meterSection: some View {
        Section("Round electric meter") {
            Text(capturePrompt(
                scan: "Scan the round meter. It reads the number and saves a photo.",
                photo: "Take a photo of the round meter with the meter number sharp and readable."
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            captureControl(
                image: store.meterImage,
                scanTitle: "Scan meter",
                slot: .meter,
                target: .meterNumber,
                unavailableText: "Live scan needs an iPhone camera. The photo can still fill the number."
            )
            if showsMeterNumberField {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Meter number")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Enter the number shown on the meter", text: meterNumberBinding)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .meterNumber)
                }
            } else {
                Button("Enter number manually") {
                    showsManualMeterEntry = true
                    // Focus after the field is in the form, or the keyboard request is dropped.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedField = .meterNumber
                    }
                }
                .frame(maxWidth: .infinity)
            }
            if store.isReadingMeterNumber {
                Label("Reading the photo…", systemImage: "text.viewfinder")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if showsMeterNumberField {
                Text(store.meterNumberNote ?? "The meter number is different from the breaker amperage. Confirm the number before leaving this screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if store.session.electrical.meterNumberSource == .ocr, !(store.session.electrical.meterNumber ?? "").isEmpty {
                scanReadConfirm("meter number") { store.confirmScannedMeterNumber() }
            }
        }
    }

    /// A number the scan read stays a suggestion until the user says it matches, or types over it.
    private func scanReadConfirm(_ what: String, confirm: @escaping () -> Void) -> some View {
        Button("Looks right", systemImage: "checkmark", action: confirm)
            .frame(maxWidth: .infinity)
            .accessibilityHint("Says the \(what) the scan read matches what you see. It then counts as your answer.")
    }

    private var breakerSection: some View {
        Section("Main breaker") {
            Text("Enter the amperage printed on the main breaker.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Main breaker amperage")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Enter amperage", text: $amperageText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .amperage)
                        .onChange(of: amperageText) { _, newValue in
                            let digits = newValue.filter(\.isNumber)
                            if digits != newValue {
                                amperageText = digits
                                return
                            }
                            let parsed = Int(digits)
                            if parsed != store.session.electrical.mainBreakerAmperage {
                                store.setMainBreakerAmperage(parsed)
                            }
                        }
                    Text("A")
                        .foregroundStyle(.secondary)
                }
            }
            // A typed value is a record of what the user read, not a confirmation, so it stays neutral.
            if let amps = store.session.electrical.mainBreakerAmperage {
                if store.session.electrical.mainBreakerAmperageSource == .ocr {
                    Text("\(amps) A, read by scan. Check it against the main breaker: the scan reads the number beside MAIN, never the panel bus rating.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    scanReadConfirm("main breaker") { store.confirmScannedMainBreaker() }
                } else {
                    Text("Recorded: \(amps) A")
                        .foregroundStyle(.secondary)
                }
                if !BaseRuleSet.austinMainBreakerRange.contains(amps) {
                    Label("\(amps) A is outside the 150–200A Austin guidance and will be flagged for review.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(ToneStyle.color(.conflict))
                }
            }
            if store.session.electrical.needsPanelBusRating {
                busRatingField
            }
        }
    }

    /// Solar or two batteries need a 200A panel. That is the panel's bus rating, which the main breaker cannot stand in for.
    private var busRatingField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Panel bus rating")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                TextField("Bus rating from the panel label", text: $busRatingText)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .busRating)
                    .onChange(of: busRatingText) { _, newValue in
                        let digits = newValue.filter(\.isNumber)
                        if digits != newValue {
                            busRatingText = digits
                            return
                        }
                        let parsed = Int(digits)
                        if parsed != store.session.electrical.panelBusRatingAmps {
                            store.setPanelBusRatingAmps(parsed)
                        }
                    }
                Text("A")
                    .foregroundStyle(.secondary)
            }
            Text("Solar or two batteries need a 200A panel. Read the bus rating from the label on the panel, usually inside the panel door. It is not the main breaker number. Do not remove the panel cover.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let rating = store.session.electrical.panelBusRatingAmps {
                Text("Recorded: \(rating) A")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Scan comes first, like adding a payment card. The typed field appears once there is a number or the user asks for it.
    private var showsMeterNumberField: Bool {
        !LiveLabelScanner.isSupported
            || showsManualMeterEntry
            || !(store.session.electrical.meterNumber ?? "").isEmpty
            || store.meterImage != nil
    }

    private var meterNumberBinding: Binding<String> {
        Binding(
            get: { store.session.electrical.meterNumber ?? "" },
            set: { store.setMeterNumber($0) }
        )
    }

    private func applyScan(_ read: LabelScanRead, image: UIImage?, target: LabelScanTarget) {
        switch target {
        case .meterNumber:
            if let number = read.meterNumber {
                store.setMeterNumber(number, source: .ocr, note: "Scanned from the camera. Confirm it matches the meter.")
            }
            if let image {
                store.attachMeterPhoto(image)
            }
        case .breakerAmperage:
            break
        }
    }

    private func beginScan(_ target: LabelScanTarget) {
        scanMessage = nil
        Task {
            if let reason = await LiveLabelScanner.prepare() {
                scanMessage = reason
            } else {
                scanTarget = target
            }
        }
    }

    private func capturePrompt(scan: String, photo: String) -> String {
        LiveLabelScanner.isSupported ? scan : photo
    }

    @ViewBuilder
    private func captureControl(
        image: UIImage?,
        scanTitle: String,
        slot: PhotoSlot,
        target: LabelScanTarget,
        unavailableText: String
    ) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Saved photo")
        }
        if LiveLabelScanner.isSupported {
            Button {
                beginScan(target)
            } label: {
                Label(image == nil ? scanTitle : "Scan again", systemImage: "text.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Point at the number. Accepting it saves the photo too. Confirm the value before you leave.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Button {
                requestPhoto(for: slot)
            } label: {
                Label(image == nil ? "Take photo" : "Retake photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text(unavailableText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if let scanMessage {
            Text(scanMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
