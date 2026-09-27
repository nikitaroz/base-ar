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
///
/// Main breaker: an amp rating counts only on an explicit MAIN row (path A: "MAIN BREAKER 200A", or MAIN and the
/// rating in the next cell of that row) or printed alone right above or below MAIN (path B). A row with a panel-rating
/// word (stab, bus, max, rated, lugs, AIC, kA, AWG, torque, volts, Hz, catalog, model, series, type, total, branch,
/// a range like 100-225) never gives the main breaker: "Maximum per stab | 125A" on the demo wall's label is not it.
/// Path C, the largest handle print among the branch handles, runs only on a real panel box with at least two branch
/// numerals in view, never on a printed label. Two different MAIN values give nil. A crop that is a panel without a
/// readable MAIN (a label, three or more branch numerals, or panel words, and not a disconnect or an appliance) is
/// still panel evidence, so the panel can lock with the amps left for Review.
enum ScanTextParser {
    /// Main-breaker ratings read beside MAIN. 60, 70, and 90 are left for Review to ask about.
    static let breakerRatings: Set<Int> = [100, 125, 150, 175, 200, 225]
    /// 225 is a bus number far more often than a main handle, so the largest-handle path never gives it.
    static let handleRatings: Set<Int> = [100, 125, 150, 175, 200]
    /// Meter numbers (the nameplate or utility asset number) run 7–12 digits. The kWh register is 5–6 digits.
    static let meterDigits = 7...12
    /// A line read below this is too unsure to decide anything. Tune on device.
    static let minLineConfidence: Float = 0.3
    /// The largest handle's print must be this much taller than the tallest branch numeral.
    static let handleHeightRatio: CGFloat = 1.15

    struct MeterRead: Sendable, Equatable {
        var number: String
        var box: CGRect
        /// A meter word ("kWh", "CL200", "240V", "watthour", "meter") was on the label too.
        var hasMeterCue: Bool
    }

    /// One panel crop's reading.
    struct PanelRead: Sendable, Equatable {
        /// The main breaker's rating, when a MAIN rule (or the largest handle) read one.
        var amps: Int?
        var basis: MainBreakerBasis?
        /// The crop is a panel (a label, branch handles, or panel words) even when no main rating was read.
        var isPanelEvidence: Bool
        /// Two or more printed-label words (torque, AWG, stab, warning, listed…): a label, not the breaker face.
        var labelMode: Bool
        /// The rating and its MAIN, or the lines that made it panel evidence. Vision-normalized in the crop.
        var box: CGRect?
    }

    // MARK: Shared

    /// Vision sometimes returns Cyrillic or Greek look-alikes ("TУРE C18 З0TA"). Fold them, then lowercase, before any
    /// word test.
    static func normalize(_ text: String) -> String {
        String(text.flatMap { lookAlikes[$0].map(Array.init) ?? [$0] }).lowercased()
    }

    private static let lookAlikes: [Character: String] = [
        "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H", "О": "O", "Р": "P", "С": "C", "Т": "T",
        "У": "Y", "Х": "X", "З": "3", "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x",
        "Α": "A", "Β": "B", "Ε": "E", "Κ": "K", "Μ": "M", "Ν": "N", "Ο": "O", "Ρ": "P", "Τ": "T", "Χ": "X"
    ]

    static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Observations on one printed row: vertical centers within 0.6 of the taller box's height. OCR splits a label's
    /// table row into boxes ("Maximum per stab" | "125A"); the whole row is the line.
    static func rowMates(of line: ScanTextLine, in lines: [ScanTextLine]) -> [ScanTextLine] {
        lines.filter { other in
            abs(other.box.midY - line.box.midY) < max(other.box.height, line.box.height) * 0.6
        }.sorted { $0.box.minX < $1.box.minX }
    }

    static func rowText(of line: ScanTextLine, in lines: [ScanTextLine]) -> String {
        rowMates(of: line, in: lines).map { normalize($0.text) }.joined(separator: " ")
    }

    // MARK: Main breaker

