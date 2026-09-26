import SwiftUI
import UIKit

/// Uses the camera on a phone. Falls back to the photo library when no camera exists, such as the simulator.
struct CameraImagePicker: UIViewControllerRepresentable {
    var instruction: String? = nil
    var onImage: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            if let instruction {
                // Keep the native shutter/cancel controls; this is coaching, not a quality detector.
                let overlay = UIView(frame: picker.view.bounds)
                overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                overlay.isUserInteractionEnabled = false
                let label = UILabel()
                label.text = instruction
                label.numberOfLines = 0
                label.textAlignment = .center
                label.font = .preferredFont(forTextStyle: .subheadline)
                label.adjustsFontForContentSizeCategory = true
                label.textColor = .white
                label.backgroundColor = UIColor.black.withAlphaComponent(0.72)
                label.layer.cornerRadius = 12
                label.clipsToBounds = true
                label.translatesAutoresizingMaskIntoConstraints = false
                overlay.addSubview(label)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 20),
                    label.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -20),
                    label.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 72)
                ])
                picker.cameraOverlayView = overlay
            }
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        context.coordinator.onImage = onImage
        context.coordinator.dismiss = { dismiss() }
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onImage: (UIImage) -> Void
        var dismiss: () -> Void

        init(onImage: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
