import ARKit
import CoreImage
import os

/// Posed camera frames saved during the site scan, so a reviewer can see what each part of `scene.ply` looked like.
/// Adaptive: a frame is kept only from a new viewpoint (moved or turned since every earlier keyframe) and only
/// while the phone is steady enough not to blur. Poses and depth share the AR world coordinates of `scene.ply`.
final class KeyframeRecorder: Sendable {
    static let maxFrames = 120
    private static let minInterval: TimeInterval = 0.3
    private static let minMoveMeters: Float = 0.4
    private static let minTurnRadians: Float = 20 * .pi / 180
    private static let maxAngularSpeed: Float = 1.2
    private static let maxLinearSpeed: Float = 1.0

    struct Frame: Codable, Sendable {
        var index: Int
        var timestamp: TimeInterval
        var image: String
        var depth: String?
        var confidence: String?
        var imageWidth: Int
        var imageHeight: Int
        var depthWidth: Int?
        var depthHeight: Int?
        /// How the phone was held. Pixels, depth, intrinsics, and pose are already turned upright to match.
        var heldAs: Upright
        var exposureDuration: TimeInterval
        /// Column-major 4×4 camera-to-world for the upright image: +X image right, +Y image up, camera looks down -Z.
        var cameraToWorld: [Float]
        /// Column-major 3×3 intrinsics in pixels of the upright image.
        var intrinsics: [Float]
    }

    private struct Manifest: Codable {
        var coordinateSpace = "ARKit world, meters, +Y up. Same space as scene.ply."
        var imageOrientation = "Upright as the phone was held. Pixels are rotated; there is no EXIF orientation. Intrinsics, depth, and cameraToWorld all match the saved image."
        var depthFormat = "Raw little-endian Float32 meters, row-major, depthWidth × depthHeight, same orientation as the image."
        var confidenceFormat = "Raw UInt8 per depth pixel: 0 low, 1 medium, 2 high."
        var frames: [Frame]
    }

    private struct State {
        var enabled = false
        var directory: URL?
        /// Nil while a frame is still being prepared outside the lock.
        var frames: [Frame?] = []
        var lastUpright: Upright = .portrait
        var poses: [simd_float4x4] = []
        var lastAccepted: TimeInterval = 0
        /// Next steady frame is kept even if it is close to an earlier one: the anchor photo for a fresh lock.
        var forceNext = false
        var previous: (transform: simd_float4x4, time: TimeInterval)?
    }

    /// Owned by one encode job, so handing it across queues is safe.
    private struct Pixels: @unchecked Sendable {
        let buffer: CVPixelBuffer
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "BaseAR.keyframes", qos: .utility)
    private let context = CIContext()

    var count: Int { state.withLock { $0.frames.count } }

    func setEnabled(_ enabled: Bool) {
        state.withLock { state in
            state.enabled = enabled
            if !enabled { state.previous = nil }
        }
    }

    /// Keeps the next steady frame regardless of spacing, so each equipment lock gets its own photo.
    func captureNext() {
        state.withLock { $0.forceNext = true }
    }

    /// Working folder, usually `<survey>/capture`. Frames land in its `frames` subfolder.
    func setDirectory(_ url: URL) {
        state.withLock { $0.directory = url }
    }

