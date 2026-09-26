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

/// YOLOE prompts are baked into EquipmentScan. The recognizer only reads that package.
final class YOLOEEquipmentDetector: EquipmentDetecting, @unchecked Sendable {
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

    /// Compatibility only: callers needing failure semantics must use detectResult.
    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> [EquipmentDetection] {
        detectResult(in: pixelBuffer, orientation: orientation).detections
    }

    func detectResult(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> EquipmentDetectionResult {
        guard let request else {
            return EquipmentDetectionResult(
                detections: [], status: .modelUnavailable, errorMessage: loadError ?? "Equipment model unavailable."
            )
        }
        // Vision requests have mutable results. Serialize legacy callers as well as bridge work.
        lock.lock()
        defer { lock.unlock() }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
            let detections: [EquipmentDetection]
            if let objects = request.results as? [VNRecognizedObjectObservation] {
                detections = try Self.recognizedObjects(in: objects)
            } else {
                detections = try Self.featureBoxes(in: request.results)
            }
            return EquipmentDetectionResult(
                detections: detections,
                status: detections.isEmpty ? .noDetections : .success,
                errorMessage: nil
            )
        } catch {
            return EquipmentDetectionResult(
                detections: [], status: .inferenceFailed, errorMessage: error.localizedDescription
            )
        }
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

    private enum OutputError: LocalizedError {
        case unsupportedOutput
        case malformedOutput

        var errorDescription: String? {
            switch self {
            case .unsupportedOutput: "Equipment model output is not supported."
            case .malformedOutput: "Equipment model output has invalid dimensions or values."
            }
        }
    }

    private static func recognizedObjects(in objects: [VNRecognizedObjectObservation]) throws -> [EquipmentDetection] {
        try objects.map { object in
            guard let label = object.labels.first,
                  let kind = kind(for: label.identifier) else { throw OutputError.unsupportedOutput }
            let box = object.boundingBox
            guard label.confidence.isFinite, (0...1).contains(label.confidence),
                  box.origin.x.isFinite, box.origin.y.isFinite,
                  box.width.isFinite, box.height.isFinite,
                  box.width > 0, box.height > 0 else { throw OutputError.malformedOutput }
            return EquipmentDetection(kind: kind, confidence: label.confidence, boundingBox: object.boundingBox)
        }
    }

    /// Ultralytics NMS exports confidence and coordinates when Vision does not wrap them as objects.
    private static func featureBoxes(in results: [VNObservation]?) throws -> [EquipmentDetection] {
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
        guard let confidence, let coordinates else { throw OutputError.unsupportedOutput }
        // Support only the known NMS contract [N, 4] / [N, 2]. Check ranks before indexing.
        guard coordinates.shape.count == 2, confidence.shape.count == 2,
              coordinates.shape[1].intValue == 4,
              confidence.shape[1].intValue == 2,
              coordinates.shape[0].intValue >= 0,
              coordinates.shape[0].intValue == confidence.shape[0].intValue else {
            throw OutputError.malformedOutput
        }
        let boxes = coordinates.shape[0].intValue
        let classes = confidence.shape[1].intValue
        guard boxes <= coordinates.count / 4, boxes <= confidence.count / classes else {
            throw OutputError.malformedOutput
        }
        var found: [EquipmentDetection] = []
        for box in 0..<boxes {
            var bestClass = 0
            var bestScore: Float = 0
            for klass in 0..<classes {
                // Multi-index access respects MLMultiArray strides; flattened storage need not be contiguous.
                let score = confidence[[NSNumber(value: box), NSNumber(value: klass)]].floatValue
                guard score.isFinite, (0...1).contains(score) else { throw OutputError.malformedOutput }
                if score > bestScore {
                    bestScore = score
                    bestClass = klass
                }
            }
            guard bestScore > 0, let kind = kind(at: bestClass) else { continue }
            let centerX = CGFloat(coordinates[[NSNumber(value: box), 0]].floatValue)
            let centerY = CGFloat(coordinates[[NSNumber(value: box), 1]].floatValue)
            let width = CGFloat(coordinates[[NSNumber(value: box), 2]].floatValue)
            let height = CGFloat(coordinates[[NSNumber(value: box), 3]].floatValue)
            guard centerX.isFinite, centerY.isFinite, width.isFinite, height.isFinite,
                  width > 0, height > 0 else { throw OutputError.malformedOutput }
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
    /// Nil only for legacy, manually constructed packets. Bridge packets always carry metadata.
    var observation: EquipmentScanObservation? = nil

    var displayTransform: CGAffineTransform {
        CGAffineTransform(a: displayA, b: displayB, c: displayC, d: displayD, tx: displayTX, ty: displayTY)
    }
}

/// One serial worker, no frame backlog, and one replaceable result slot.
final class EquipmentScanBridge: @unchecked Sendable {
    let detector = YOLOEEquipmentDetector()
    /// Freshness policy, not a measured inference-performance guarantee.
    let maximumObservationAge: TimeInterval
    private let worker = DispatchQueue(label: "BaseAR.EquipmentScan", qos: .userInitiated)
    // One lock protects generation, admission, publication and consumption atomically.
    // Invalidation never clears busy: a running Vision request cannot be forcibly cancelled.
    private let gate = OSAllocatedUnfairLock(initialState: Gate())

    private struct Gate {
        var enabled = false
        var busy = false
        var trackingNormal = false
        var generation: UInt64 = 0
        var generationStartedAt: TimeInterval = 0
        var lastFire: TimeInterval?
        var lastFrameTimestamp: TimeInterval?
        var viewSize = CGSize.zero
        var orientation = UIInterfaceOrientation.portrait
        var latestPacket: EquipmentScanFrame?
        var latestObservation: EquipmentScanObservation?

        mutating func invalidate() {
            generation &+= 1
            generationStartedAt = CACurrentMediaTime()
            latestPacket = nil
            latestObservation = nil
            lastFire = nil
        }
    }

    /// ARFrame owns its image/depth buffers. Retaining ONE immutable frame across the
    /// dispatch boundary keeps those buffers and its pose alive until worker copying ends.
    /// No mutable ARSession/ARView state is read on the worker; this is the Sendable boundary.
    private struct CapturedFrame: @unchecked Sendable {
        let frame: ARFrame
        let id: UUID
        let generation: UInt64
        let viewSize: CGSize
        let orientation: UIInterfaceOrientation
    }

    init(maximumObservationAge: TimeInterval = 2.0) {
        precondition(maximumObservationAge.isFinite && maximumObservationAge > 0)
        self.maximumObservationAge = maximumObservationAge
    }

    func setEnabled(_ enabled: Bool) {
        gate.withLock {
            guard $0.enabled != enabled else { return }
            $0.enabled = enabled
            $0.invalidate()
        }
    }

    func setViewport(_ size: CGSize, orientation: UIInterfaceOrientation) {
        gate.withLock {
            guard $0.viewSize != size || $0.orientation != orientation else { return }
            $0.viewSize = size
            $0.orientation = orientation
            $0.invalidate()
        }
    }

    /// Call from ARSession interruption/failure/reset callbacks, even when no frames arrive.
    /// The next normal frame reopens admission; no enable toggle is required for recovery.
    func trackingInterrupted() {
        gate.withLock {
            $0.trackingNormal = false
            $0.invalidate()
        }
    }

    /// Includes failure metadata without passing an empty failure packet to legacy consumers.
    /// Nil means no current observation (disabled, interrupted, invalidated or expired).
    var latestObservation: EquipmentScanObservation? {
        gate.withLock {
            guard $0.enabled, $0.trackingNormal,
                  let observation = $0.latestObservation,
                  observation.generation == $0.generation,
                  isFresh(observation.capturedAt, at: CACurrentMediaTime()) else { return nil }
            return observation
        }
    }

    func takeLatest() -> EquipmentScanFrame? {
        gate.withLock {
            let packet = $0.latestPacket
            $0.latestPacket = nil
            // Independently validate on consumption, not just when the worker publishes.
            guard $0.enabled, $0.trackingNormal,
                  let packet, let observation = packet.observation,
                  observation.generation == $0.generation,
                  observation.status.isSuccessfulInference,
                  isFresh(observation.capturedAt, at: CACurrentMediaTime()) else { return nil }
            return packet
        }
    }

    /// Admission only on the AR callback: copying, depth extraction and Vision run on worker.
    /// Frames arriving while busy are dropped, not queued. A completed result replaces the old one.
    func consider(_ frame: ARFrame) {
        guard case .normal = frame.camera.trackingState else {
            gate.withLock {
                if $0.trackingNormal {
                    $0.trackingNormal = false
                    $0.invalidate()
                }
            }
            return
        }
        let now = CACurrentMediaTime()
        let captured: CapturedFrame? = gate.withLock { gate in
            // A delayed callback captured before interruption/viewport/enable invalidation
            // must not resurrect tracking or acquire the new generation's identity.
            guard frame.timestamp >= gate.generationStartedAt else { return nil }
            gate.trackingNormal = true
            guard gate.enabled, !gate.busy,
                  gate.viewSize.width.isFinite, gate.viewSize.height.isFinite,
                  gate.viewSize.width > 1, gate.viewSize.height > 1,
                  isFresh(frame.timestamp, at: now),
                  gate.lastFire.map({ now - $0 >= 0.25 }) ?? true,
                  gate.lastFrameTimestamp.map({ frame.timestamp > $0 }) ?? true else { return nil }
            gate.lastFire = now
            gate.lastFrameTimestamp = frame.timestamp
            gate.busy = true
            return CapturedFrame(
                frame: frame, id: UUID(), generation: gate.generation,
                viewSize: gate.viewSize, orientation: gate.orientation
            )
        }
        guard let captured else { return }
        worker.async { [self, captured] in
            autoreleasepool { process(captured) }
        }
    }

    private func process(_ captured: CapturedFrame) {
        defer { gate.withLock { $0.busy = false } }
        guard isCurrent(captured) else { return }
        let startedAt = CACurrentMediaTime()
        let frame = captured.frame
        let visionOrientation = Self.visionOrientation(for: captured.orientation)
        let transform = frame.displayTransform(for: captured.orientation, viewportSize: captured.viewSize)
        var packet = EquipmentScanFrame(
            detections: [],
            visionOrientation: visionOrientation,
            imageSize: CGSize(
                width: CVPixelBufferGetWidth(frame.capturedImage),
                height: CVPixelBufferGetHeight(frame.capturedImage)
            ),
            viewSize: captured.viewSize,
            intrinsics: frame.camera.intrinsics,
            cameraTransform: frame.camera.transform,
            displayA: transform.a,
            displayB: transform.b,
            displayC: transform.c,
            displayD: transform.d,
            displayTX: transform.tx,
            displayTY: transform.ty,
            // Image, depth and pose all belong to the retained frame, never session.currentFrame.
            depth: EquipmentPixelBuffer.depthSample(from: frame.smoothedSceneDepth ?? frame.sceneDepth)
        )
        let result: EquipmentDetectionResult
        if let pixels = EquipmentPixelBuffer.copy(frame.capturedImage) {
            guard isCurrent(captured) else { return }
            result = detector.detectResult(in: pixels, orientation: visionOrientation)
        } else {
            result = EquipmentDetectionResult(
                detections: [], status: .frameUnavailable, errorMessage: "Camera frame could not be copied."
            )
        }
        let completedAt = CACurrentMediaTime()
        let observation = EquipmentScanObservation(
            id: captured.id, generation: captured.generation,
            capturedAt: frame.timestamp, completedAt: completedAt,
            processingDuration: completedAt - startedAt,
            status: result.status, errorMessage: result.errorMessage
        )
        packet.detections = result.detections
        packet.observation = observation
        let finished = packet
        gate.withLock {
            guard $0.enabled, $0.trackingNormal, $0.generation == captured.generation,
                  isFresh(frame.timestamp, at: CACurrentMediaTime()) else { return }
            $0.latestObservation = observation
            // Failures replace prior status and remove prior detections; they are never
            // delivered as a confident empty scan. UI reads latestObservation separately.
            $0.latestPacket = result.status.isSuccessfulInference ? finished : nil
        }
    }

    private func isCurrent(_ captured: CapturedFrame) -> Bool {
        gate.withLock {
            $0.enabled && $0.trackingNormal && $0.generation == captured.generation
                && isFresh(captured.frame.timestamp, at: CACurrentMediaTime())
        }
    }

    private func isFresh(_ capturedAt: TimeInterval, at now: TimeInterval) -> Bool {
        // ARFrame.timestamp and CACurrentMediaTime share the monotonic uptime timebase.
        capturedAt.isFinite && now.isFinite && capturedAt <= now && now - capturedAt <= maximumObservationAge
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
        CVBufferPropagateAttachments(source, destination)
        return destination
    }

    static func depthSample(from depth: ARDepthData?) -> DepthSample? {
        guard let depth else { return nil }
        let map = depth.depthMap
        guard CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferLockBaseAddress(map, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        guard width > 0, height > 0, width <= Int.max / height,
              width <= rowBytes / MemoryLayout<Float>.stride else { return nil }
        var meters = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            let source = base.advanced(by: row * rowBytes).assumingMemoryBound(to: Float.self)
            for column in 0..<width {
                meters[row * width + column] = source[column]
            }
        }
        return DepthSample(
            width: width, height: height, meters: meters,
            confidence: confidenceValues(depth.confidenceMap, width: width, height: height)
        )
    }

    private static func confidenceValues(_ map: CVPixelBuffer?, width: Int, height: Int) -> [UInt8]? {
        guard let map,
              CVPixelBufferGetWidth(map) == width, CVPixelBufferGetHeight(map) == height,
              CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_OneComponent8,
              CVPixelBufferLockBaseAddress(map, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        guard rowBytes >= width else { return nil }
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
        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else { return false }
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
        }
        let planes = CVPixelBufferGetPlaneCount(source)
        guard planes == CVPixelBufferGetPlaneCount(destination) else { return false }
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
