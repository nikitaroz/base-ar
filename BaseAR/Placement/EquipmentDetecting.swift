import ARKit
import CoreML
import CoreVideo
import Foundation
import os
import simd
import UIKit
import Vision

enum EquipmentKind: String, Sendable {
    case electricMeter
    case breakerPanel

    var title: String {
        switch self {
        case .electricMeter: "Meter"
        case .breakerPanel: "Panel"
        }
    }
}

/// One box from the EquipmentScan detector. The rect is Vision-normalized, origin at the lower left of the upright image.
struct EquipmentDetection: Sendable {
    /// Provisional cutoffs on the true detector score. On held-out site photos the YOLO26s model scores real meters
    /// and panels 0.77+, even shrunk to 20% size, while a laptop keyboard reads as a panel at about 0.35. Tune both
    /// from the DEBUG `EquipmentScan` log on a device.
    static let drawConfidence: Float = 0.40
    static let lockConfidence: Float = 0.45

    var kind: EquipmentKind
    /// The detector's own score for this box (`VNRecognizedObjectObservation.confidence`), not the label share.
    var confidence: Float
    var boundingBox: CGRect
    /// Focus and exposure inside the box, measured on the inference queue for the capture gate. Nil past the
    /// first few boxes of a frame, or for a box too small to measure.
    var quality: CaptureReading? = nil
}

/// Why a frame came back with the boxes it has. A model that failed to load or run must not look like an empty wall.
enum EquipmentObservationStatus: Sendable, Equatable {
    /// The model ran. No boxes means it saw nothing it knows, not that the scene has no meter.
    case ok
    /// EquipmentScan did not load, so no frame will ever have boxes.
    case modelMissing
    /// Vision threw on this frame.
    case inferenceFailed
}

struct EquipmentDetectionResult: Sendable {
    var detections: [EquipmentDetection]
    var status: EquipmentObservationStatus
    var errorMessage: String?
}

/// The AR session asks for boxes. It does not own the Core ML model.
protocol EquipmentDetecting: AnyObject {
    func detectResult(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> EquipmentDetectionResult
}

extension EquipmentDetecting {
    /// Boxes only. Callers that need to tell a failure from an empty frame use `detectResult`.
    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> [EquipmentDetection] {
        detectResult(in: pixelBuffer, orientation: orientation).detections
    }
}

/// EquipmentScan is a YOLO detector fine-tuned on meter and panel photos (scripts/train_equipment.py).
/// The recognizer only reads that package.
final class YOLOEquipmentDetector: EquipmentDetecting, @unchecked Sendable {
    private static let log = Logger(subsystem: "BaseAR", category: "EquipmentScan")
    private let request: VNCoreMLRequest?
    private let lock = NSLock()
    let loadError: String?

    init() {
        do {
            request = try Self.makeRequest()
            loadError = nil
        } catch {
            request = nil
            loadError = error.localizedDescription
        }
    }

    func detectResult(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> EquipmentDetectionResult {
        guard let request else {
            return EquipmentDetectionResult(detections: [], status: .modelMissing, errorMessage: loadError)
        }
        lock.lock()
        defer { lock.unlock() }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            #if DEBUG
            Self.log.debug("inference failed: \(error.localizedDescription, privacy: .public)")
            #endif
            return EquipmentDetectionResult(detections: [], status: .inferenceFailed, errorMessage: error.localizedDescription)
        }
        var found = Self.recognizedObjects(in: request.results)
        if found.isEmpty {
            let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
            let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
            let sideways: Set<CGImagePropertyOrientation> = [.left, .right, .leftMirrored, .rightMirrored]
            let uprightAspect = sideways.contains(orientation) ? height / width : width / height
            found = Self.featureBoxes(in: request.results, uprightAspect: uprightAspect)
        }
        return EquipmentDetectionResult(detections: found, status: .ok, errorMessage: nil)
    }

    private static func makeRequest() throws -> VNCoreMLRequest {
        guard let url = Bundle.main.url(forResource: "EquipmentScan", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "EquipmentScan", withExtension: "mlpackage") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try MLModel(contentsOf: url, configuration: configuration)
        let vision = try VNCoreMLModel(for: model)
        let request = VNCoreMLRequest(model: vision)
        // Pad to square like Ultralytics training does, instead of squashing the 4:3 frame.
        // Vision maps object boxes back to the full image; featureBoxes undoes the padding itself.
        request.imageCropAndScaleOption = .scaleFit
        return request
    }

