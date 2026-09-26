import Foundation
import Vision

/// On-device text recognition for a meter nameplate or a main-breaker handle.
struct VisionElectricalRecognizer: MeterNumberRecognizing {
    func recognizeMeterNumber(in imageJPEG: Data) async -> String? {
        let lines = await Self.lines(in: imageJPEG)
        return ElectricalLabelParser.meterNumber(in: lines)
    }

    func recognizeMainBreakerAmperage(in imageJPEG: Data) async -> Int? {
        let lines = await Self.lines(in: imageJPEG)
        return ElectricalLabelParser.mainBreakerAmperage(in: lines)
    }

    private static func lines(in imageJPEG: Data) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            recognizeLines(in: imageJPEG)
        }.value
    }

    private nonisolated static func recognizeLines(in imageJPEG: Data) -> [String] {
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
        return (request.results ?? [])
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { !$0.isEmpty }
    }
}

/// Pulls a meter number or a main-breaker rating out of recognized text.
enum ElectricalLabelParser {
    private static let ratings: Set<Int> = [100, 125, 150, 175, 200, 225]

    static func meterNumber(in lines: [String]) -> String? {
        if let labeled = labeledMeterNumber(in: lines) {
            return labeled
        }
        return lines
            .compactMap { longestDigitRun(in: $0, minCount: 5, maxCount: 12) }
            .max(by: { $0.count < $1.count })
    }

    /// Live scan often splits one number into short fragments. Those are joined when no single fragment is long enough.
    static func meterNumber(from transcripts: [String]) -> String? {
        if let labeled = labeledMeterNumber(in: transcripts) {
            return labeled
        }
        let singles = transcripts.compactMap { longestDigitRun(in: $0, minCount: 5, maxCount: 12) }
        let pieces = transcripts.compactMap { digitsOnlyFragment($0) }.filter { $0.count < 5 }
        if pieces.count >= 2 {
            let joined = pieces.joined()
            if (5...12).contains(joined.count) {
                return joined
            }
        }
        return singles.max(by: { $0.count < $1.count })
    }

    static func mainBreakerAmperage(in lines: [String]) -> Int? {
        let matches = lines.flatMap { amperageMatches(in: $0) }
        return matches.max { lhs, rhs in
            if lhs.isMainLine != rhs.isMainLine { return rhs.isMainLine }
            if lhs.hasSuffix != rhs.hasSuffix { return rhs.hasSuffix }
            return lhs.amps < rhs.amps
        }?.amps
    }

    private static func labeledMeterNumber(in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            guard isMeterLabel(line) else { continue }
            if let run = longestDigitRun(in: line, minCount: 5, maxCount: 12) {
                return run
            }
            let next = index + 1
            if next < lines.count, let run = longestDigitRun(in: lines[next], minCount: 5, maxCount: 12) {
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

    private static func isSeparator(_ character: Character) -> Bool {
        character == " " || character == "-" || character == "–" || character == "—"
    }

    private struct AmperageMatch {
        var amps: Int
        var hasSuffix: Bool
        var isMainLine: Bool
    }

    private static func amperageMatches(in line: String) -> [AmperageMatch] {
        let chars = Array(line)
        let lower = line.lowercased()
        let isMain = lower.contains("main") || lower.contains("disconnect")
        var matches: [AmperageMatch] = []
        var index = 0
        while index < chars.count {
            guard chars[index].isNumber else {
                index += 1
                continue
            }
            var end = index
            while end < chars.count, chars[end].isNumber {
                end += 1
            }
            let token = String(chars[index..<end])
            if let amps = Int(token),
               ratings.contains(amps),
               !isClassRating(chars, numberStart: index) {
                matches.append(AmperageMatch(
                    amps: amps,
                    hasSuffix: hasAmpSuffix(chars, from: end),
                    isMainLine: isMain
                ))
            }
            index = end
        }
        return matches
    }

    private static func isClassRating(_ chars: [Character], numberStart: Int) -> Bool {
        let word = precedingWord(chars, before: numberStart)
        return word == "cl" || word == "class"
    }

    private static func precedingWord(_ chars: [Character], before index: Int) -> String {
        var cursor = index - 1
        while cursor >= 0, chars[cursor].isWhitespace {
            cursor -= 1
        }
        var letters: [Character] = []
        while cursor >= 0, chars[cursor].isLetter {
            letters.append(chars[cursor])
            cursor -= 1
        }
        return String(letters.reversed()).lowercased()
    }

    private static func hasAmpSuffix(_ chars: [Character], from index: Int) -> Bool {
        var cursor = index
        while cursor < chars.count, chars[cursor].isWhitespace {
            cursor += 1
        }
        let rest = String(chars[cursor...]).lowercased()
        if rest.hasPrefix("amps") { return endsToken(rest, after: 4) }
        if rest.hasPrefix("amp") { return endsToken(rest, after: 3) }
        if rest.hasPrefix("a") { return endsToken(rest, after: 1) }
        return false
    }

    private static func endsToken(_ text: String, after offset: Int) -> Bool {
        guard let index = text.index(text.startIndex, offsetBy: offset, limitedBy: text.endIndex) else {
            return false
        }
        guard index < text.endIndex else { return true }
        let next = text[index]
        return !next.isLetter && !next.isNumber
    }
}
