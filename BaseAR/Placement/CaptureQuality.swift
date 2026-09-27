import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import os
import simd
import UIKit
import Vision

/// How good one region of a camera frame is for a photo that has to be read: focus and exposure, measured on the
/// luma plane of the copied frame. Nothing here keeps a frame.
struct CaptureReading: Sendable, Equatable {
    /// Variance of the 4-neighbour Laplacian on the region, downscaled to about 256 px on its long side.
    var sharpness: Float
    /// Mean luma, 0–255 (ARKit frames are full range).
    var meanLuma: Float
    /// Share of samples at or below `CaptureQuality.darkLuma`.
    var darkFraction: Float
    /// Share of samples at or above `CaptureQuality.clippedLuma`.
    var clippedFraction: Float
}

/// What stands between a region and a readable photo, in the order the user can fix it.
enum CaptureProblem: String, Sendable {
    case tooDark
    case tooBright
    case blurry
}

enum CaptureQuality {
    // Every number below is a first guess. Tune on device from the DEBUG `ScanCapture` log.
    /// Below this the frame is too blurry to read small print. Tune on device.
    static let minSharpness: Float = 35
    /// Mean luma band for a readable label. Tune on device.
    static let lumaRange: ClosedRange<Float> = 45...210
    /// A sample this dark counts as crushed. Tune on device.
    static let darkLuma: Float = 18
    /// A sample this bright counts as clipped (glare on the meter glass, direct sun). Tune on device.
    static let clippedLuma: Float = 250
    /// Too much of the region crushed or clipped fails even when the mean looks fine. Tune on device.
    static let maxDarkFraction: Float = 0.45
    static let maxClippedFraction: Float = 0.2
    /// Long side of the downscaled grid the metrics run on.
    private static let sampleSide = 256

    static func problem(_ reading: CaptureReading) -> CaptureProblem? {
        if reading.meanLuma < lumaRange.lowerBound || reading.darkFraction > maxDarkFraction { return .tooDark }
        if reading.meanLuma > lumaRange.upperBound || reading.clippedFraction > maxClippedFraction { return .tooBright }
        if reading.sharpness < minSharpness { return .blurry }
        return nil
    }

