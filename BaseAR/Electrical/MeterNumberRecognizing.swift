import Foundation

/// Electrical capture/OCR boundary.
/// Replace `UnimplementedMeterNumberRecognizer` with Vision text recognition.
/// Leave the manual meter-number field as the confirmed value until the user accepts a read.
protocol MeterNumberRecognizing: Sendable {
    func recognizeMeterNumber(in imageJPEG: Data) async -> String?
}

struct UnimplementedMeterNumberRecognizer: MeterNumberRecognizing {
    func recognizeMeterNumber(in imageJPEG: Data) async -> String? {
        nil
    }
}
