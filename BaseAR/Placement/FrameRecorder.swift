//  FrameRecorder.swift
//
//  A DEBUG-only frame log for test builds. Each teammate test run leaves labeled camera frames behind: detector
//  tuning data now, and training data for the next EquipmentScan retrain.
//
//  PRIVACY
//  - Only DEBUG builds record. A Release build compiles every call to a no-op.
//  - Frames stay on this device, under Documents/FrameLog. Nothing uploads, syncs, or leaves the app on its own.
//    The folder is excluded from iCloud device backup.
//  - Getting frames off the phone is a deliberate act: in a Debug build, the Files app (On My iPhone > Base Site
//    Survey > FrameLog) or Finder (iPhone > Files > Base Site Survey); in any build,
//    `xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer
//     --domain-identifier <bundle id> --source Documents/FrameLog --destination ./FrameLog`.
//  - Frames can show a house, a street, and people. Treat an exported FrameLog like any site photo.
//
//  SWITCH
//  Off by default, even in DEBUG. The UserDefaults bool "FrameRecorderEnabled" turns it on: the DEBUG-only
//  "Save test frames on this phone" toggle in Review writes it, or use the scheme launch argument
//  `-FrameRecorderEnabled YES`. It is read at `begin`, so a change starts with the next Live Survey.
//  The Files app and Finder see Documents only in Debug builds: the Debug configuration uses BaseAR/Info-Debug.plist
//  (UIFileSharingEnabled, LSSupportsOpeningDocumentsInPlace). Release uses BaseAR/Info.plist, which sets neither.
//
//  API (every call is safe from any thread, and returns quickly)
//
//      FrameRecorder.shared.begin(surveyID: UUID)
//          Opens Documents/FrameLog/<UTC ISO date>-<surveyID>/ and writes session.json (app version, device model,
//          LiDAR yes/no, start time). Calling it again with the survey that is already recording does nothing.
//          After end(), calling it again for that same survey (same app run) continues its folder and numbering.
//          Before a new folder opens, the oldest folders are deleted until everything else fits in 1.1 GB, so the
//          whole log stays under 1.5 GB even when this survey reaches its 400 MB cap.
//
//      FrameRecorder.shared.end(summary: [String: any Sendable] = [:])
//          Stops recording and rewrites session.json with the end time, frame counts by reason, dropped counts,
//          bytes, why recording stopped early (if it did), and `summary`, the caller's final outcome
//          (for example, which locks happened and how).
//
//      FrameRecorder.shared.recordFrame(_ frame: ARFrame, reason: String, metadata: [String: any Sendable],
//                                       interfaceOrientation: UIInterfaceOrientation? = nil) -> Bool
//          Copies frame.capturedImage before it returns, then drops its references to the frame. It never keeps
//          the ARFrame or ARKit's pixel buffer. A background serial queue then turns it upright, downsizes it to a
//          1280 px long edge, and writes <n>.jpg (JPEG quality 0.7) plus <n>.json. The JSON holds the timestamp,
//          reason, tracking state, camera intrinsics and transform, interface orientation, and `metadata`.
//          Pass `interfaceOrientation` when calling off the main thread; otherwise the key window scene is read.
//          Returns false when the frame was not taken (off, throttled, capped, or busy).
//
//      FrameRecorder.shared.recordPixels(_ pixelBuffer: CVPixelBuffer, camera: FrameRecorder.Camera,
//                                        reason: String, metadata: [String: any Sendable]) -> Bool
//          The same, for a detector packet that already holds its own copy of the camera image. The boxes then
//          belong to exactly the image that is saved, not to a later frame. This call copies the buffer too.
//
//      FrameRecorder.detection(label:confidence:visionBox:) and FrameRecorder.box(_:)
//          Turn a Vision rect into {x, y, w, h}, normalized, with the origin at the top left of the saved upright
//          JPEG. YOLO center form is x + w/2, y + h/2, w, h.
//
//  Reasons and throttles (FrameRecorder.Reason):
//      "periodic"                     at most 1 per second, counted from the last frame saved for any reason.
//      "gate-pass", "gate-reject"     unthrottled, but at most 5 in any 1 s window between them.
//      "lock", "capture"              unthrottled, with their own window of 5 per second.
//      Any other string is treated like a gate reason.
//  Hard caps per survey: 2000 frames or 400 MB, whichever comes first. At most 4 frames wait for encoding at once
//  (8 for lock and capture); a frame beyond that is dropped and counted in session.json as "busy".
//
//  Suggested metadata keys (free-form; anything JSON-like works, and NaN and infinity become null):
//      "detections": [FrameRecorder.detection(label:confidence:visionBox:)]
//      "gate": ["sharpness": .., "luma": .., "areaFraction": .., "centered": .., "ocrText": .., "ocrStable": ..]
//      "decision": "lock" | "reject: below lockConfidence" | ...
//      "step": the walk step or lock target
//
//  CALL SITES FOR THE INTEGRATOR (names as of 4e80384; nothing below is wired yet)
//
//  1. Session start and stop — PlacementARView.body
//         .onAppear, after `controller.resume()`:
//             FrameRecorder.shared.begin(surveyID: store.session.id)
//         .onDisappear, after `pauseIfIdle()`:
//             FrameRecorder.shared.end(summary: ["meterLocked": meterMarked, "panelLocked": panelMarked,
//                                                "step": "\(step)"])
//         and SurveyStore.discardSavedSurvey(): FrameRecorder.shared.end(summary: ["discarded": true]).
//     Appear, disappear, appear again in one run keeps one folder per survey.
//
//  2. Each detector packet — EquipmentScanBridge.consider(_:), inside `inference.async`, right after
//     `detector.detectResult(...)`. The copy there is exactly what the model saw:
//         FrameRecorder.shared.recordPixels(copied.buffer,
//             camera: FrameRecorder.Camera(intrinsics: geometry.intrinsics, transform: geometry.cameraTransform,
//                                          imageSize: geometry.imageSize, timestamp: geometry.capturedAt,
//                                          imageOrientation: visionOrientation),   // capturedAt: copy time
//             reason: FrameRecorder.Reason.periodic,
//             metadata: ["status": "\(result.status)",
//                        "detections": result.detections.map { FrameRecorder.detection(
//                            label: $0.kind.rawValue, confidence: $0.confidence, visionBox: $0.boundingBox) }])
//     While `FrameRecorder.shared.isRecording`, also set `packet.pixels = copied` on every packet, not only on
//     packets with a meter box, so call site 3 has the image.
//
//  3. Gate pass or reject — PlacementSceneController.applyScan(_:), where the target's box either reaches
//     lockEquipment or falls out of the guard. Also any capture gate (sharpness, luma, OCR) at its decision point.
//         if let pixels = packet.pixels {
//             FrameRecorder.shared.recordPixels(pixels.buffer,
//                 camera: FrameRecorder.Camera(intrinsics: packet.intrinsics, transform: packet.cameraTransform,
//                                              imageSize: packet.imageSize, timestamp: packet.capturedAt,
//                                              imageOrientation: packet.visionOrientation),
//                 reason: passed ? FrameRecorder.Reason.gatePass : FrameRecorder.Reason.gateReject,
//                 metadata: ["target": target.rawValue, "detections": ..., "gate": [...], "decision": why])
//         }
//
//  4. Lock and capture — PlacementSceneController.lockEquipment(_:at:source:), and wherever a meter photo or
//     AR screenshot is taken from the live session (takeScreenshot, an auto-capture):
//         if let frame = arView.session.currentFrame {
//             FrameRecorder.shared.recordFrame(frame, reason: FrameRecorder.Reason.lock,   // or .capture
//                 metadata: ["kind": kind.rawValue, "source": "\(source)",
//                            "point": sample.point, "normal": sample.normal])
//         }
//     Keep `frame` a local. A stored ARFrame starves ARKit's buffer pool.
//
//  The same image can be saved under two reasons (a periodic packet and then its gate decision). Every JSON has
//  "frameTimestamp", so duplicates can be dropped offline.

import ARKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import ImageIO
import os
import simd
import UIKit

final class FrameRecorder: @unchecked Sendable {
    static let shared = FrameRecorder()
    static let enabledDefaultsKey = "FrameRecorderEnabled"

    enum Reason {
        static let periodic = "periodic"
        static let gatePass = "gate-pass"
        static let gateReject = "gate-reject"
        static let lock = "lock"
        static let capture = "capture"
    }

    /// Pose and image geometry for one saved frame. A value, so nothing from the ARFrame is kept.
    struct Camera: Sendable {
        /// Sensor-pixel intrinsics of the buffer as delivered (landscape sensor orientation).
        var intrinsics: simd_float3x3
        /// Camera to world, ARKit axes.
        var transform: simd_float4x4
        /// Sensor pixel size of the buffer.
        var imageSize: CGSize
        /// ARFrame.timestamp, host uptime seconds (the CACurrentMediaTime clock).
        var timestamp: TimeInterval
        /// Rotation applied to make the saved JPEG upright; the same value Vision was given.
        var imageOrientation: CGImagePropertyOrientation
        var trackingState: String
        var interfaceOrientation: UIInterfaceOrientation?
        var exposureDuration: Double?
        var exposureOffset: Double?
        var ambientIntensity: Double?
        var ambientColorTemperature: Double?
        var hasSceneDepth: Bool?
        var worldMappingStatus: String?

