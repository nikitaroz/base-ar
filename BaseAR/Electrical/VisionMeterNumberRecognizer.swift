import Foundation
import UIKit
import Vision

/// Vision-based OCR for utility meter numbers. Meter numbers are typically 7–12 consecutive digits
/// printed largest on the meter face. Rank candidates by observation height (proxy for print size)
/// then confidence, and return the top hit.
struct VisionMeterNumberRecognizer: MeterNumberRecognizing {
    private static let minDigits = 7
    private static let maxDigits = 12
    private static let minConfidence: Float = 0.4

    func recognizeMeterNumber(in imageJPEG: Data) async -> String? {
        guard let cgImage = UIImage(data: imageJPEG)?.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let candidates = Self.candidates(from: request.results as? [VNRecognizedTextObservation] ?? [])
                continuation.resume(returning: candidates.first?.digits)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }

    struct Candidate {
        var digits: String
        var confidence: Float
        var height: CGFloat
    }

    static func candidates(from observations: [VNRecognizedTextObservation]) -> [Candidate] {
        var result: [Candidate] = []
        for observation in observations {
            guard let top = observation.topCandidates(1).first else { continue }
            guard top.confidence >= minConfidence else { continue }
            let digits = top.string.filter(\.isNumber)
            guard (minDigits...maxDigits).contains(digits.count) else { continue }
            result.append(Candidate(digits: digits, confidence: top.confidence, height: observation.boundingBox.height))
        }
        return result.sorted { lhs, rhs in
            if lhs.height != rhs.height { return lhs.height > rhs.height }
            return lhs.confidence > rhs.confidence
        }
    }
}