    private static func recognizedObjects(in results: [VNObservation]?) -> [EquipmentDetection] {
        (results ?? []).compactMap { result in
            guard let object = result as? VNRecognizedObjectObservation,
                  let label = object.labels.first,
                  let kind = kind(for: label.identifier) else { return nil }
            // The label's confidence is only this class's share of meter vs panel (about 0.99 on every box that
            // survives NMS). The observation's confidence is the detector score the thresholds are meant for.
            #if DEBUG
            let box = object.boundingBox
            log.debug("\(kind.rawValue, privacy: .public) score=\(object.confidence, format: .fixed(precision: 3)) share=\(label.confidence, format: .fixed(precision: 3)) area=\(Double(box.width * box.height), format: .fixed(precision: 3)) x=\(Double(box.midX), format: .fixed(precision: 2)) y=\(Double(box.midY), format: .fixed(precision: 2))")
            #endif
            return EquipmentDetection(kind: kind, confidence: object.confidence, boundingBox: object.boundingBox)
        }
    }

    /// Ultralytics NMS exports confidence and coordinates when Vision does not wrap them as objects.
    /// Raw coordinates are in the padded square, so they are mapped back using the upright width / height.
    private static func featureBoxes(in results: [VNObservation]?, uprightAspect: CGFloat) -> [EquipmentDetection] {
        var confidence: MLMultiArray?
        var coordinates: MLMultiArray?
        for result in results ?? [] {
            guard let feature = result as? VNCoreMLFeatureValueObservation,
                  let array = feature.featureValue.multiArrayValue else { continue }
            switch feature.featureName {
            case "confidence": confidence = array
            case "coordinates": coordinates = array
            default: break
            }
        }
        guard let confidence, let coordinates else { return [] }
        let boxes = max(coordinates.shape[0].intValue, 0)
        let classes = confidence.shape.count > 1 ? confidence.shape[1].intValue : 1
        guard boxes > 0, coordinates.shape.last?.intValue == 4 else { return [] }
        var found: [EquipmentDetection] = []
        for box in 0..<boxes {
            var bestClass = 0
            var bestScore: Float = 0
            for klass in 0..<classes {
                let score = confidence[box * classes + klass].floatValue
                if score > bestScore {
                    bestScore = score
                    bestClass = klass
                }
            }
            guard bestScore > 0, let kind = kind(at: bestClass) ?? kind(for: "\(bestClass)") else { continue }
            var centerX = CGFloat(coordinates[box * 4].floatValue)
            var centerY = CGFloat(coordinates[box * 4 + 1].floatValue)
            var width = CGFloat(coordinates[box * 4 + 2].floatValue)
            var height = CGFloat(coordinates[box * 4 + 3].floatValue)
            // scaleFit centers the image in the square: a wide image leaves bands above and below, a tall one at the sides.
            if uprightAspect > 1 {
                centerY = (centerY - 0.5) * uprightAspect + 0.5
                height *= uprightAspect
            } else if uprightAspect > 0 {
                centerX = (centerX - 0.5) / uprightAspect + 0.5
                width /= uprightAspect
            }
            guard width > 0.01, height > 0.01 else { continue }
            // Ultralytics NMS boxes are center xywh with the origin at the top of the upright image.
            let originX = centerX - width / 2
            let originY = 1 - centerY - height / 2
            found.append(EquipmentDetection(
                kind: kind,
                confidence: bestScore,
                boundingBox: CGRect(x: originX, y: originY, width: width, height: height)
            ))
        }
        return found
    }

    private static func kind(for identifier: String) -> EquipmentKind? {
        switch identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "electric meter", "electric_meter": .electricMeter
        case "breaker panel", "breaker_panel": .breakerPanel
        default: nil
        }
    }

    private static func kind(at index: Int) -> EquipmentKind? {
        switch index {
        case 0: .electricMeter
        case 1: .breakerPanel
        default: nil
        }
    }
}

struct DepthSample: Sendable {
    var width: Int
    var height: Int
    var meters: [Float]
    var confidence: [UInt8]?
}

/// Pose and image geometry captured with a frame, so projection can run after that frame is released.
struct EquipmentScanFrame: Sendable {
    var detections: [EquipmentDetection]
    var visionOrientation: CGImagePropertyOrientation
    var imageSize: CGSize
    var viewSize: CGSize
    var intrinsics: simd_float3x3
    var cameraTransform: simd_float4x4
    var displayA: CGFloat
    var displayB: CGFloat
    var displayC: CGFloat
    var displayD: CGFloat
    var displayTX: CGFloat
    var displayTY: CGFloat
    var depth: DepthSample?
    /// Media time when the frame was captured, so a packet held past a stalled inference is not read as current.
    var capturedAt: CFTimeInterval = 0
    var status: EquipmentObservationStatus = .ok
    /// The camera image the boxes came from, so a lock crops its photo and the capture gate reads text from this
    /// same frame instead of a later one. A copy: no `ARFrame` is kept.
    var pixels: CopiedPixels?
    /// The middle of the screen (`EquipmentScanBridge.centerFraction` of each side) as a Vision-normalized rect of
    /// the upright image, and its focus and exposure. The text-first panel search reads this region.
    var centerRegion: CGRect?
    var centerQuality: CaptureReading?