        init(
            intrinsics: simd_float3x3,
            transform: simd_float4x4,
            imageSize: CGSize,
            timestamp: TimeInterval,
            imageOrientation: CGImagePropertyOrientation,
            trackingState: String = "normal",
            interfaceOrientation: UIInterfaceOrientation? = nil
        ) {
            self.intrinsics = intrinsics
            self.transform = transform
            self.imageSize = imageSize
            self.timestamp = timestamp
            self.imageOrientation = imageOrientation
            self.trackingState = trackingState
            self.interfaceOrientation = interfaceOrientation
        }

        init(frame: ARFrame, interfaceOrientation: UIInterfaceOrientation) {
            let camera = frame.camera
            self.init(
                intrinsics: camera.intrinsics,
                transform: camera.transform,
                imageSize: camera.imageResolution,
                timestamp: frame.timestamp,
                imageOrientation: FrameRecorder.imageOrientation(for: interfaceOrientation),
                trackingState: FrameRecorder.describe(camera.trackingState),
                interfaceOrientation: interfaceOrientation
            )
            exposureDuration = camera.exposureDuration
            exposureOffset = Double(camera.exposureOffset)
            ambientIntensity = frame.lightEstimate.map { Double($0.ambientIntensity) }
            ambientColorTemperature = frame.lightEstimate.map { Double($0.ambientColorTemperature) }
            hasSceneDepth = frame.sceneDepth != nil || frame.smoothedSceneDepth != nil
            worldMappingStatus = FrameRecorder.describe(frame.worldMappingStatus)
        }
    }

    // MARK: Limits

    static let longEdge: CGFloat = 1280
    static let jpegQuality: CGFloat = 0.7
    static let periodicInterval: CFTimeInterval = 1.0
    static let burstPerSecond = 5
    static let maxFramesPerSurvey = 2000
    static let maxBytesPerSurvey: Int64 = 400 * 1024 * 1024
    static let maxBytesTotal: Int64 = 1536 * 1024 * 1024
    static let minFreeBytes: Int64 = 1024 * 1024 * 1024
    static let maxInFlight = 4
    static let maxInFlightKeyFrames = 8

    #if DEBUG
    static let isAvailableInBuild = true
    #else
    static let isAvailableInBuild = false
    #endif

    /// DEBUG and switched on in UserDefaults (off on a fresh install). Read by `begin`.
    var isEnabled: Bool {
        guard Self.isAvailableInBuild else { return false }
        return UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool ?? false
    }

    /// A survey is open and no cap has stopped it. Cheap; use it to skip building metadata.
    var isRecording: Bool {
        gate.withLock { $0.active && !$0.stopped }
    }

    // MARK: State

    /// Admission state, read and written on the caller's thread under the lock.
    private struct Gate: Sendable {
        var active = false
        var stopped = false
        var stopReason: String?
        var generation = 0
        var surveyID: UUID?
        var nextIndex = 1
        var lastAccepted: CFTimeInterval = -.infinity
        var burst: [CFTimeInterval] = []
        var keyBurst: [CFTimeInterval] = []
        var inFlight = 0
        var accepted: [String: Int] = [:]
        var throttled = 0
        var busy = 0
        var capped = 0

        var stats: Stats {
            Stats(generation: generation, accepted: accepted, throttled: throttled, busy: busy, capped: capped, stopReason: stopReason)
        }
    }

    private struct Stats: Sendable {
        var generation: Int
        var accepted: [String: Int]
        var throttled: Int
        var busy: Int
        var capped: Int
        var stopReason: String?
    }

    private struct Ticket: Sendable {
        var index: Int
        var generation: Int
        var key: Bool
    }

    private struct Segment {
        var start: Date
        var end: Date?
    }

    private struct Device: Sendable {
        var model: String
        var system: String
        var lidar: Bool
        var sceneDepth: Bool
    }

    /// One survey folder. Only touched on `io`.
    private struct Session {
        var surveyID: UUID
        var folder: URL
        var generation: Int
        var startedAt: Date
        var segments: [Segment]
        var device: Device
        var frames = 0
        var bytes: Int64 = 0
        var summary: [String: any Sendable] = [:]
    }

    /// The copy belongs to one write job and is never written after the copy, so it may cross to `io`.
    private struct OwnedPixels: @unchecked Sendable {
        let buffer: CVPixelBuffer
    }

