import Foundation
import Vision

/// On-device text recognition for a meter nameplate or a main-breaker handle.
struct VisionElectricalRecognizer: MeterNumberRecognizing {
    func recognizeMeterNumber(in imageJPEG: Data) async -> String? {
        let lines = await Self.lines(in: imageJPEG)
        return ElectricalLabelParser.meterNumber(in: lines)
    }

    /// The same MAIN rules as the Live Survey's capture gate, on the photo's boxed lines, so a table row
    /// ("Maximum per stab" | "125A") reads as one row. No largest-handle guess from a photo.
    func recognizeMainBreakerAmperage(in imageJPEG: Data) async -> Int? {
        let lines = await Task.detached(priority: .userInitiated) {
            Self.recognizeBoxedLines(in: imageJPEG)
        }.value
        return ScanTextParser.panelRead(in: lines, detectorPanelBox: false)?.amps
    }

    private static func lines(in imageJPEG: Data) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            recognizeBoxedLines(in: imageJPEG)
                .sorted { $0.box.midY > $1.box.midY }
                .map(\.text)
        }.value
    }

    private nonisolated static func recognizeBoxedLines(in imageJPEG: Data) -> [ScanTextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(data: imageJPEG, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).compactMap { observation in
            guard let top = observation.topCandidates(1).first, !top.string.isEmpty else { return nil }
            return ScanTextLine(text: top.string, box: observation.boundingBox, confidence: top.confidence)
        }
    }
}

/// Pulls a meter number or a main-breaker rating out of recognized text.
enum ElectricalLabelParser {
    /// Meter numbers run 7–12 digits; the kWh register is 5–6. A shorter run counts only right beside a "METER" label.
    static let meterDigitRange = 7...12

    static func meterNumber(in lines: [String]) -> String? {
        if let labeled = labeledMeterNumber(in: lines) {
            return labeled
        }
        return lines
            .filter { !$0.lowercased().contains("kwh") }
            .compactMap { longestDigitRun(in: $0, minCount: meterDigitRange.lowerBound, maxCount: meterDigitRange.upperBound) }
            .max(by: { $0.count < $1.count })
    }

    /// Live scan often splits one number into short fragments. Those are joined when no single fragment is long enough.
    static func meterNumber(from transcripts: [String]) -> String? {
        if let labeled = labeledMeterNumber(in: transcripts) {
            return labeled
        }
        let singles = transcripts.compactMap {
            longestDigitRun(in: $0, minCount: meterDigitRange.lowerBound, maxCount: meterDigitRange.upperBound)
        }
        let pieces = transcripts.compactMap { digitsOnlyFragment($0) }.filter { $0.count < 5 }
        if pieces.count >= 2 {
            let joined = pieces.joined()
            if meterDigitRange.contains(joined.count) {
                return joined
            }
        }
        return singles.max(by: { $0.count < $1.count })
    }

    /// Lines without boxes (the live number scanner's transcripts): MAIN and the rating on one line, or the rating
    /// alone on the line right above or below MAIN, and never on a row of the panel's own ratings ("Maximum per stab
    /// 125A", bus, max, AIC, torque, volts). Same rules as the capture gate, with no largest-handle path.
    static func mainBreakerAmperage(in lines: [String]) -> Int? {
        ScanTextParser.mainBreakerAmps(inLines: lines)
    }

    private static func labeledMeterNumber(in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            guard isMeterLabel(line) else { continue }
            if let run = longestDigitRun(in: line, minCount: 5, maxCount: meterDigitRange.upperBound) {
                return run
            }
            let next = index + 1
            if next < lines.count, !lines[next].lowercased().contains("kwh"),
               let run = longestDigitRun(in: lines[next], minCount: 5, maxCount: meterDigitRange.upperBound) {
                return run
            }
        }
        return nil
    }

    private static func isMeterLabel(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("mtr") { return true }
        return lower.range(of: #"(?<![a-z])meter\b"#, options: .regularExpression) != nil
    }

    private static func digitsOnlyFragment(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digits = trimmed.filter(\.isNumber)
        let extras = trimmed.contains { character in
            !(character.isNumber || character.isWhitespace || character == "-" || character == "–" || character == "—")
        }
        guard !extras, !digits.isEmpty else { return nil }
        return digits
    }

    private static func longestDigitRun(in line: String, minCount: Int, maxCount: Int) -> String? {
        let chars = Array(line)
        var best: String?
        var index = 0
        while index < chars.count {
            guard chars[index].isNumber else {
                index += 1
                continue
            }
            var digits = String(chars[index])
            var cursor = index + 1
            while cursor < chars.count {
                if chars[cursor].isNumber {
                    digits.append(chars[cursor])
                    cursor += 1
                    continue
                }
                if isSeparator(chars[cursor]), cursor + 1 < chars.count, chars[cursor + 1].isNumber {
                    cursor += 1
                    continue
                }
                break
            }
            if (minCount...maxCount).contains(digits.count), best == nil || digits.count > (best?.count ?? 0) {
                best = digits
            }
            index = max(cursor, index + 1)
        }
        return best
    }

    /// Hyphens join a printed number ("12-345-678"). A space does not: "2812689 1858" on a barcode line is two
    /// numbers, and joining them gave an 11-digit meter number that is not on the meter.
    private static func isSeparator(_ character: Character) -> Bool {
        character == "-" || character == "–" || character == "—"
    }
}