    /// A whole rating token: not glued to letters, digits, '.', '/', '-', or '#', with an optional A, AMP(S), AMPERE(S).
    static let ratingToken = #"(?<![\w#./\-])(100|125|150|175|200|225)(?:\s*(?:a|amps?|amperes?))?(?![\w/.\-%°])"#
    /// The observation is nothing but a rating ("200", "200A", "200 AMP").
    static let ratingOnly = #"^\s*(100|125|150|175|200|225)\s*(?:a|amps?|amperes?)?\s*$"#
    static let branchOnly = #"^\s*(15|20|25|30|40|50)\s*a?\s*$"#
    /// MAIN as a word (not "maintain", "remain", "domain"), MAIN BREAKER/BKR/CB/DISCONNECT, SERVICE DISCONNECT.
    static let mainWord = #"(?<![a-z])(main(\s*(breaker|brkr|bkr|cb|disconnect|disc))?|service\s+disconnect)(?![a-z])"#
    /// "Main lugs (only)", "MLO", "main bus", "non-main": the panel has no main breaker, or the number is the bus.
    static let notAMain = #"(?<![a-z])(main\s*lugs?|mlo|main\s*bus|non[\s-]?main|main\s*lug\s*only)(?![a-z])"#
    /// Row words that change what an amp number on that row means.
    static let rowVeto = #"(?<![a-z])(per\s*st[a@][bdh]s?|stabs?|bus(\s*bar)?|max(imum)?|min(imum)?|rated|ratings?|lugs?|mlo|sccr|short[\s-]*circuit|interrupt\w*|withstand|k?aic|\d\s*ka(?![a-z])|ka(?![a-z])|awg|kcmil|mcm|torque|tighten\w*|in[\s.\-]*[l1i|\[]?bs|lb[\s.\-]*in|\d\s*v(ac|dc)?(?![a-z])|volts?|vac|vdc|\d\s*hz|hz|\d\s*ph(?![a-z])|phase|load\s*cent(er|re)|panelboard|cat(alog)?\.?\s*(no|#)|model|series|type|suitable|service\s+entrance|not\s+to\s+exceed|total|branch|tandem|feeder|sub[\s-]*feed|\d\s*[-–]\s*\d)(?![a-z])"#
    /// Two or more of these and the crop is a printed label or table, not a breaker face.
    static let labelWords = #"(?<![a-z])(awg|torque|tighten\w*|in[\s.\-]*[l1i|\[]?bs|stabs?|install\w*|accordance|codes?|warning|caution|danger|listed|catalog|cat\.?\s*no|sccr|suitable|conductors?|copper|alumin\w*|wire)(?![a-z])"#
    static let panelWords = #"(?<![a-z])(panel|main|bus|lugs?|mlo|load\s*cent(er|re)|panelboard|breakers?|circuits?|stabs?|neutral|ground(ing)?\s*bar|square\s*d|siemens|eaton|cutler|murray|homeline|tye|awg|torque)(?![a-z])"#
    /// A meter nameplate (kWh, watthour, CL200 or "CL.200", FM2S, Kh 7.2): not a panel.
    static let meterCue = #"(?<![a-z])(kwh|watt[\s-]?hour|cl[\s.\-]?(10|20|100|200|320)(?!\d)|fm\s*\d+s|form\s*\d+s|k\s?h\s*\d)"#
    static let disconnectOnly = #"(?<![a-z])((ac\s+)?disconnect|discon|fusible|non[\s-]?fusible|pull[\s-]?out)(?![a-z])"#

    private static let ratingRegex = try? NSRegularExpression(pattern: ratingToken, options: [.caseInsensitive])