    private let gate = OSAllocatedUnfairLock(initialState: Gate())
    private let io = DispatchQueue(label: "BaseAR.frame-recorder", qos: .utility, autoreleaseFrequency: .workItem)
    private static let log = Logger(subsystem: "BaseAR", category: "FrameRecorder")
    // Confined to `io`.
    private var session: Session?
    private var context: CIContext?
    private let stampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    // MARK: Session

    func begin(surveyID: UUID) {
        guard isEnabled else { return }
        let current = gate.withLock { ($0.active, $0.surveyID) }
        if current.0 {
            if current.1 == surveyID { return }
            end(summary: ["endedBy": "begin for another survey"])
        }
        let started = Date()
        let (generation, reopen) = gate.withLock { gate -> (Int, Bool) in
            let reopen = gate.surveyID == surveyID
            if !reopen {
                let generation = gate.generation
                gate = Gate()
                gate.generation = generation
                gate.surveyID = surveyID
            }
            gate.generation += 1
            gate.active = true
            return (gate.generation, reopen)
        }
        let device = Device(
            model: Self.deviceModel(),
            system: ProcessInfo.processInfo.operatingSystemVersionString,
            lidar: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
            sceneDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        )
        io.async { [self] in
            if reopen, var current = session, current.surveyID == surveyID {
                current.generation = generation
                current.segments.append(Segment(start: started))
                session = current
                writeSession(current, stats: nil)
                return
            }
            openFolder(surveyID: surveyID, generation: generation, started: started, device: device)
        }
    }

    func end(summary: [String: any Sendable] = [:]) {
        guard Self.isAvailableInBuild else { return }
        let stats: Stats? = gate.withLock { gate in
            guard gate.active else { return nil }
            gate.active = false
            return gate.stats
        }
        guard let stats else { return }
        let ended = Date()
        io.async { [self] in
            guard var current = session, current.generation == stats.generation else { return }
            if !current.segments.isEmpty {
                current.segments[current.segments.count - 1].end = ended
            }
            current.summary.merge(summary) { _, new in new }
            session = current
            writeSession(current, stats: stats)
        }
    }

    // MARK: Recording

    /// True when a frame for `reason` would be taken right now. For skipping expensive metadata; not a promise.
    func wants(_ reason: String) -> Bool {
        let now = CACurrentMediaTime()
        return gate.withLock { gate in
            guard gate.active, !gate.stopped else { return false }
            if reason == Reason.periodic { return now - gate.lastAccepted >= Self.periodicInterval }
            let window = Self.isKey(reason) ? gate.keyBurst : gate.burst
            return window.filter { now - $0 < 1 }.count < Self.burstPerSecond
        }
    }

    @discardableResult
    func recordFrame(
        _ frame: ARFrame,
        reason: String,
        metadata: [String: any Sendable] = [:],
        interfaceOrientation: UIInterfaceOrientation? = nil
    ) -> Bool {
        guard Self.isAvailableInBuild, let ticket = admit(reason) else { return false }
        let camera = Camera(frame: frame, interfaceOrientation: interfaceOrientation ?? Self.currentInterfaceOrientation())
        return submit(frame.capturedImage, camera: camera, reason: reason, metadata: metadata, ticket: ticket)
    }

    @discardableResult
    func recordPixels(
        _ pixelBuffer: CVPixelBuffer,
        camera: Camera,
        reason: String,
        metadata: [String: any Sendable] = [:]
    ) -> Bool {
        guard Self.isAvailableInBuild, let ticket = admit(reason) else { return false }
        return submit(pixelBuffer, camera: camera, reason: reason, metadata: metadata, ticket: ticket)
    }

    /// Vision-normalized rect (origin lower left of the upright image) to {x, y, w, h} with the origin at the top
    /// left of the saved upright JPEG.
    static func box(_ visionRect: CGRect) -> [String: Double] {
        [
            "x": round5(visionRect.minX),
            "y": round5(1 - visionRect.maxY),
            "w": round5(visionRect.width),
            "h": round5(visionRect.height),
        ]
    }

    static func detection(label: String, confidence: Float, visionBox: CGRect) -> [String: any Sendable] {
        ["label": label, "confidence": confidence, "box": box(visionBox)]
    }

