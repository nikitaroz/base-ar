import Foundation

/// Electrical capture/OCR boundary.
/// A scan may suggest a meter number or main-breaker rating.
/// The typed field stays the value the user accepts.
protocol MeterNumberRecognizing: Sendable {
    func recognizeMeterNumber(in imageJPEG: Data) async -> String?
    func recognizeMainBreakerAmperage(in imageJPEG: Data) async -> Int?
}

struct UnimplementedMeterNumberRecognizer: MeterNumberRecognizing {
    func recognizeMeterNumber(in imageJPEG: Data) async -> String? {
        nil
    }

    func recognizeMainBreakerAmperage(in imageJPEG: Data) async -> Int? {
        nil
    }
}