    func consider(_ frame: ARFrame) {
        guard case .normal = frame.camera.trackingState else {
            state.withLock { $0.previous = nil }
            return
        }
        let transform = frame.camera.transform
        let time = frame.timestamp
        let accepted: (index: Int, upright: Upright, directory: URL)? = state.withLock { state in
            let previous = state.previous
            state.previous = (transform, time)
            guard state.enabled, let directory = state.directory,
                  state.frames.count < Self.maxFrames,
                  state.forceNext || time - state.lastAccepted >= Self.minInterval,
                  let previous, time > previous.time else { return nil }

            let dt = Float(time - previous.time)
            let linear = simd_distance(Self.position(transform), Self.position(previous.transform)) / dt
            let angular = Self.angle(Self.forward(transform), Self.forward(previous.transform)) / dt
            guard linear < Self.maxLinearSpeed, angular < Self.maxAngularSpeed else { return nil }

            let isNew = state.forceNext || state.poses.allSatisfy { pose in
                simd_distance(Self.position(transform), Self.position(pose)) >= Self.minMoveMeters
                    || Self.angle(Self.forward(transform), Self.forward(pose)) >= Self.minTurnRadians
            }
            guard isNew else { return nil }

            let upright = Upright(cameraToWorld: transform) ?? state.lastUpright
            state.lastUpright = upright
            state.poses.append(transform)
            state.lastAccepted = time
            state.forceNext = false
            // Reserve the slot now; the record is filled in below, outside the lock.
            state.frames.append(nil)
            return (state.frames.count - 1, upright, directory)
        }
        guard let accepted else { return }

        // Copy off ARKit's buffer pool before leaving the delegate callback.
        let sensor = frame.capturedImage
        guard let pixels = EquipmentPixelBuffer.copy(sensor).map(Pixels.init) else {
            state.withLock { $0.frames.removeLast() }
            return
        }
        let upright = accepted.upright
        let stem = String(format: "%06d", accepted.index)
        let width = CVPixelBufferGetWidth(sensor)
        let height = CVPixelBufferGetHeight(sensor)
        let size = upright.size(width: width, height: height)
        let rawDepth = EquipmentPixelBuffer.depthSample(from: frame.smoothedSceneDepth ?? frame.sceneDepth)
        let depth = rawDepth.map { sample in
            let meters = upright.rotate(sample.meters, width: sample.width, height: sample.height)
            let confidence = sample.confidence.map { upright.rotate($0, width: sample.width, height: sample.height) }
            let depthSize = upright.size(width: sample.width, height: sample.height)
            return DepthSample(width: depthSize.width, height: depthSize.height, meters: meters, confidence: confidence)
        }
        let pose = transform * upright.cameraRotation
        let intrinsics = upright.intrinsics(frame.camera.intrinsics, width: Float(width), height: Float(height))
        let record = Frame(
            index: accepted.index,
            timestamp: time,
            image: "frames/\(stem).jpg",
            depth: depth == nil ? nil : "frames/\(stem).depth.bin",
            confidence: depth?.confidence == nil ? nil : "frames/\(stem).conf.bin",
            imageWidth: size.width,
            imageHeight: size.height,
            depthWidth: depth?.width,
            depthHeight: depth?.height,
            heldAs: upright,
            exposureDuration: frame.camera.exposureDuration,
            cameraToWorld: [pose.columns.0, pose.columns.1, pose.columns.2, pose.columns.3]
                .flatMap { [$0.x, $0.y, $0.z, $0.w] },
            intrinsics: [intrinsics.columns.0, intrinsics.columns.1, intrinsics.columns.2]
                .flatMap { [$0.x, $0.y, $0.z] }
        )
        state.withLock { state in
            if record.index < state.frames.count { state.frames[record.index] = record }
        }
        let directory = accepted.directory
        queue.async { [context] in
            let frames = directory.appendingPathComponent("frames", isDirectory: true)
            try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
            // Rotate the pixels themselves, not an EXIF tag, so every viewer and the intrinsics agree.
            let ciImage = CIImage(cvPixelBuffer: pixels.buffer).oriented(upright.imageOrientation)
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.8]
            if let jpeg = context.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: options) {
                try? jpeg.write(to: directory.appendingPathComponent(record.image))
            }
            if let depth, let name = record.depth {
                let data = depth.meters.withUnsafeBufferPointer { Data(buffer: $0) }
                try? data.write(to: directory.appendingPathComponent(name))
            }
            if let confidence = depth?.confidence, let name = record.confidence {
                try? Data(confidence).write(to: directory.appendingPathComponent(name))
            }
        }
    }

    /// Waits for pending encodes and writes `frames.json`. Returns the capture folder, or nil when nothing was captured.
    func finalize() throws -> URL? {
        queue.sync {}
        let (frames, directory) = state.withLock { ($0.frames.compactMap { $0 }, $0.directory) }
        guard !frames.isEmpty, let directory else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Manifest(frames: frames)).write(to: directory.appendingPathComponent("frames.json"), options: .atomic)
        return directory
    }

    private static func position(_ transform: simd_float4x4) -> SIMD3<Float> {
        SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }

    private static func forward(_ transform: simd_float4x4) -> SIMD3<Float> {
        -SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
    }

    private static func angle(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        acos(max(-1, min(1, simd_dot(simd_normalize(a), simd_normalize(b)))))
    }
}