    private func admit(_ reason: String) -> Ticket? {
        let now = CACurrentMediaTime()
        let key = Self.isKey(reason)
        return gate.withLock { gate in
            guard gate.active else { return nil }
            guard !gate.stopped else {
                if reason != Reason.periodic { gate.capped += 1 }
                return nil
            }
            if reason == Reason.periodic {
                guard now - gate.lastAccepted >= Self.periodicInterval else { return nil }
            } else if key {
                gate.keyBurst.removeAll { now - $0 >= 1 }
                guard gate.keyBurst.count < Self.burstPerSecond else {
                    gate.throttled += 1
                    return nil
                }
            } else {
                gate.burst.removeAll { now - $0 >= 1 }
                guard gate.burst.count < Self.burstPerSecond else {
                    gate.throttled += 1
                    return nil
                }
            }
            guard gate.inFlight < (key ? Self.maxInFlightKeyFrames : Self.maxInFlight) else {
                gate.busy += 1
                return nil
            }
            guard gate.nextIndex <= Self.maxFramesPerSurvey else {
                gate.stopped = true
                gate.stopReason = "frame cap (\(Self.maxFramesPerSurvey))"
                gate.capped += 1
                return nil
            }
            if key {
                gate.keyBurst.append(now)
            } else if reason != Reason.periodic {
                gate.burst.append(now)
            }
            gate.lastAccepted = now
            gate.inFlight += 1
            gate.accepted[reason, default: 0] += 1
            let ticket = Ticket(index: gate.nextIndex, generation: gate.generation, key: key)
            gate.nextIndex += 1
            return ticket
        }
    }

    private func submit(
        _ source: CVPixelBuffer,
        camera: Camera,
        reason: String,
        metadata: [String: any Sendable],
        ticket: Ticket
    ) -> Bool {
        // The only work done on the caller's thread: one plane-by-plane memcpy. Nothing below keeps `source`.
        guard let copy = Self.copyPixels(source) else {
            gate.withLock { $0.inFlight -= 1 }
            return false
        }
        let pixels = OwnedPixels(buffer: copy)
        let recordedAt = Date()
        io.async { [self] in
            write(pixels, camera: camera, reason: reason, metadata: metadata, ticket: ticket, recordedAt: recordedAt)
            gate.withLock { $0.inFlight -= 1 }
        }
        return true
    }

    // MARK: Disk (on `io`)

    private func openFolder(surveyID: UUID, generation: Int, started: Date, device: Device) {
        let manager = FileManager.default
        do {
            let documents = try manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            var root = documents.appendingPathComponent("FrameLog", isDirectory: true)
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? root.setResourceValues(values)
            prune(root)
            let folder = root.appendingPathComponent("\(Self.folderStamp(started))-\(surveyID.uuidString)", isDirectory: true)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let opened = Session(
                surveyID: surveyID,
                folder: folder,
                generation: generation,
                startedAt: started,
                segments: [Segment(start: started)],
                device: device
            )
            session = opened
            if let free = try? documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage, free < Self.minFreeBytes {
                stop(generation: generation, reason: "low disk (\(free / 1_048_576) MB free)")
            }
            writeSession(opened, stats: nil)
        } catch {
            session = nil
            stop(generation: generation, reason: "could not open folder: \(error.localizedDescription)")
        }
    }

    private func write(
        _ pixels: OwnedPixels,
        camera: Camera,
        reason: String,
        metadata: [String: any Sendable],
        ticket: Ticket,
        recordedAt: Date
    ) {
        guard var current = session, current.generation == ticket.generation else { return }
        guard let (jpeg, savedSize) = encodeJPEG(pixels.buffer, orientation: camera.imageOrientation) else {
            Self.log.debug("frame \(ticket.index) did not encode")
            return
        }
        let name = String(format: "%05d", ticket.index)
        let record = frameRecord(
            index: ticket.index,
            name: name,
            camera: camera,
            reason: reason,
            metadata: metadata,
            savedSize: savedSize,
            recordedAt: recordedAt,
            session: current
        )
        guard let json = Self.jsonData(record) else { return }
        do {
            try jpeg.write(to: current.folder.appendingPathComponent(name + ".jpg"))
            try json.write(to: current.folder.appendingPathComponent(name + ".json"))
        } catch {
            stop(generation: current.generation, reason: "write failed: \(error.localizedDescription)")
            writeSession(current, stats: nil)
            return
        }
        current.frames += 1
        current.bytes += Int64(jpeg.count + json.count)
        session = current
        if current.bytes >= Self.maxBytesPerSurvey {
            stop(generation: current.generation, reason: "size cap (\(Self.maxBytesPerSurvey / 1_048_576) MB)")
            writeSession(current, stats: nil)
        } else if current.frames % 25 == 0 {
            // A crash or a kill mid-scan still leaves counts behind.
            writeSession(current, stats: nil)
        }
    }