    var displayTransform: CGAffineTransform {
        CGAffineTransform(a: displayA, b: displayB, c: displayC, d: displayD, tx: displayTX, ty: displayTY)
    }
}

/// Copies AR frames on the session callback and runs the detector on a background queue. The latest packet is drained on the main thread.
final class EquipmentScanBridge: @unchecked Sendable {
    let detector = YOLOEquipmentDetector()
    /// Share of the screen's width and height, around its center, that counts as "in the middle" for the capture gate.
    static let centerFraction: CGFloat = 0.6
    /// Boxes per frame that get a focus and exposure reading, strongest first.
    private static let measuredBoxes = 4
    private let gate = OSAllocatedUnfairLock(initialState: Gate())
    private let latest = OSAllocatedUnfairLock<EquipmentScanFrame?>(initialState: nil)
    private let inference = DispatchQueue(label: "BaseAR.equipment-scan", qos: .userInitiated)

    private struct Gate {
        var enabled = false
        var busy = false
        var lastFire = 0.0
        var viewSize = CGSize.zero
        var orientation = UIInterfaceOrientation.portrait
    }

    func setEnabled(_ enabled: Bool) {
        gate.withLock { $0.enabled = enabled }
    }

    func setViewport(_ size: CGSize, orientation: UIInterfaceOrientation) {
        gate.withLock {
            $0.viewSize = size
            $0.orientation = orientation
        }
    }

    func takeLatest() -> EquipmentScanFrame? {
        latest.withLock { packet in
            let current = packet
            packet = nil
            return current
        }
    }

    /// Schedules at most one Vision request every quarter second, and only while tracking is normal.
    /// Without a model there is nothing to run, so frames are not copied; the controller reads `loadError`.
    func consider(_ frame: ARFrame) {
        guard detector.loadError == nil, case .normal = frame.camera.trackingState else { return }
        let now = CACurrentMediaTime()
        let snapshot: (CGSize, UIInterfaceOrientation)? = gate.withLock { gate in
            guard gate.enabled, !gate.busy, gate.viewSize.width > 1, now - gate.lastFire >= 0.25 else { return nil }
            gate.lastFire = now
            gate.busy = true
            return (gate.viewSize, gate.orientation)
        }
        guard let (viewSize, interface) = snapshot else { return }
        let visionOrientation = Self.visionOrientation(for: interface)
        guard let pixels = EquipmentPixelBuffer.copy(frame.capturedImage) else {
            gate.withLock { $0.busy = false }
            return
        }
        let transform = frame.displayTransform(for: interface, viewportSize: viewSize)
        let geometry = EquipmentScanFrame(
            detections: [],
            visionOrientation: visionOrientation,
            imageSize: CGSize(
                width: CVPixelBufferGetWidth(frame.capturedImage),
                height: CVPixelBufferGetHeight(frame.capturedImage)
            ),
            viewSize: viewSize,
            intrinsics: frame.camera.intrinsics,
            cameraTransform: frame.camera.transform,
            displayA: transform.a,
            displayB: transform.b,
            displayC: transform.c,
            displayD: transform.d,
            displayTX: transform.tx,
            displayTY: transform.ty,
            depth: EquipmentPixelBuffer.depthSample(from: frame.smoothedSceneDepth ?? frame.sceneDepth),
            capturedAt: now
        )
        // The session delegate runs on the main queue. Only the copies above touch the frame; inference runs here.
        let copied = CopiedPixels(buffer: pixels)
        inference.async { [self] in
            var packet = geometry
            let result = detector.detectResult(in: copied.buffer, orientation: visionOrientation)
            #if DEBUG
            // The frame recorder's periodic sample: exactly the image the model saw, with its boxes.
            let recording = FrameRecorder.shared.isRecording
            if recording, FrameRecorder.shared.wants(FrameRecorder.Reason.periodic) {
                FrameRecorder.shared.recordPixels(
                    copied.buffer,
                    camera: FrameRecorder.Camera(
                        intrinsics: geometry.intrinsics,
                        transform: geometry.cameraTransform,
                        imageSize: geometry.imageSize,
                        timestamp: geometry.capturedAt,
                        imageOrientation: visionOrientation
                    ),
                    reason: FrameRecorder.Reason.periodic,
                    metadata: [
                        "status": "\(result.status)",
                        "detections": result.detections.map {
                            FrameRecorder.detection(label: $0.kind.rawValue, confidence: $0.confidence, visionBox: $0.boundingBox)
                        }
                    ]
                )
            }
            #else
            let recording = false
            #endif
            var detections = result.detections.sorted { $0.confidence > $1.confidence }
            for index in detections.indices.prefix(Self.measuredBoxes) {
                detections[index].quality = CaptureQuality.measure(
                    copied.buffer,
                    visionRect: detections[index].boundingBox,
                    orientation: visionOrientation
                )
            }
            packet.detections = detections
            packet.status = result.status
            // While the frame recorder runs, every packet carries its image so gate decisions can be saved with it.
            if recording { packet.pixels = copied }
            if result.status == .ok {
                packet.pixels = copied
                let center = CaptureQuality.centerVisionRect(
                    fraction: Self.centerFraction,
                    displayTransform: transform,
                    orientation: visionOrientation
                )
                packet.centerRegion = center
                packet.centerQuality = CaptureQuality.measure(copied.buffer, visionRect: center, orientation: visionOrientation)
            }
            let finished = packet
            latest.withLock { $0 = finished }
            gate.withLock { $0.busy = false }
        }
    }