    /// The main breaker's rating on this crop, and whether the crop is a panel at all. Nil when it is not a panel
    /// (a meter, a disconnect, an appliance, or text with no panel words). `detectorPanelBox` is a real panel box
    /// from the detector: only then may the largest-handle path run.
    static func panelRead(in raw: [ScanTextLine], detectorPanelBox: Bool) -> PanelRead? {
        let lines = raw.filter { $0.confidence >= minLineConfidence }
        let texts = lines.map { normalize($0.text) }
        if texts.contains(where: { matches($0, meterCue) }) { return nil }
        // AC condensers and heat pumps carry "breaker" and "circuit" too, and the detector scores them as meters.
        if texts.contains(where: isApplianceLabel) { return nil }
        let labelHits = texts.filter { matches($0, labelWords) }.count
        let labelMode = labelHits >= 2
        let branch = lines.filter { matches(normalize($0.text), branchOnly) }
        let disconnectBox = texts.contains { matches($0, disconnectOnly) && !matches($0, mainWord) }
        let evidence = !disconnectBox && (labelMode || branch.count >= 3 || texts.contains { matches($0, panelWords) })
        let vetoed: (ScanTextLine) -> Bool = { matches(rowText(of: $0, in: lines), rowVeto) }
        let evidenceBox = lines.map(\.box).reduce(nil as CGRect?) { partial, box in partial.map { $0.union(box) } ?? box }

        var found: [(amps: Int, basis: MainBreakerBasis, box: CGRect)] = []
        let mains = lines.filter { let text = normalize($0.text); return matches(text, mainWord) && !matches(text, notAMain) }
        for main in mains where !matches(rowText(of: main, in: lines), notAMain) && !vetoed(main) {
            // (A) MAIN and the rating in one observation, or in the next cell of the same row.
            let row = rowMates(of: main, in: lines)
            let adjacent = row.filter { $0 == main || horizontalGap($0.box, main.box) <= max($0.box.height, main.box.height) * 8 }
            let rowRatings = adjacent.flatMap { tokens(in: normalize($0.text)) }
            if rowRatings.count == 1 {
                found.append((rowRatings[0], .mainRow, adjacent.map(\.box).reduce(main.box) { $0.union($1) }))
                continue
            }
            if rowRatings.count > 1 { continue }
            // (B) The rating alone, directly above or below MAIN.
            let stacked = lines.filter { other in
                other != main && matches(normalize(other.text), ratingOnly)
                    && abs(other.box.midY - main.box.midY) <= max(other.box.height, main.box.height) * 1.8
                    && abs(other.box.midY - main.box.midY) >= max(other.box.height, main.box.height) * 0.6
                    && horizontalOverlap(other.box, main.box) >= 0.3
                    && !vetoed(other)
            }
            let values = Set(stacked.flatMap { tokens(in: normalize($0.text)) })
            if values.count == 1, let amps = values.first {
                found.append((amps, .mainNeighbor, stacked.map(\.box).reduce(main.box) { $0.union($1) }))
            }
        }
        let mainValues = Set(found.map(\.amps))
        if mainValues.count == 1, let first = found.first {
            return PanelRead(amps: first.amps, basis: first.basis, isPanelEvidence: true, labelMode: labelMode, box: first.box)
        }
        if mainValues.count > 1 {
            return PanelRead(amps: nil, basis: nil, isPanelEvidence: true, labelMode: labelMode, box: evidenceBox)
        }

        // (C) Largest handle: a breaker face with branch handles in view, never a printed label.
        if detectorPanelBox, !labelMode, branch.count >= 2 {
            let ratingsOnly = lines.filter { matches(normalize($0.text), ratingOnly) && !vetoed($0) }
            let values = Set(ratingsOnly.flatMap { tokens(in: normalize($0.text)) })
            let tallestBranch = branch.map(\.box.height).max() ?? 0
            if values.count == 1, let amps = values.first, handleRatings.contains(amps),
               let line = ratingsOnly.max(by: { $0.box.height < $1.box.height }),
               line.box.height >= tallestBranch * handleHeightRatio {
                return PanelRead(amps: amps, basis: .largestHandle, isPanelEvidence: true, labelMode: false, box: line.box)
            }
        }
        return evidence ? PanelRead(amps: nil, basis: nil, isPanelEvidence: true, labelMode: labelMode, box: evidenceBox) : nil
    }