/// How the phone was held for one keyframe. ARKit's sensor image is always landscape with the home side on the
/// right; this picks the quarter turn that puts world up at the top of the saved image.
enum Upright: String, Codable, Sendable {
    case landscapeRight
    case portrait
    case landscapeLeft
    case portraitUpsideDown

    /// Nil when the camera points nearly straight up or down and no edge is clearly on top.
    init?(cameraToWorld transform: simd_float4x4) {
        // World up in camera space is the second row of the rotation.
        let x = transform.columns.0.y
        let y = transform.columns.1.y
        guard max(abs(x), abs(y)) > 0.35 else { return nil }
        if abs(y) >= abs(x) {
            self = y > 0 ? .landscapeRight : .portraitUpsideDown
        } else {
            self = x < 0 ? .portrait : .landscapeLeft
        }
    }

    /// `.right` turns the pixels 90° clockwise, `.left` counterclockwise.
    var imageOrientation: CGImagePropertyOrientation {
        switch self {
        case .landscapeRight: .up
        case .portrait: .right
        case .landscapeLeft: .left
        case .portraitUpsideDown: .down
        }
    }

    func size(width: Int, height: Int) -> (width: Int, height: Int) {
        switch self {
        case .landscapeRight, .portraitUpsideDown: (width, height)
        case .portrait, .landscapeLeft: (height, width)
        }
    }

    /// Camera axes of the upright image, expressed in ARKit's sensor camera axes. Right-multiply the camera transform.
    var cameraRotation: simd_float4x4 {
        let (xAxis, yAxis): (SIMD4<Float>, SIMD4<Float>) = switch self {
        case .landscapeRight: (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0))
        case .portrait: (SIMD4(0, 1, 0, 0), SIMD4(-1, 0, 0, 0))
        case .landscapeLeft: (SIMD4(0, -1, 0, 0), SIMD4(1, 0, 0, 0))
        case .portraitUpsideDown: (SIMD4(-1, 0, 0, 0), SIMD4(0, -1, 0, 0))
        }
        return simd_float4x4(xAxis, yAxis, SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1))
    }

    /// Sensor intrinsics re-expressed for the upright image. `width` and `height` are the sensor image size.
    func intrinsics(_ k: simd_float3x3, width: Float, height: Float) -> simd_float3x3 {
        let fx = k.columns.0.x, fy = k.columns.1.y
        let cx = k.columns.2.x, cy = k.columns.2.y
        let (nfx, nfy, ncx, ncy): (Float, Float, Float, Float) = switch self {
        case .landscapeRight: (fx, fy, cx, cy)
        case .portrait: (fy, fx, height - cy, cx)
        case .landscapeLeft: (fy, fx, cy, width - cx)
        case .portraitUpsideDown: (fx, fy, width - cx, height - cy)
        }
        return simd_float3x3(SIMD3(nfx, 0, 0), SIMD3(0, nfy, 0), SIMD3(ncx, ncy, 1))
    }

    /// Turns a row-major raster the same way as the image.
    func rotate<T>(_ values: [T], width: Int, height: Int) -> [T] {
        guard self != .landscapeRight, values.count == width * height else { return values }
        let out = size(width: width, height: height)
        var result = values
        for v in 0..<out.height {
            for u in 0..<out.width {
                let (x, y): (Int, Int) = switch self {
                case .landscapeRight: (u, v)
                case .portrait: (v, height - 1 - u)
                case .landscapeLeft: (width - 1 - v, u)
                case .portraitUpsideDown: (width - 1 - u, height - 1 - v)
                }
                result[v * out.width + u] = values[y * width + x]
            }
        }
        return result
    }
}