    /// Measures `visionRect` (Vision-normalized, origin lower left of the upright image) on the frame's luma plane.
    /// Nil for a region under 16 px or a buffer without a luma plane.
    static func measure(
        _ buffer: CVPixelBuffer,
        visionRect: CGRect,
        orientation: CGImagePropertyOrientation
    ) -> CaptureReading? {
        let normalized = bufferRect(fromVision: visionRect, orientation: orientation)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) >= 1,
              let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let x0 = max(0, min(width, Int((normalized.minX * CGFloat(width)).rounded(.down))))
        let x1 = max(0, min(width, Int((normalized.maxX * CGFloat(width)).rounded(.up))))
        let y0 = max(0, min(height, Int((normalized.minY * CGFloat(height)).rounded(.down))))
        let y1 = max(0, min(height, Int((normalized.maxY * CGFloat(height)).rounded(.up))))
        guard x1 - x0 >= 16, y1 - y0 >= 16 else { return nil }
        let step = max(1, Int((Double(max(x1 - x0, y1 - y0)) / Double(sampleSide)).rounded(.up)))
        let columns = (x1 - x0) / step
        let rows = (y1 - y0) / step
        guard columns >= 3, rows >= 3 else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var grid = [Float](repeating: 0, count: columns * rows)
        var sum: Float = 0
        var dark = 0
        var clipped = 0
        grid.withUnsafeMutableBufferPointer { cells in
            for row in 0..<rows {
                let y = y0 + row * step
                for column in 0..<columns {
                    let x = x0 + column * step
                    let index = y * stride + x
                    var value: Float
                    if step >= 2 {
                        // A 2×2 average keeps sensor noise from reading as detail after the downscale.
                        let total = Int(bytes[index]) + Int(bytes[index + 1]) + Int(bytes[index + stride]) + Int(bytes[index + stride + 1])
                        value = Float(total) / 4
                    } else {
                        value = Float(bytes[index])
                    }
                    cells[row * columns + column] = value
                    sum += value
                    if value <= darkLuma { dark += 1 }
                    if value >= clippedLuma { clipped += 1 }
                }
            }
        }
        let count = Float(columns * rows)
        var lapSum: Double = 0
        var lapSquares: Double = 0
        var lapCount = 0
        grid.withUnsafeBufferPointer { cells in
            for row in 1..<(rows - 1) {
                for column in 1..<(columns - 1) {
                    let center = row * columns + column
                    let laplacian = Double(cells[center - 1] + cells[center + 1] + cells[center - columns] + cells[center + columns] - 4 * cells[center])
                    lapSum += laplacian
                    lapSquares += laplacian * laplacian
                    lapCount += 1
                }
            }
        }
        guard lapCount > 0 else { return nil }
        let lapMean = lapSum / Double(lapCount)
        let variance = max(0, lapSquares / Double(lapCount) - lapMean * lapMean)
        return CaptureReading(
            sharpness: Float(variance),
            meanLuma: sum / count,
            darkFraction: Float(dark) / count,
            clippedFraction: Float(clipped) / count
        )
    }

    /// Vision's upright rect (origin lower left) as a normalized rect in the camera buffer (origin upper left).
    static func bufferRect(fromVision rect: CGRect, orientation: CGImagePropertyOrientation) -> CGRect {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)
        ].map { bufferPoint(fromVision: $0, orientation: orientation) }
        return bounds(of: corners)
    }

    /// The middle of the screen, `fraction` of its width and height, as a Vision-normalized rect of the upright image.
    static func centerVisionRect(
        fraction: CGFloat,
        displayTransform: CGAffineTransform,
        orientation: CGImagePropertyOrientation
    ) -> CGRect {
        let inset = (1 - fraction) / 2
        let view = CGRect(x: inset, y: inset, width: fraction, height: fraction)
        let inverse = displayTransform.inverted()
        let corners = [
            CGPoint(x: view.minX, y: view.minY), CGPoint(x: view.maxX, y: view.minY),
            CGPoint(x: view.minX, y: view.maxY), CGPoint(x: view.maxX, y: view.maxY)
        ].map { visionPoint(fromBuffer: $0.applying(inverse), orientation: orientation) }
        return bounds(of: corners).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let shared = a.intersection(b)
        guard !shared.isNull else { return 0 }
        let inter = shared.width * shared.height
        let union = a.width * a.height + b.width * b.height - inter
        return union > 0 ? inter / union : 0
    }

    /// `rect` grown by `factor` of its size on every side, kept inside the unit square.
    static func padded(_ rect: CGRect, by factor: CGFloat) -> CGRect {
        rect.insetBy(dx: -rect.width * factor, dy: -rect.height * factor)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func bufferPoint(fromVision point: CGPoint, orientation: CGImagePropertyOrientation) -> CGPoint {
        switch orientation {
        case .right: CGPoint(x: 1 - point.y, y: 1 - point.x)
        case .left: CGPoint(x: point.y, y: point.x)
        case .down: CGPoint(x: 1 - point.x, y: point.y)
        default: CGPoint(x: point.x, y: 1 - point.y)
        }
    }

    private static func visionPoint(fromBuffer point: CGPoint, orientation: CGImagePropertyOrientation) -> CGPoint {
        switch orientation {
        case .right: CGPoint(x: 1 - point.y, y: 1 - point.x)
        case .left: CGPoint(x: point.y, y: point.x)
        case .down: CGPoint(x: 1 - point.x, y: point.y)
        default: CGPoint(x: point.x, y: 1 - point.y)
        }
    }

    private static func bounds(of points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Reading the label

/// One recognized line. The box is Vision-normalized in whatever image was read.
struct ScanTextLine: Sendable, Equatable {
    var text: String
    var box: CGRect
    var confidence: Float
}

/// Label text that decides a capture. Pure, so the rules can be read and tuned without a device.
enum ScanTextParser {
    static let breakerRatings: Set<Int> = [100, 125, 150, 175, 200, 225]
    /// Meter numbers (the nameplate or utility asset number) run 7–12 digits. The kWh register is 5–6 digits.
    static let meterDigits = 7...12
    /// A line read below this is too unsure to decide anything. Tune on device.
    static let minLineConfidence: Float = 0.3

    struct MeterRead: Sendable, Equatable {
        var number: String
        var box: CGRect
        /// A meter word ("kWh", "CL200", "240V", "watthour", "meter") was on the label too.
        var hasMeterCue: Bool
    }

    struct BreakerRead: Sendable, Equatable {
        var amps: Int
        /// The rating plus the "MAIN" it sat beside, when there was one.
        var box: CGRect
        var nearMain: Bool
    }

    /// The meter number on this label, or nil. AC and heat-pump nameplates also carry long numbers, so a label
    /// with refrigerant or compressor words never gives one.
    static func meterNumber(in lines: [ScanTextLine]) -> MeterRead? {
        let usable = lines.filter { $0.confidence >= minLineConfidence }
        guard !usable.contains(where: { isApplianceLabel($0.text) }) else { return nil }
        let cue = usable.contains { hasMeterCue($0.text) }
        let labels = usable.filter { isMeterNumberLabel($0.text) }
        var best: (score: Double, read: MeterRead)?
        for line in usable {
            let lower = line.text.lowercased()
            // The usage register sits on the kWh line. It is never the meter number.
            if lower.contains("kwh") { continue }
            for run in digitRuns(in: line.text) where meterDigits.contains(run.digits.count) {
                if looksLikePhoneNumber(run.grouping) { continue }
                var score = Double(line.box.height) * 20 + Double(line.confidence)
                if isMeterNumberLabel(line.text) || labels.contains(where: { isNear($0.box, line.box) }) {
                    score += 2
                }
                if best == nil || score > best!.score {
                    best = (score, MeterRead(number: run.digits, box: line.box, hasMeterCue: cue))
                }
            }
        }
        return best?.read
    }

    /// The main breaker's rating on this panel, or nil. Beside "MAIN" always counts. With a detector box around the
    /// panel, the rating printed biggest (the main handle) counts too. Never the panel's bus rating.
    static func mainBreakerAmps(in lines: [ScanTextLine], allowLargestHandle: Bool) -> BreakerRead? {
        let usable = lines.filter { $0.confidence >= minLineConfidence }
        // A meter nameplate (CL200, 240V, kWh) is not a panel.
        guard !usable.contains(where: { isStrongMeterCue($0.text) }) else { return nil }
        let mains = usable.filter { $0.text.lowercased().contains("main") && !isPanelRatingLabel($0.text) }
        var nearMain: (height: CGFloat, read: BreakerRead)?
        var ratings: [(line: ScanTextLine, amps: Int)] = []
        // The panel's own label ("200A MAX", "MAIN LUGS", "BUS RATING") carries the bus rating, never the breaker's.
        for line in usable where !isPanelRatingLabel(line.text) {
            for amps in ratingTokens(in: line.text) {
                ratings.append((line, amps))
                let onMainLine = line.text.lowercased().contains("main")
                let neighbor = mains.first { isNear($0.box, line.box) }
                guard onMainLine || neighbor != nil else { continue }
                let box = neighbor.map { $0.box.union(line.box) } ?? line.box
                if nearMain == nil || line.box.height > nearMain!.height {
                    nearMain = (line.box.height, BreakerRead(amps: amps, box: box, nearMain: true))
                }
            }
        }
        if let nearMain { return nearMain.read }
        guard allowLargestHandle else { return nil }
        // Branch handles print 15, 20, 30…; the main handle's rating is the biggest print among the numbers.
        let numeric = usable.filter { isNumberOnly($0.text) }.sorted { $0.box.height > $1.box.height }
        guard let tallest = numeric.first,
              let rating = ratings.first(where: { $0.line == tallest }) else { return nil }
        if numeric.count > 1, tallest.box.height < numeric[1].box.height * 1.15 { return nil }
        return BreakerRead(amps: rating.amps, box: tallest.box, nearMain: false)
    }

    /// Words of the panel's nameplate, whose amps are the bus rating: those numbers never count as the main breaker.
    private static func isPanelRatingLabel(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = ["bus", "lug", "max", "rated", "rating", "load center", "loadcenter", "catalog", "cat no", "cat.",
                     "suitable", "service entrance", "short circuit", "interrupting", "sccr", "enclosure", "volt"]
        return words.contains { lower.contains($0) }
    }

    static func hasMeterCue(_ text: String) -> Bool {
        let lower = text.lowercased()
        if isStrongMeterCue(text) { return true }
        return lower.range(of: #"(?<![a-z])(meter|mtr|kh|fm ?\d+s|form ?\d+s)(?![a-z])"#, options: .regularExpression) != nil
    }

    private static func isStrongMeterCue(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("kwh") || lower.contains("watthour") || lower.contains("watt-hour")
            || lower.range(of: #"(?<![a-z])cl ?(20|100|200|320)(?!\d)"#, options: .regularExpression) != nil
    }

    private static func isMeterNumberLabel(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.range(of: #"(?<![a-z])(meter|mtr|serial|s/n|sn|meter no|mtr no)(?![a-z])"#, options: .regularExpression) != nil
    }

    /// Words on AC condensers and heat pumps, which the detector scores as meters.
    private static func isApplianceLabel(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = ["refrigerant", "r-410a", "r410a", "r-22", "r-454b", "r454b", "compressor", "condens", "seer", "btu",
                     "hvac", "fan motor", "heat pump", "air condition", "min. circuit", "max. fuse", "mca", "mocp"]
        return words.contains { lower.contains($0) }
    }

    private static func isNumberOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return false }
        let body = trimmed.hasSuffix("a") ? String(trimmed.dropLast()) : trimmed
        return !body.isEmpty && body.allSatisfy(\.isNumber)
    }

    /// Two boxes on the same label: centers within a few line heights of each other.
    private static func isNear(_ a: CGRect, _ b: CGRect) -> Bool {
        let height = max(a.height, b.height, 0.01)
        return abs(a.midY - b.midY) < height * 2.5 && abs(a.midX - b.midX) < max(a.width, b.width) / 2 + height * 4
    }

    private struct DigitRun {
        var digits: String
        /// Group lengths when the run was joined across hyphens, e.g. [3, 3, 4].
        var grouping: [Int]
    }

    /// Digit runs. A hyphen between digits joins them; a space never does, so "2812689 1858" stays two runs.
    private static func digitRuns(in text: String) -> [DigitRun] {
        var runs: [DigitRun] = []
        var digits = ""
        var groups: [Int] = []
        var group = 0
        let chars = Array(text)
        func close() {
            if group > 0 { groups.append(group) }
            if !digits.isEmpty { runs.append(DigitRun(digits: digits, grouping: groups)) }
            digits = ""
            groups = []
            group = 0
        }
        for (index, char) in chars.enumerated() {
            if char.isASCII, char.isNumber {
                digits.append(char)
                group += 1
            } else if char == "-" || char == "–", group > 0, index + 1 < chars.count, chars[index + 1].isASCII, chars[index + 1].isNumber {
                groups.append(group)
                group = 0
            } else {
                close()
            }
        }
        close()
        return runs
    }

    private static func looksLikePhoneNumber(_ grouping: [Int]) -> Bool {
        grouping == [3, 3, 4] || grouping == [1, 3, 3, 4]
    }

    /// Breaker ratings on one line: whole numbers from the rating list, not "CL200" or "200V", optionally "200A".
    private static func ratingTokens(in text: String) -> [Int] {
        let lower = Array(text.lowercased())
        var found: [Int] = []
        var index = 0
        while index < lower.count {
            guard lower[index].isASCII, lower[index].isNumber else {
                index += 1
                continue
            }
            var end = index
            while end < lower.count, lower[end].isASCII, lower[end].isNumber { end += 1 }
            defer { index = end }
            guard let amps = Int(String(lower[index..<end])), breakerRatings.contains(amps) else { continue }
            var before = index - 1
            while before >= 0, lower[before] == " " { before -= 1 }
            var word = ""
            while before >= 0, lower[before].isLetter {
                word = String(lower[before]) + word
                before -= 1
            }
            if word.hasSuffix("cl") || word == "class" { continue }
            if index > 0, lower[index - 1].isLetter { continue }
            var after = end
            while after < lower.count, lower[after] == " " { after += 1 }
            if after < lower.count {
                let next = lower[after]
                // "200V", "200kWh", "200Hz", "240/120", "200.5" are not ratings. "200A", "200 AMP", "200 MAIN" are.
                if next == "/" || next == "." || next == "," { continue }
                if next.isLetter {
                    var word = ""
                    var cursor = after
                    while cursor < lower.count, lower[cursor].isLetter {
                        word.append(lower[cursor])
                        cursor += 1
                    }
                    guard ["a", "amp", "amps", "ampere", "amperes", "main"].contains(word) else { continue }
                }
            }
            found.append(amps)
        }
        return found
    }
}

/// One OCR pass over a crop of a copied frame.
struct ScanTextRead: @unchecked Sendable {
    var kind: EquipmentKind
    /// The capture attempt that asked for it. A newer attempt drops older reads.
    var generation: Int
    /// The Vision-normalized region of the upright frame that was read.
    var region: CGRect
    var textFirst: Bool
    var meter: ScanTextParser.MeterRead?
    var breaker: ScanTextParser.BreakerRead?
    /// Box of the read value in the whole upright frame (Vision-normalized), for a text-first candidate.
    var textBox: CGRect?
    /// The full-resolution crop that was read. It becomes the photo when this read captures.
    var image: CGImage?
    var lines: [String]

    /// The value this read found, as text, so two reads can be compared.
    var value: String? {
        switch kind {
        case .electricMeter: meter?.number
        case .breakerPanel: breaker.map { String($0.amps) }
        }
    }
}

/// Runs `VNRecognizeTextRequest(.accurate)` on full-resolution crops, one at a time, off the main thread.
/// It holds only `CopiedPixels`, never an `ARFrame`.
final class ScanTextReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "BaseAR.scan-text", qos: .userInitiated)
    private let context = CIContext()

    func read(
        _ pixels: CopiedPixels,
        region: CGRect,
        orientation: CGImagePropertyOrientation,
        kind: EquipmentKind,
        textFirst: Bool,
        generation: Int,
        completion: @escaping @Sendable (ScanTextRead) -> Void
    ) {
        queue.async { [context] in
            var result = ScanTextRead(
                kind: kind,
                generation: generation,
                region: region,
                textFirst: textFirst,
                lines: []
            )
            defer { completion(result) }
            let upright = CIImage(cvPixelBuffer: pixels.buffer).oriented(orientation)
            let extent = upright.extent
            // Vision boxes and Core Image share a lower-left origin.
            let crop = CGRect(
                x: extent.minX + region.minX * extent.width,
                y: extent.minY + region.minY * extent.height,
                width: region.width * extent.width,
                height: region.height * extent.height
            ).integral.intersection(extent)
            guard !crop.isNull, crop.width >= 32, crop.height >= 32,
                  let image = context.createCGImage(upright, from: crop) else { return }
            result.image = image
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return
            }
            let lines = (request.results ?? []).compactMap { observation -> ScanTextLine? in
                guard let top = observation.topCandidates(1).first, !top.string.isEmpty else { return nil }
                return ScanTextLine(text: top.string, box: observation.boundingBox, confidence: top.confidence)
            }
            result.lines = lines.map(\.text)
            let local: CGRect?
            switch kind {
            case .electricMeter:
                result.meter = ScanTextParser.meterNumber(in: lines)
                local = result.meter?.box
            case .breakerPanel:
                result.breaker = ScanTextParser.mainBreakerAmps(in: lines, allowLargestHandle: !textFirst)
                local = result.breaker?.box
            }
            if let local {
                result.textBox = CGRect(
                    x: region.minX + local.minX * region.width,
                    y: region.minY + local.minY * region.height,
                    width: local.width * region.width,
                    height: local.height * region.height
                )
            }
        }
    }
}