    /// The same MAIN rules on lines with no boxes (a photo's text top to bottom, or the live number scanner's
    /// transcripts): path A on each line, path B on the line right above or below MAIN. No largest-handle path.
    static func mainBreakerAmps(inLines raw: [String]) -> Int? {
        let texts = raw.map(normalize)
        if texts.contains(where: { matches($0, meterCue) }) { return nil }
        if texts.contains(where: isApplianceLabel) { return nil }
        var found: [Int] = []
        for (index, text) in texts.enumerated()
        where matches(text, mainWord) && !matches(text, notAMain) && !matches(text, rowVeto) {
            let ratings = tokens(in: text)
            if ratings.count == 1 {
                found.append(ratings[0])
                continue
            }
            if ratings.count > 1 { continue }
            let neighbors = [index - 1, index + 1].filter { texts.indices.contains($0) }.map { texts[$0] }
            let values = Set(neighbors.filter { matches($0, ratingOnly) && !matches($0, rowVeto) }.flatMap { tokens(in: $0) })
            if values.count == 1, let amps = values.first { found.append(amps) }
        }
        let values = Set(found)
        return values.count == 1 ? values.first : nil
    }

    static func tokens(in text: String) -> [Int] {
        guard let ratingRegex else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return ratingRegex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) }
        }.filter { breakerRatings.contains($0) }
    }

    static func horizontalGap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, max(a.minX, b.minX) - min(a.maxX, b.maxX))
    }

    static func horizontalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let shared = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        return max(0, shared) / max(min(a.width, b.width), 0.001)
    }

    // MARK: Meter number

    /// SERIAL (and OCR's "sertal", "seria1"), S/N, METER NO, MTR NO, or METER beside or above the number.
    static let serialLabel = #"(?<![a-z])(ser[il1t|][a@][l1i]|s\s*/\s*n|serial\s*(no|number|#)|meter\s*(no|number|#)|mtr\s*(no|#)?|meter)(?![a-z])"#
    /// A long number on these lines is a register, a model, a certification, or a date, not the meter number.
    static let meterLineVeto = #"(?<![a-z])(kwh|kvarh|kw|kvar|fcc|ic\s*:|pat(ent)?|model|cat(alog)?|mfg|made|date|lot)(?![a-z])"#

    /// The meter number on this label, or nil. The tallest long number wins, and one on or right under a serial label
    /// wins over a taller one. AC and heat-pump nameplates also carry long numbers, so a label with refrigerant or
    /// compressor words never gives one. The kWh register, FCC ids, models, phone numbers, and an LCD test pattern
    /// ("8888888") are never the meter number.
    static func meterNumber(in raw: [ScanTextLine]) -> MeterRead? {
        let lines = raw.filter { $0.confidence >= minLineConfidence }
        let texts = lines.map { normalize($0.text) }
        guard !texts.contains(where: isApplianceLabel) else { return nil }
        let cue = texts.contains(where: hasMeterCue)
        var best: (score: Double, read: MeterRead)?
        for (line, text) in zip(lines, texts) {
            if matches(text, meterLineVeto) { continue }
            for run in digitRuns(in: text) where meterDigits.contains(run.digits.count) {
                if looksLikePhoneNumber(run.grouping) { continue }
                if Set(run.digits).count == 1 { continue }
                var score = Double(line.box.height) * 20 + Double(line.confidence)
                let row = rowText(of: line, in: lines)
                let above = lines.filter { $0.box.midY > line.box.midY && $0.box.midY - line.box.midY <= line.box.height * 2.5 }
                if matches(row, serialLabel) || above.contains(where: { matches(normalize($0.text), serialLabel) }) {
                    score += 3
                }
                if best == nil || score > best!.score {
                    best = (score, MeterRead(number: run.digits, box: line.box, hasMeterCue: cue))
                }
            }
        }
        return best?.read
    }

    /// A meter word anywhere on the label: the strong cues above, or "meter", "mtr", "Kh", a form number.
    static func hasMeterCue(_ text: String) -> Bool {
        let lower = normalize(text)
        if matches(lower, meterCue) { return true }
        return lower.range(of: #"(?<![a-z])(meter|mtr|kh|fm ?\d+s|form ?\d+s)(?![a-z])"#, options: .regularExpression) != nil
    }

    /// Words on AC condensers and heat pumps, which the detector scores as meters.
    private static func isApplianceLabel(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = ["refrigerant", "r-410a", "r410a", "r-22", "r-454b", "r454b", "compressor", "condens", "seer", "btu",
                     "hvac", "fan motor", "heat pump", "air condition", "min. circuit", "max. fuse", "mca", "mocp"]
        return words.contains { lower.contains($0) }
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
}

/// One OCR pass over a crop of a copied frame.
struct ScanTextRead: @unchecked Sendable {
    var kind: EquipmentKind
    /// The capture attempt that asked for it. A newer attempt drops older reads.
    var generation: Int
    /// The Vision-normalized region of the upright frame that was read.
    var region: CGRect
    var textFirst: Bool
    /// The crop was a real panel box from the detector, so the largest-handle path could run.
    var detectorPanelBox = false
    var meter: ScanTextParser.MeterRead?
    var panel: ScanTextParser.PanelRead?
    /// Box of the read value in the whole upright frame (Vision-normalized), for a text-first candidate.
    var textBox: CGRect?
    /// The full-resolution crop that was read. It becomes the photo when this read captures.
    var image: CGImage?
    var lines: [String]

    /// A panel read with a main-breaker value is "main:<amps>"; a panel with no main read is "panel".
    static let mainPrefix = "main:"
    static let panelEvidence = "panel"

    /// The value this read found, as text, so two reads can be compared: the meter number, "main:<amps>", or "panel".
    var value: String? {
        switch kind {
        case .electricMeter:
            return meter?.number
        case .breakerPanel:
            if let amps = panel?.amps { return Self.mainPrefix + String(amps) }
            return panel?.isPanelEvidence == true ? Self.panelEvidence : nil
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
        detectorPanelBox: Bool,
        generation: Int,
        completion: @escaping @Sendable (ScanTextRead) -> Void
    ) {
        queue.async { [context] in
            var result = ScanTextRead(
                kind: kind,
                generation: generation,
                region: region,
                textFirst: textFirst,
                detectorPanelBox: detectorPanelBox,
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
                result.panel = ScanTextParser.panelRead(in: lines, detectorPanelBox: detectorPanelBox && !textFirst)
                local = result.panel?.box
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
    /// A wider panel photo taken after the lock. It replaces panel.jpg only; the lock and the amps stay as they are.
    var photoOnly = false
    /// Which OCR rule read `mainBreakerAmps`. Nil with no amps.
    var mainBreakerBasis: MainBreakerBasis? = nil
}

/// The frame an OCR read came from, kept with the read so the capture judges and photographs that same frame.
struct CaptureReadContext {
    /// When the frame was captured (media time). Agreeing reads must come from frames 0.4 s or more apart.
    var frameTime: CFTimeInterval
    /// Where the candidate landed on the wall, and which way the wall faced.
    var landing: SIMD3<Float>?
    var landingNormal: SIMD3<Float>?
    var cameraPosition: SIMD3<Float>
    /// The detector box that was read, and which path proposed it ("breakerPanel-box", "meter-box-as-panel", "text").
    var candidateBox: CGRect?
    var source: String
    /// The copied frame, for the panel photo. Only the newest record keeps it.
    var pixels: CopiedPixels?
    var orientation: CGImagePropertyOrientation
}

/// One OCR read the gate kept, with where the candidate was when its frame was taken.
struct CaptureReadRecord {
    var read: ScanTextRead
    var landing: SIMD3<Float>?
    var context: CaptureReadContext
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
    /// The frame and candidate of the in-flight OCR read.
    var pendingContext: CaptureReadContext?
    /// Text-first candidate: the box of the last good read of MAIN + rating (or a meter number), and when.
    var textCandidate: (box: CGRect, at: CFTimeInterval)?
    /// Good frames in a row whose OCR found no value.
    var emptyReads = 0
    /// Panel reads with no main-breaker value, and whether the last one was a printed label, for the hint.
    var readsWithoutMain = 0
    var lastReadLabelMode = false
    /// Half the meter enclosure's width from the last passing detector box, for the lock.
    var meterHalfWidth: Float?

    mutating func breakStreak() {
        streak = 0
        lastBox = nil
        lastLanding = nil
        landings = []
    }
}