    /// The orientation Vision is given for camera frames in this interface orientation.
    static func visionOrientation(for interface: UIInterfaceOrientation) -> CGImagePropertyOrientation {
        switch interface {
        case .portrait: .right
        case .portraitUpsideDown: .left
        // capturedImage is upright in landscapeRight (home side on the right).
        case .landscapeRight: .up
        case .landscapeLeft: .down
        default: .right
        }
    }
}

/// The copy is owned by one inference job and never written after it, so handing it across queues is safe.
struct CopiedPixels: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

enum EquipmentPixelBuffer {
    static func copy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let format = CVPixelBufferGetPixelFormatType(source)
        var destination: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, nil, &destination) == kCVReturnSuccess,
              let destination else { return nil }
        guard transfer(from: source, to: destination) else { return nil }
        return destination
    }

    static func depthSample(from depth: ARDepthData?) -> DepthSample? {
        guard let depth else { return nil }
        let map = depth.depthMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        var meters = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            let source = base.advanced(by: row * rowBytes).assumingMemoryBound(to: Float.self)
            for column in 0..<width {
                meters[row * width + column] = source[column]
            }
        }
        return DepthSample(width: width, height: height, meters: meters, confidence: confidenceValues(depth.confidenceMap))
    }

    private static func confidenceValues(_ map: CVPixelBuffer?) -> [UInt8]? {
        guard let map else { return nil }
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        var values = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let source = base.advanced(by: row * rowBytes).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width {
                values[row * width + column] = source[column]
            }
        }
        return values
    }

    private static func transfer(from source: CVPixelBuffer, to destination: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(destination, [])
        }
        let planes = CVPixelBufferGetPlaneCount(source)
        if planes == 0 {
            return copyPlane(from: source, to: destination, plane: nil)
        }
        for plane in 0..<planes where !copyPlane(from: source, to: destination, plane: plane) {
            return false
        }
        return true
    }

    private static func copyPlane(from source: CVPixelBuffer, to destination: CVPixelBuffer, plane: Int?) -> Bool {
        let sourceBase: UnsafeMutableRawPointer?
        let destinationBase: UnsafeMutableRawPointer?
        let height: Int
        let sourceStride: Int
        let destinationStride: Int
        if let plane {
            sourceBase = CVPixelBufferGetBaseAddressOfPlane(source, plane)
            destinationBase = CVPixelBufferGetBaseAddressOfPlane(destination, plane)
            height = CVPixelBufferGetHeightOfPlane(source, plane)
            sourceStride = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
            destinationStride = CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
        } else {
            sourceBase = CVPixelBufferGetBaseAddress(source)
            destinationBase = CVPixelBufferGetBaseAddress(destination)
            height = CVPixelBufferGetHeight(source)
            sourceStride = CVPixelBufferGetBytesPerRow(source)
            destinationStride = CVPixelBufferGetBytesPerRow(destination)
        }
        guard let sourceBase, let destinationBase, height > 0 else { return false }
        let rowBytes = min(sourceStride, destinationStride)
        for row in 0..<height {
            memcpy(destinationBase.advanced(by: row * destinationStride), sourceBase.advanced(by: row * sourceStride), rowBytes)
        }
        return true
    }
}
