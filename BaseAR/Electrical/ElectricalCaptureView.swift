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
    var onContinue: () -> Void

    @State private var activeSlot: PhotoSlot?
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

            Section {
                Button("Done") {
                    fieldIsFocused = false
                    onContinue()
                }
                Text("You can leave blanks. Review lists what is still missing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(focus == .meter ? "Electrical Meter" : "Breaker box")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if focus == .breaker, amperageText.isEmpty, let amps = store.session.electrical.mainBreakerAmperage {
                amperageText = String(amps)
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
            photoRow(
                image: store.meterImage,
                emptyTitle: "Photograph meter",
                retakeTitle: "Retake meter photo",
                slot: .meter
            )
            TextField("Meter number", text: meterNumberBinding)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($fieldIsFocused)
            Text("The meter number is separate from the breaker amperage. Reading it from the photo is not connected yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var breakerSection: some View {
        Section("Main disconnect / breaker") {
            photoRow(
                image: store.breakerImage,
                emptyTitle: "Photograph main breaker",
                retakeTitle: "Retake breaker photo",
                slot: .breaker
            )
            TextField("Main breaker amperage", text: $amperageText)
                .keyboardType(.numberPad)
                .focused($fieldIsFocused)
                .onChange(of: amperageText) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue {
                        amperageText = digits
                    }
                    store.setMainBreakerAmperage(Int(digits))
                }
            if let amps = store.session.electrical.mainBreakerAmperage {
                Text("Confirmed main breaker: \(amps) A")
            } else {
                Text("No amperage confirmed yet.")
                    .foregroundStyle(.secondary)
            }
            Text("Austin checks use 150–200A. Confirm the number printed on the breaker.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var meterNumberBinding: Binding<String> {
        Binding(
            get: { store.session.electrical.meterNumber ?? "" },
            set: { store.setMeterNumber($0) }
        )
    }

    @ViewBuilder
    private func photoRow(image: UIImage?, emptyTitle: String, retakeTitle: String, slot: PhotoSlot) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(retakeTitle)
        }
        Button(image == nil ? emptyTitle : retakeTitle) {
            requestPhoto(for: slot)
        }
    }
}