    private func stop(generation: Int, reason: String) {
        gate.withLock { gate in
            guard gate.generation == generation, !gate.stopped else { return }
            gate.stopped = true
            gate.stopReason = reason
        }
        Self.log.debug("recording stopped: \(reason, privacy: .public)")
    }

    private func frameRecord(
        index: Int,
        name: String,
        camera: Camera,
        reason: String,
        metadata: [String: any Sendable],
        savedSize: CGSize,
        recordedAt: Date,
        session: Session
    ) -> [String: Any] {
        let k = camera.intrinsics
        let position = camera.transform.columns.3
        var cameraRecord: [String: Any] = [
            "intrinsics": Self.json(k),
            "fx": Self.json(k.columns.0.x), "fy": Self.json(k.columns.1.y),
            "cx": Self.json(k.columns.2.x), "cy": Self.json(k.columns.2.y),
            "transform": Self.json(camera.transform),
            "position": [position.x, position.y, position.z].map { Self.json($0) },
            "matrixLayout": "column-major arrays; intrinsics in sensor pixels; transform is camera to world",
        ]
        cameraRecord["exposureDuration"] = camera.exposureDuration.map { Self.finite($0) }
        cameraRecord["exposureOffset"] = camera.exposureOffset.map { Self.finite($0) }
        cameraRecord["ambientIntensity"] = camera.ambientIntensity.map { Self.finite($0) }
        cameraRecord["ambientColorTemperature"] = camera.ambientColorTemperature.map { Self.finite($0) }
        cameraRecord["sceneDepth"] = camera.hasSceneDepth
        cameraRecord["worldMapping"] = camera.worldMappingStatus
        var record: [String: Any] = [
            "index": index,
            "image": name + ".jpg",
            "surveyID": session.surveyID.uuidString,
            "reason": reason,
            "recordedAt": stampFormatter.string(from: recordedAt),
            "sinceStart": Self.finite(recordedAt.timeIntervalSince(session.startedAt)),
            "frameTimestamp": Self.finite(camera.timestamp),
            "trackingState": camera.trackingState,
            "interfaceOrientation": camera.interfaceOrientation.map { Self.describe($0) as Any } ?? NSNull(),
            "camera": cameraRecord,
            "imageGeometry": [
                "sensorSize": [Double(camera.imageSize.width), Double(camera.imageSize.height)],
                "savedSize": [Double(savedSize.width), Double(savedSize.height)],
                "orientationApplied": Self.describe(camera.imageOrientation),
                "jpegQuality": Double(Self.jpegQuality),
                "boxConvention": "x, y, w, h normalized; origin top left of the saved upright JPEG",
            ] as [String: Any],
            "thermalState": Self.describe(ProcessInfo.processInfo.thermalState),
        ]
        record["metadata"] = Self.json(metadata)
        return record
    }

    private func writeSession(_ open: Session, stats: Stats?) {
        let live = stats ?? gate.withLock { $0.stats }
        let bundle = Bundle.main
        var record: [String: Any] = [
            "surveyID": open.surveyID.uuidString,
            "folder": open.folder.lastPathComponent,
            "startedAt": stampFormatter.string(from: open.startedAt),
            "segments": open.segments.map { segment -> [String: Any] in
                ["start": stampFormatter.string(from: segment.start),
                 "end": segment.end.map { stampFormatter.string(from: $0) as Any } ?? NSNull()]
            },
            "app": [
                "version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
                "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
                "bundleID": bundle.bundleIdentifier ?? "?",
                "configuration": Self.isAvailableInBuild ? "Debug" : "Release",
            ],
            "device": [
                "model": open.device.model,
                "system": open.device.system,
                "lidar": open.device.lidar,
                "sceneDepth": open.device.sceneDepth,
            ] as [String: Any],
            "frames": open.frames,
            "bytes": open.bytes,
            "limits": [
                "longEdge": Double(Self.longEdge),
                "jpegQuality": Double(Self.jpegQuality),
                "periodicPerSecond": 1,
                "burstPerSecond": Self.burstPerSecond,
                "maxFrames": Self.maxFramesPerSurvey,
                "maxBytes": Self.maxBytesPerSurvey,
                "maxBytesAllSurveys": Self.maxBytesTotal,
            ] as [String: Any],
            "privacy": "DEBUG build only. Frames stay on this device until someone exports them through Files or Finder.",
        ]
        let ended = open.segments.last?.end
        record["endedAt"] = ended.map { stampFormatter.string(from: $0) as Any } ?? NSNull()
        if live.generation == open.generation {
            record["reasons"] = live.accepted
            record["dropped"] = ["throttled": live.throttled, "busy": live.busy, "capped": live.capped]
            record["stopReason"] = live.stopReason.map { $0 as Any } ?? NSNull()
        }
        record["summary"] = Self.json(open.summary)
        guard let data = Self.jsonData(record) else { return }
        try? data.write(to: open.folder.appendingPathComponent("session.json"), options: .atomic)
    }

