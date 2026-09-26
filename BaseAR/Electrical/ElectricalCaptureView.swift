import AVFoundation
import SwiftUI
import UIKit

enum PhotoSlot: String, Identifiable {
    case meter
    case breaker

    var id: String { rawValue }
}

struct ElectricalCaptureView: View {
    var store: SurveyStore
    var focus: PhotoSlot

    @State private var activeSlot: PhotoSlot?
    @State private var scanTarget: LabelScanTarget?
    @State private var scanMessage: String?
    @State private var amperageText = ""
    @State private var showCameraDeniedAlert = false
    @FocusState private var fieldIsFocused: Bool

    var body: some View {
        Form {
            switch focus {
            case .meter:
                meterSection
            case .breaker:
                breakerSection
            }

        }
        .navigationTitle(focus == .meter ? "Electrical Meter" : "Breaker box")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if focus == .breaker, amperageText.isEmpty, let amps = store.session.electrical.mainBreakerAmperage {
                amperageText = String(amps)
            }
        }
        .onChange(of: store.session.electrical.mainBreakerAmperage) { _, amps in
            guard focus == .breaker, let amps else { return }
            let text = String(amps)
            if amperageText != text {
                amperageText = text
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldIsFocused = false }
            }
        }
        .fullScreenCover(item: $activeSlot) { slot in
            CameraImagePicker { image in
                switch slot {
                case .meter:
                    store.attachMeterPhoto(image)
                case .breaker:
                    store.attachBreakerPhoto(image)
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Meter number")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Enter the number shown on the meter", text: meterNumberBinding)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($fieldIsFocused)
            }
            if store.isReadingMeterNumber {
                Label("Reading the photo…", systemImage: "text.viewfinder")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(store.meterNumberNote ?? "The meter number is different from the breaker amperage. Confirm the number before leaving this screen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var breakerSection: some View {
        Section("Main disconnect / breaker") {
            Text(capturePrompt(
                scan: "Scan the main breaker. It reads the amperage and saves a photo.",
                photo: "Take a photo of the main disconnect with the number on the main breaker clearly visible."
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            captureControl(
                image: store.breakerImage,
                scanTitle: "Scan breaker",
                slot: .breaker,
                target: .breakerAmperage,
                unavailableText: "Live scan needs an iPhone camera. The photo can still fill the rating."
            )
            VStack(alignment: .leading, spacing: 6) {
                Text("Main breaker amperage")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Enter amperage", text: $amperageText)
                        .keyboardType(.numberPad)
                        .focused($fieldIsFocused)
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
            if store.isReadingBreakerAmperage {
                Label("Reading the photo…", systemImage: "text.viewfinder")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let amps = store.session.electrical.mainBreakerAmperage {
                if (150...200).contains(amps) {
                    Label("Confirmed: \(amps) A", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("\(amps) A is outside the 150–200A Austin guidance and will be flagged for review.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } else if store.breakerAmperageNote == nil {
                Text("Enter the number printed on the main breaker.")
                    .foregroundStyle(.secondary)
            }
            if let note = store.breakerAmperageNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
                store.setMeterNumber(number, note: "Scanned from the camera. Confirm it matches the meter.")
            }
            if let image {
                store.attachMeterPhoto(image)
            }
        case .breakerAmperage:
            if let amps = read.amperage {
                store.setMainBreakerAmperage(amps, note: "Scanned from the camera. Confirm it matches the main breaker.")
                amperageText = String(amps)
            }
            if let image {
                store.attachBreakerPhoto(image)
            }
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