/// What a scan capture hands the survey: the photo it read and the value it read. The value is a suggestion the
/// user checks in Review, never a confirmed reading.
struct ScanCapture: @unchecked Sendable {
    var kind: EquipmentKind
    var image: UIImage
    var meterNumber: String?
    var mainBreakerAmps: Int?
}

/// One OCR read the gate kept, with where the candidate was when its frame was taken.
struct CaptureReadRecord {
    var read: ScanTextRead
    var landing: SIMD3<Float>?
    var at: CFTimeInterval
}

/// Per-target state of the automatic capture gate. The controller owns the checks; this only counts.
struct ScanCaptureState {
    var target: EquipmentKind?
    /// Bumped on every reset, so an OCR pass that finishes after a reset is ignored.
    var generation = 0
    /// Consecutive detector evaluations where every image check passed.
    var streak = 0
    var lastBox: CGRect?
    var lastLanding: SIMD3<Float>?
    var landings: [(point: SIMD3<Float>, normal: SIMD3<Float>)] = []
    var records: [CaptureReadRecord] = []
    var ocrInFlight = false
    var lastOCRAt: CFTimeInterval = 0
    /// Where the candidate was when the in-flight OCR frame was taken.
    var pendingLanding: SIMD3<Float>?
    /// Text-first candidate: the box of the last good read of MAIN + rating (or a meter number), and when.
    var textCandidate: (box: CGRect, at: CFTimeInterval)?
    /// Good frames in a row whose OCR found no value.
    var emptyReads = 0

    mutating func breakStreak() {
        streak = 0
        lastBox = nil
        lastLanding = nil
        landings = []
    }
}