    /// Deletes the oldest survey folders until everything left fits beside one full-size new survey.
    private func prune(_ root: URL) {
        let manager = FileManager.default
        guard let children = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var folders = children
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { ($0, Self.allocatedSize($0)) }
        var total = folders.reduce(Int64(0)) { $0 + $1.1 }
        let budget = Self.maxBytesTotal - Self.maxBytesPerSurvey
        while total > budget, !folders.isEmpty {
            let (oldest, size) = folders.removeFirst()
            try? manager.removeItem(at: oldest)
            total -= size
            Self.log.debug("pruned \(oldest.lastPathComponent, privacy: .public)")
        }
    }

    private static func allocatedSize(_ folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            let values = try? file.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    private func encodeJPEG(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> (Data, CGSize)? {
        let context = self.context ?? CIContext(options: [.cacheIntermediates: false, .priorityRequestLow: true])
        self.context = context
        let upright = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        let source = upright.transformed(by: CGAffineTransform(translationX: -upright.extent.minX, y: -upright.extent.minY))
        let size = source.extent.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, Self.longEdge / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        var output = source
        if scale < 1 {
            let filter = CIFilter.lanczosScaleTransform()
            filter.inputImage = source
            filter.scale = Float(target.height / size.height)
            filter.aspectRatio = Float((target.width / size.width) / (target.height / size.height))
            guard let scaled = filter.outputImage else { return nil }
            output = scaled
        }
        output = output.cropped(to: CGRect(origin: .zero, size: target))
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let data = context.jpegRepresentation(
                of: output,
                colorSpace: sRGB,
                options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): Self.jpegQuality]
              ) else { return nil }
        return (data, target)
    }

    // MARK: Helpers

    private static func isKey(_ reason: String) -> Bool {
        reason == Reason.lock || reason == Reason.capture
    }

