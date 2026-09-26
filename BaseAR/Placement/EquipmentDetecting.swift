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
    var kind: EquipmentKind
    var confidence: Float
    var boundingBox: CGRect
}

/// The AR session asks for boxes. It does not own the Core ML model.
protocol EquipmentDetecting: AnyObject {
    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> [EquipmentDetection]
}

/// "No detections" means a supported model output was read, not that the scene is clear.
enum EquipmentObservationStatus: String, Sendable {
    case success
    case noDetections
    case modelUnavailable
    case inferenceFailed
    case frameUnavailable

    var isSuccessfulInference: Bool {
        self == .success || self == .noDetections
    }
}

struct EquipmentDetectionResult: Sendable {
    let detections: [EquipmentDetection]
    let status: EquipmentObservationStatus
    let errorMessage: String?
}

/// All times use the monotonic, seconds-since-boot clock, not wall-clock dates.
struct EquipmentScanObservation: Sendable, Equatable {
    let id: UUID
    let generation: UInt64
    let capturedAt: TimeInterval
    let completedAt: TimeInterval
    /// Copying, depth extraction and inference time on the worker; excludes queue wait.
    let processingDuration: TimeInterval
    let status: EquipmentObservationStatus
    let errorMessage: String?
}

/// EquipmentScan is a YOLO detector fine-tuned on meter and panel photos (scripts/train_equipment.py).
/// The recognizer only reads that package.
final class YOLOEquipmentDetector: EquipmentDetecting, @unchecked Sendable {
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

    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> [EquipmentDetection] {
        guard let request else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let recognized = Self.recognizedObjects(in: request.results)
        if !recognized.isEmpty { return recognized }
        return Self.featureBoxes(in: request.results)
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
        request.imageCropAndScaleOption = .scaleFill
        return request
    }

    private static func recognizedObjects(in results: [VNObservation]?) -> [EquipmentDetection] {
        (results ?? []).compactMap { result in
            guard let object = result as? VNRecognizedObjectObservation,
                  let label = object.labels.first,
                  let kind = kind(for: label.identifier) else { return nil }
            return EquipmentDetection(kind: kind, confidence: label.confidence, boundingBox: object.boundingBox)
        }
    }

    /// Ultralytics NMS exports confidence and coordinates when Vision does not wrap them as objects.
    private static func featureBoxes(in results: [VNObservation]?) -> [EquipmentDetection] {
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
            let centerX = CGFloat(coordinates[box * 4].floatValue)
            let centerY = CGFloat(coordinates[box * 4 + 1].floatValue)
            let width = CGFloat(coordinates[box * 4 + 2].floatValue)
            let height = CGFloat(coordinates[box * 4 + 3].floatValue)
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

    var displayTransform: CGAffineTransform {
        CGAffineTransform(a: displayA, b: displayB, c: displayC, d: displayD, tx: displayTX, ty: displayTY)
    }
}

/// Copies AR frames on the session callback and runs the detector on a background queue. The latest packet is drained on the main thread.
final class EquipmentScanBridge: @unchecked Sendable {
    let detector = YOLOEquipmentDetector()
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
    func consider(_ frame: ARFrame) {
        guard case .normal = frame.camera.trackingState else { return }
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
            depth: EquipmentPixelBuffer.depthSample(from: frame.smoothedSceneDepth ?? frame.sceneDepth)
        )
        // The session delegate runs on the main queue. Only the copies above touch the frame; inference runs here.
        let copied = CopiedPixels(buffer: pixels)
        inference.async { [self] in
            var packet = geometry
            packet.detections = detector.detect(in: copied.buffer, orientation: visionOrientation)
            let finished = packet
            latest.withLock { $0 = finished }
            gate.withLock { $0.busy = false }
        }
    }

    private static func visionOrientation(for interface: UIInterfaceOrientation) -> CGImagePropertyOrientation {
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

/// The copy is owned by one inference job, so handing it across queues is safe.
private struct CopiedPixels: @unchecked Sendable {
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