    /// A private copy with the same size, format, planes, and color attachments.
    private static func copyPixels(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        var created: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, CVPixelBufferGetPixelFormatType(source), attributes, &created) == kCVReturnSuccess,
              let destination = created else { return nil }
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        let planes = CVPixelBufferGetPlaneCount(source)
        if planes == 0 {
            guard let from = CVPixelBufferGetBaseAddress(source), let to = CVPixelBufferGetBaseAddress(destination) else { return nil }
            copyRows(from: from, to: to, rows: height,
                     fromStride: CVPixelBufferGetBytesPerRow(source), toStride: CVPixelBufferGetBytesPerRow(destination))
        } else {
            for plane in 0..<planes {
                guard let from = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let to = CVPixelBufferGetBaseAddressOfPlane(destination, plane) else { return nil }
                copyRows(from: from, to: to, rows: CVPixelBufferGetHeightOfPlane(source, plane),
                         fromStride: CVPixelBufferGetBytesPerRowOfPlane(source, plane),
                         toStride: CVPixelBufferGetBytesPerRowOfPlane(destination, plane))
            }
        }
        CVBufferPropagateAttachments(source, destination)
        return destination
    }

    private static func copyRows(from: UnsafeMutableRawPointer, to: UnsafeMutableRawPointer, rows: Int, fromStride: Int, toStride: Int) {
        if fromStride == toStride {
            memcpy(to, from, fromStride * rows)
            return
        }
        let rowBytes = min(fromStride, toStride)
        for row in 0..<rows {
            memcpy(to.advanced(by: row * toStride), from.advanced(by: row * fromStride), rowBytes)
        }
    }

    private static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        guard Thread.isMainThread else { return .portrait }
        return MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            return scene?.effectiveGeometry.interfaceOrientation ?? .portrait
        }
    }

    /// The rotation that makes capturedImage upright; matches EquipmentScanBridge's Vision orientation.
    static func imageOrientation(for interface: UIInterfaceOrientation) -> CGImagePropertyOrientation {
        switch interface {
        case .portrait: .right
        case .portraitUpsideDown: .left
        case .landscapeRight: .up
        case .landscapeLeft: .down
        default: .right
        }
    }

    private static func folderStamp(_ date: Date) -> String {
        // ISO 8601 in UTC with hyphens for colons, which Finder shows as slashes. Sorts oldest first.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.string(from: date)
    }

    private static func deviceModel() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated + " (simulator)"
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static func describe(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal: "normal"
        case .notAvailable: "notAvailable"
        case .limited(let reason):
            switch reason {
            case .initializing: "limited: initializing"
            case .excessiveMotion: "limited: excessiveMotion"
            case .insufficientFeatures: "limited: insufficientFeatures"
            case .relocalizing: "limited: relocalizing"
            @unknown default: "limited: unknown"
            }
        }
    }

    private static func describe(_ status: ARFrame.WorldMappingStatus) -> String {
        switch status {
        case .notAvailable: "notAvailable"
        case .limited: "limited"
        case .extending: "extending"
        case .mapped: "mapped"
        @unknown default: "unknown"
        }
    }

    private static func describe(_ orientation: UIInterfaceOrientation) -> String {
        switch orientation {
        case .portrait: "portrait"
        case .portraitUpsideDown: "portraitUpsideDown"
        case .landscapeLeft: "landscapeLeft"
        case .landscapeRight: "landscapeRight"
        default: "unknown"
        }
    }

    private static func describe(_ orientation: CGImagePropertyOrientation) -> String {
        switch orientation {
        case .up: "up"
        case .upMirrored: "upMirrored"
        case .down: "down"
        case .downMirrored: "downMirrored"
        case .left: "left"
        case .leftMirrored: "leftMirrored"
        case .right: "right"
        case .rightMirrored: "rightMirrored"
        @unknown default: "unknown"
        }
    }

    private static func describe(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static func round5(_ value: CGFloat) -> Double {
        let rounded = (Double(value) * 100_000).rounded() / 100_000
        return rounded.isFinite ? rounded : 0
    }

    /// JSONSerialization raises on NaN and infinity; they become null. Finite values go out in their shortest
    /// decimal form (0.4, not 0.40000000000000002).
    private static func finite(_ value: Double) -> Any {
        value.isFinite ? decimal(String(value), fallback: value) : NSNull()
    }

    private static func decimal(_ text: String, fallback: Double) -> Any {
        let number = NSDecimalNumber(string: text, locale: Locale(identifier: "en_US_POSIX"))
        return number == NSDecimalNumber.notANumber ? fallback : number
    }

    private static func jsonData(_ object: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else {
            log.debug("record is not valid JSON")
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Turns caller metadata into JSON-safe values. Unknown types fall back to their description.
    private static func json(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let wrapped = mirror.children.first?.value else { return NSNull() }
            return json(wrapped)
        }
        switch value {
        case is NSNull: return NSNull()
        case let string as String: return string
        case let bool as Bool: return bool
        case let int as Int: return int
        case let int as Int64: return int
        case let int as Int32: return Int(int)
        case let int as UInt8: return Int(int)
        case let double as Double: return finite(double)
        case let float as Float: return float.isFinite ? decimal(String(float), fallback: Double(float)) : NSNull()
        case let cg as CGFloat: return finite(Double(cg))
        case let date as Date: return ISO8601DateFormatter().string(from: date)
        case let uuid as UUID: return uuid.uuidString
        case let url as URL: return url.absoluteString
        case let rect as CGRect: return ["x": finite(rect.minX), "y": finite(rect.minY), "w": finite(rect.width), "h": finite(rect.height)]
        case let point as CGPoint: return ["x": finite(point.x), "y": finite(point.y)]
        case let size as CGSize: return ["w": finite(size.width), "h": finite(size.height)]
        case let v as SIMD2<Float>: return [v.x, v.y].map { json($0) }
        case let v as SIMD3<Float>: return [v.x, v.y, v.z].map { json($0) }
        case let v as SIMD4<Float>: return [v.x, v.y, v.z, v.w].map { json($0) }
        case let m as simd_float3x3: return [m.columns.0, m.columns.1, m.columns.2].map { json($0) }
        case let m as simd_float4x4: return [m.columns.0, m.columns.1, m.columns.2, m.columns.3].map { json($0) }
        case let dictionary as [String: Any]: return dictionary.mapValues { json($0) }
        case let dictionary as [AnyHashable: Any]:
            var converted: [String: Any] = [:]
            for (key, element) in dictionary {
                let name = (key.base as? any RawRepresentable).map { "\($0.rawValue)" } ?? "\(key.base)"
                converted[name] = json(element)
            }
            return converted
        case let array as [Any]: return array.map { json($0) }
        case let raw as any RawRepresentable: return json(raw.rawValue)
        default: return String(describing: value)
        }
    }

    private static func finite(_ value: CGFloat) -> Any {
        finite(Double(value))
    }
}
