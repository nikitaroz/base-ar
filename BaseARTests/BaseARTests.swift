import CoreGraphics
import simd
import XCTest
@testable import BaseAR

final class BaseARTests: XCTestCase {
    func testAppModuleLoads() {
        XCTAssertTrue(true)
    }
}

// MARK: - Label reads (the capture gate's OCR rules)

/// The strict label rules, from the prototype in the scratchpad (`ocr/t/main.swift`). The REAL cases are Vision's own
/// lines (.accurate, no language correction) on the 22:31 demo-wall run's photos and keyframes and the earlier partial
/// run, dumped once so the test needs no image files.
final class ScanTextParserTests: XCTestCase {
    private var failures: [String] = []

    private func expectPanel(_ name: String, _ lines: [ScanTextLine], box: Bool, amps: Int?, evidence: Bool) {
        let read = ScanTextParser.panelRead(in: lines, detectorPanelBox: box)
        let ok = read?.amps == amps && (read?.isPanelEvidence ?? false) == evidence
        if !ok {
            failures.append("panel \(name): amps=\(read?.amps.map(String.init) ?? "nil") evidence=\(read?.isPanelEvidence ?? false)")
        }
    }

    private func expectMeter(_ name: String, _ lines: [ScanTextLine], _ want: String?) {
        let got = ScanTextParser.meterNumber(in: lines)?.number
        if got != want { failures.append("meter \(name): \(got ?? "nil")") }
    }

    /// (text, midX, midY, height); width from the text length.
    private func L(_ text: String, _ x: CGFloat, _ y: CGFloat, _ h: CGFloat = 0.03) -> ScanTextLine {
        let width = CGFloat(text.count) * h * 0.55
        return ScanTextLine(text: text, box: CGRect(x: x - width / 2, y: y - h / 2, width: width, height: h), confidence: 1)
    }

    func testStrictLabelRules() {
        expectPanel("REAL 22:31 panel.jpg (Maximum per stab | 125A)", RealLines.run2231Panel, box: true, amps: nil, evidence: true)
        expectPanel("REAL earlier panel.jpg", RealLines.earlierPanel, box: true, amps: nil, evidence: true)
        expectPanel("REAL keyframe 0 (door open, whole label, FL-PC 12125)", RealLines.keyframe0, box: true, amps: nil, evidence: true)
        expectPanel("REAL keyframe 2 (door shut, 'Electrical Panel')", RealLines.keyframe2, box: true, amps: nil, evidence: true)
        expectPanel("REAL meter.jpg read as a panel (CL.200)", RealLines.run2231Meter, box: true, amps: nil, evidence: false)
        expectPanel("MAIN over 200 (stacked)", [L("MAIN", 0.5, 0.60), L("200", 0.5, 0.55, 0.035)], box: true, amps: 200, evidence: true)
        expectPanel("200 AMP MAIN BREAKER", [L("200 AMP MAIN BREAKER", 0.5, 0.5)], box: false, amps: 200, evidence: true)
        expectPanel("MAIN BREAKER | 150A (two cells)", [L("MAIN BREAKER", 0.35, 0.5), L("150A", 0.7, 0.5)], box: false, amps: 150, evidence: true)
        expectPanel("SERVICE DISCONNECT 100A", [L("SERVICE DISCONNECT 100A", 0.5, 0.5)], box: false, amps: 100, evidence: true)
        expectPanel("MAIN 200A 22kAIC (AIC on the row)", [L("MAIN 200A 22kAIC", 0.5, 0.5)], box: false, amps: nil, evidence: true)
        expectPanel("Maximum per stab | 125A", [L("Maximum per stab", 0.35, 0.64), L("125A", 0.72, 0.65)], box: true, amps: nil, evidence: true)
        expectPanel("MAX 225A", [L("MAX 225A", 0.5, 0.5)], box: true, amps: nil, evidence: false)
        expectPanel("BUS RATING 225A", [L("BUS RATING 225A", 0.5, 0.5)], box: true, amps: nil, evidence: true)
        expectPanel("MAIN LUGS ONLY 200A", [L("MAIN LUGS ONLY 200A", 0.5, 0.5)], box: true, amps: nil, evidence: true)
        expectPanel("MLO | 125A", [L("MLO", 0.3, 0.5), L("125A", 0.6, 0.5)], box: true, amps: nil, evidence: true)
        expectPanel("MAIN BREAKER 100-225A MAX", [L("MAIN BREAKER 100-225A MAX", 0.5, 0.5)], box: false, amps: nil, evidence: true)
        expectPanel("120/240V 1PH 3W 200A", [L("120/240V 1PH 3W 200A", 0.5, 0.5)], box: true, amps: nil, evidence: false)
        expectPanel("Load center 200A", [L("Load center 200A", 0.5, 0.5)], box: true, amps: nil, evidence: true)
        expectPanel("Torque 50 in-lbs / #4 AWG", [L("#4 AWG", 0.3, 0.5), L("50in-Ibs", 0.6, 0.5), L("Torque", 0.5, 0.6)], box: true, amps: nil, evidence: true)
        expectPanel("Maintain 36 in clearance | 200A", [L("Maintain clearance", 0.3, 0.5), L("200A", 0.7, 0.5)], box: false, amps: nil, evidence: false)
        expectPanel("MAIN 200 and MAIN 100 (two mains)", [L("MAIN 200A", 0.3, 0.6), L("MAIN 100A", 0.3, 0.3)], box: false, amps: nil, evidence: true)
        expectPanel("CL200 meter label as panel", [L("CL200 240V 3W", 0.5, 0.5)], box: true, amps: nil, evidence: false)
        expectPanel("60A AC disconnect", [L("AC DISCONNECT", 0.5, 0.6), L("60A", 0.5, 0.5), L("240 VAC", 0.5, 0.4)], box: true, amps: nil, evidence: false)
        expectPanel("MAIN 60A (sub-100 main -> Review asks)", [L("MAIN 60A", 0.5, 0.5)], box: false, amps: nil, evidence: true)
        expectPanel("demo-wall Disconnect box", [L("Disconnect", 0.5, 0.6, 0.05), L("60A", 0.5, 0.5)], box: true, amps: nil, evidence: false)
        expectPanel("REAL keyframe 4 (Electrical Panel + Discon box edge)", RealLines.keyframe4, box: true, amps: nil, evidence: false)
        let face = [L("20", 0.3, 0.7), L("20", 0.3, 0.62), L("15", 0.7, 0.7), L("30", 0.7, 0.62), L("200", 0.5, 0.85, 0.045)]
        // Owner, 27 Sep: amps only beside MAIN. The largest-handle path is off, so this face reads no amps.
        expectPanel("breaker face: 200 on biggest handle + branch 20/20/15/30", face, box: true, amps: nil, evidence: true)
        expectPanel("same face, text-first (no detector box)", face, box: false, amps: nil, evidence: true)
        expectPanel("breaker face, 200 no taller than branches", [L("20", 0.3, 0.7), L("20", 0.3, 0.62), L("200", 0.5, 0.85)], box: true, amps: nil, evidence: false)
        expectPanel("lone 125A (no branch handles)", [L("125A", 0.5, 0.5, 0.05)], box: true, amps: nil, evidence: false)
        expectPanel("face with 225 on biggest handle", [L("20", 0.3, 0.7), L("20", 0.3, 0.62), L("225", 0.5, 0.85, 0.05)], box: true, amps: nil, evidence: false)
        expectMeter("REAL 22:31 meter.jpg (sertal | 71656933, CL.200, TYPE C1S)", RealLines.run2231Meter, "71656933")
        expectMeter("REAL earlier meter.jpg (Meter, Base only)", RealLines.earlierMeter, nil)
        expectMeter("serial number 71656933", [L("serial number 71656933", 0.5, 0.5)], "71656933")
        expectMeter("kWh register 0012345", [L("kWh 0012345", 0.5, 0.6, 0.06), L("71656933", 0.5, 0.4, 0.015)], "71656933")
        expectMeter("LCD 8888888 test pattern", [L("8888888", 0.5, 0.6, 0.06)], nil)
        expectMeter("CL200 240V 3W / TYPE C1S 30TA 1.0Kh", [L("CL200 240V 3W", 0.3, 0.6), L("TYPE C1S 30TA 1.0Kh", 0.6, 0.6)], nil)
        expectMeter("phone 512-555-1234", [L("Call 512-555-1234", 0.5, 0.5)], nil)
        expectMeter("hyphenated 12-345-678", [L("12-345-678", 0.5, 0.5)], "12345678")
        expectMeter("barcode pair 2812689 1858", [L("2812689 1858", 0.5, 0.5)], "2812689")
        expectMeter("FCC ID 2AB1234567 vs serial", [L("FCC ID: 2AB1234567", 0.5, 0.3, 0.02), L("S/N", 0.3, 0.5, 0.015), L("45817263", 0.55, 0.5, 0.015)], "45817263")
        expectMeter("utility asset no. taller than serial", [L("123456789", 0.5, 0.7, 0.04), L("SERIAL 7165693", 0.5, 0.3, 0.012)], "7165693")
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    /// The 22:31 run stored the stab rating (125) as the main breaker. Neither its panel photo nor keyframe 0 gives amps,
    /// and both still count as the panel.
    func testDemoPanelGivesNoAmps() {
        for lines in [RealLines.run2231Panel, RealLines.earlierPanel, RealLines.keyframe0] {
            let read = ScanTextParser.panelRead(in: lines, detectorPanelBox: true)
            XCTAssertNil(read?.amps)
            XCTAssertEqual(read?.isPanelEvidence, true)
            XCTAssertEqual(read?.labelMode, true)
        }
        XCTAssertNil(ScanTextParser.mainBreakerAmps(inLines: RealLines.run2231Panel.map(\.text)))
    }

    func testMainWordIsWholeWord() {
        XCTAssertNil(ScanTextParser.mainBreakerAmps(inLines: ["Maintain 36 in clearance 200A"]))
        XCTAssertEqual(ScanTextParser.mainBreakerAmps(inLines: ["MAIN", "200"]), 200)
    }

    func testLargestHandlePathIsOff() {
        XCTAssertFalse(ScanTextParser.largestHandleEnabled)
    }
}

/// Vision's lines on the real photos. Boxes are Vision-normalized (origin lower left) in each image.
enum RealLines {
    private static func line(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Float) -> ScanTextLine {
        ScanTextLine(text: text, box: CGRect(x: x, y: y, width: w, height: h), confidence: c)
    }

    /// Vision (.accurate, no language correction) on runs/2B631824-AAE6-4E18-8662-04EE5DC7A96A/panel.jpg
    static let run2231Panel: [ScanTextLine] = [
        line("This panel must be installed in", 0.1781, 0.7803, 0.6027, 0.0393, 1.00),
        line("accordance with local electrical", 0.1685, 0.7470, 0.6265, 0.0373, 1.00),
        line("codes", 0.4151, 0.7139, 0.1286, 0.0312, 1.00),
        line("Maximum per stab", 0.1781, 0.6262, 0.3516, 0.0361, 1.00),
        line("125A", 0.6620, 0.6359, 0.1052, 0.0331, 1.00),
        line("Tighten all connections before", 0.1772, 0.5430, 0.5771, 0.0483, 1.00),
        line("energizing", 0.1779, 0.5110, 0.2057, 0.0305, 1.00),
        line("Torque recommendations", 0.1963, 0.4426, 0.4886, 0.0328, 1.00),
        line("#14-10 AWG", 0.2009, 0.4098, 0.2420, 0.0262, 1.00),
        line("20in-Ibs", 0.5250, 0.4093, 0.1601, 0.0272, 1.00),
        line("#8 AWG", 0.2009, 0.3705, 0.1689, 0.0295, 1.00),
        line("35in-Ibs", 0.5251, 0.3704, 0.1553, 0.0297, 1.00),
        line("#4 - 16 AWG", 0.2009, 0.3311, 0.2557, 0.0295, 1.00),
        line("40in-|bs", 0.5204, 0.3306, 0.1647, 0.0305, 1.00),
        line("#3or greater", 0.2007, 0.2844, 0.2425, 0.0378, 1.00),
        line("50in-[bs", 0.5205, 0.2917, 0.1645, 0.0298, 1.00),
        line("N", 0.2420, 0.2262, 0.0548, 0.0492, 1.00),
        line("A B", 0.4292, 0.2262, 0.1689, 0.0492, 1.00),
    ]
    /// Vision (.accurate, no language correction) on runs/C5BD9DED-9CAF-4AE1-B059-B253F36807A9/panel.jpg
    static let earlierPanel: [ScanTextLine] = [
        line("This panel must be installed in", 0.2056, 0.8023, 0.6168, 0.0311, 1.00),
        line("accordance with local electrical", 0.2009, 0.7712, 0.6402, 0.0282, 1.00),
        line("codes", 0.4672, 0.7371, 0.1263, 0.0257, 1.00),
        line("Maximum per stab", 0.2150, 0.6554, 0.3692, 0.0339, 1.00),
        line("125A", 0.7150, 0.6667, 0.1028, 0.0254, 1.00),
        line("Tighten all connections before", 0.2263, 0.5710, 0.5842, 0.0559, 1.00),
        line("energizing", 0.2285, 0.5410, 0.2159, 0.0311, 1.00),
        line("Torque recommendations", 0.2544, 0.4762, 0.4956, 0.0506, 1.00),
        line("#14-10 AWG", 0.2539, 0.4402, 0.2588, 0.0414, 1.00),
        line("20in-Ibs", 0.5935, 0.4576, 0.1542, 0.0282, 1.00),
        line("#8 AWG", 0.2579, 0.4055, 0.1801, 0.0387, 1.00),
        line("35in-Ibs", 0.5935, 0.4237, 0.1542, 0.0282, 1.00),
        line("#4 - #6 AWG", 0.2585, 0.3713, 0.2728, 0.0412, 1.00),
        line("40in-lbs", 0.5935, 0.3898, 0.1542, 0.0282, 1.00),
        line("50in-lbs", 0.5914, 0.3549, 0.1583, 0.0309, 1.00),
        line("#3or greater", 0.2664, 0.3362, 0.2477, 0.0339, 1.00),
        line("N", 0.3084, 0.2797, 0.0607, 0.0424, 1.00),
        line("A B", 0.5327, 0.2938, 0.1402, 0.0452, 1.00),
    ]
    /// Vision (.accurate, no language correction) on runs/2B631824-AAE6-4E18-8662-04EE5DC7A96A/capture/frames/000000.jpg
    static let keyframe0: [ScanTextLine] = [
        line("This panel must be installed in", 0.4009, 0.7915, 0.2021, 0.0160, 1.00),
        line("accordance with local electrical", 0.3950, 0.7789, 0.2138, 0.0163, 1.00),
        line("codes", 0.4806, 0.7689, 0.0426, 0.0102, 1.00),
        line("Maximum per stab", 0.4012, 0.7396, 0.1163, 0.0120, 1.00),
        line("125A", 0.5601, 0.7413, 0.0388, 0.0116, 1.00),
        line("Tighten all connections before", 0.4009, 0.7089, 0.1944, 0.0167, 1.00),
        line("energizing", 0.4011, 0.6961, 0.0698, 0.0132, 1.00),
        line("Torque recommendations", 0.4109, 0.6729, 0.1609, 0.0117, 1.00),
        line("#14-10 AWG", 0.4089, 0.6598, 0.0814, 0.0118, 1.00),
        line("20in-Ibs", 0.5155, 0.6613, 0.0562, 0.0103, 1.00),
        line("#8 AWG", 0.4088, 0.6466, 0.0583, 0.0121, 1.00),
        line("35in-lbs", 0.5155, 0.6467, 0.0563, 0.0118, 1.00),
        line("#4- #6 AWG", 0.4128, 0.6352, 0.0833, 0.0087, 1.00),
        line("40in-Ibs", 0.5154, 0.6335, 0.0564, 0.0121, 1.00),
        line("#3or greater", 0.4127, 0.6189, 0.0777, 0.0122, 1.00),
        line("50in-Ibs", 0.5194, 0.6221, 0.0523, 0.0087, 1.00),
        line("N", 0.4244, 0.5974, 0.0174, 0.0160, 1.00),
        line("A", 0.4961, 0.5974, 0.0329, 0.0160, 1.00),
        line("B", 0.5252, 0.5974, 0.0174, 0.0160, 1.00),
        line("FL-PC 12125", 0.4457, 0.4186, 0.1260, 0.0147, 1.00),
        line("TYE", 0.4612, 0.3663, 0.0911, 0.0334, 1.00),
    ]
    /// Vision (.accurate, no language correction) on runs/2B631824-AAE6-4E18-8662-04EE5DC7A96A/capture/frames/000002.jpg
    static let keyframe2: [ScanTextLine] = [
        line("Electrical", 0.1318, 0.6541, 0.2597, 0.0422, 1.00),
        line("\" Panel", 0.1066, 0.6047, 0.2306, 0.0407, 1.00),
    ]
    /// Vision (.accurate, no language correction) on runs/2B631824-AAE6-4E18-8662-04EE5DC7A96A/capture/frames/000004.jpg
    static let keyframe4: [ScanTextLine] = [
        line("or", 0.0000, 0.6541, 0.0310, 0.0218, 1.00),
        line("Eloctrical", 0.4028, 0.6619, 0.1381, 0.0267, 1.00),
        line("Panel", 0.4283, 0.6366, 0.0872, 0.0276, 1.00),
        line("Discon", 0.8957, 0.7143, 0.0983, 0.0281, 1.00),
        line("\"Disc", 0.9167, 0.6904, 0.0775, 0.0262, 1.00),
    ]
    /// Vision (.accurate, no language correction) on runs/2B631824-AAE6-4E18-8662-04EE5DC7A96A/meter.jpg
    static let run2231Meter: [ScanTextLine] = [
        line("Meter", 0.2672, 0.8724, 0.4506, 0.1085, 1.00),
        line("CL.200 24DV 3W", 0.2410, 0.5556, 0.1054, 0.0105, 1.00),
        line("TУРE C18 З0TA 1.00", 0.3886, 0.5493, 0.1506, 0.0126, 1.00),
        line("sertal", 0.2500, 0.5136, 0.0542, 0.0105, 1.00),
        line("71656933", 0.3765, 0.5073, 0.0964, 0.0147, 1.00),
        line("Base", 0.2892, 0.4256, 0.2801, 0.0881, 1.00),
    ]
    /// Vision (.accurate, no language correction) on runs/C5BD9DED-9CAF-4AE1-B059-B253F36807A9/meter.jpg
    static let earlierMeter: [ScanTextLine] = [
        line("Meter", 0.3172, 0.7304, 0.2957, 0.0826, 1.00),
        line("Base", 0.3277, 0.3908, 0.1779, 0.0618, 1.00),
    ]
}

// MARK: - Demo wall geometry

/// A synthetic copy of Base's demo wall, rebuilt from the 22:31 run's recovered geometry (lock normals and offsets,
/// the floor, the wood wall on the corner side, the facade's ends). That run's scene.ply has no mesh faces, so these
/// checks cannot replay its real faces; they rebuild the wall from the numbers the forensics recovered.
private struct DemoWall {
    let up = SIMD3<Float>(0, 1, 0)
    /// The facade's outward normal.
    let outward = simd_normalize(SIMD3<Float>(0.841, 0, 0.541))
    /// Along the facade, toward the panel. The corner (and the wood wall) is the other way.
    var along: SIMD3<Float> { simd_normalize(simd_cross(up, outward)) }
    let floorY: Float = -1.385
    /// The siding under the meter.
    let siding = SIMD3<Float>(0, 0.17, 0)
    var meterLock: SIMD3<Float> { siding + outward * 0.115 }
    let meterNormal = SIMD3<Float>(0.854, -0.031, 0.519)
    /// The panel sits 1.2 m along on the panel side; its lock landed 0.058 m off the meter's plane, on a door-tilted patch.
    var panelLock: SIMD3<Float> { siding + along * 1.2 + outward * (0.115 + 0.058) + up * 0.1 }
    let panelNormal = SIMD3<Float>(0.995, 0.008, -0.097)

    func wallFace(_ a: Float, _ height: Float, out: Float = 0) -> ClassifiedMeshSample {
        let point = siding + along * a + outward * out
        return ClassifiedMeshSample(faceClass: .wall, point: SIMD3(point.x, floorY + height, point.z), normal: outward)
    }

    /// Facade from 0.44 m past the meter on the corner side to 4.5 m on the panel side, floor to 2.3 m; the meter
    /// glass out to 0.2 m; the wood wall 0.374–0.424 m toward the corner, 0.94 m out; turf in front.
    var mesh: [ClassifiedMeshSample] {
        var faces: [ClassifiedMeshSample] = []
        for a in stride(from: Float(-0.44), through: 4.5, by: 0.05) {
            for h in stride(from: Float(0.05), through: 2.3, by: 0.1) { faces.append(wallFace(a, h)) }
        }
        for a in stride(from: Float(-0.12), through: 0.12, by: 0.04) {
            for dh in stride(from: Float(-0.15), through: 0.15, by: 0.05) {
                faces.append(wallFace(a, meterLock.y - floorY + dh, out: 0.2))
            }
        }
        for a in [Float(-0.374), -0.424] {
            for out in stride(from: Float(0.02), through: 0.94, by: 0.06) {
                for h in stride(from: Float(0.05), through: 1.8, by: 0.1) {
                    let point = siding + along * a + outward * out
                    faces.append(ClassifiedMeshSample(faceClass: .wall, point: SIMD3(point.x, floorY + h, point.z), normal: along))
                }
            }
        }
        for a in stride(from: Float(-1.5), through: 4.5, by: 0.1) {
            for out in stride(from: Float(0.05), through: 2.5, by: 0.1) {
                let point = siding + along * a + outward * out
                faces.append(ClassifiedMeshSample(faceClass: .floor, point: SIMD3(point.x, floorY, point.z), normal: up))
            }
        }
        return faces
    }

    var snapshot: PlacementSceneSnapshot {
        var snapshot = PlacementSceneSnapshot()
        snapshot.lidarMeshAvailable = true
        snapshot.meterWallPosition = PlacementAnchor(meterLock)
        snapshot.meterWallNormal = PlacementAnchor(meterNormal)
        snapshot.meterPosition = PlacementAnchor(SIMD3(meterLock.x, floorY, meterLock.z))
        snapshot.panelWallPosition = PlacementAnchor(panelLock)
        snapshot.panelWallNormal = PlacementAnchor(panelNormal)
        snapshot.panelPosition = PlacementAnchor(SIMD3(panelLock.x, floorY, panelLock.z))
        snapshot.classifiedMesh = mesh
        return snapshot
    }
}

final class DemoWallMeasurementTests: XCTestCase {
    private let wall = DemoWall()
    private let measurer = CorePlacementMeasurer()

    /// 5.1: the panel patch is 37° off the siding, but the mesh shows one wall running between the locks.
    func testMeterAndPanelShareTheDemoWall() {
        XCTAssertEqual(measurer.measure(wall.snapshot).meterAndPanelShareWall, true)
    }

    /// A panel on the other wall of a real corner stays a conflict.
    func testRealCornerIsNotOneWall() {
        var snapshot = wall.snapshot
        let corner = wall.siding - wall.along * 0.44 + wall.outward * 0.2
        snapshot.panelWallPosition = PlacementAnchor(corner)
        snapshot.panelWallNormal = PlacementAnchor(-wall.along)
        XCTAssertEqual(measurer.measure(snapshot).meterAndPanelShareWall, false)
    }

    /// Base allows the panel on the far side of the meter's wall (a garage panel behind it).
    func testOppositeSidesOfOneWallPass() {
        var snapshot = wall.snapshot
        snapshot.panelWallPosition = PlacementAnchor(wall.meterLock - wall.outward * 0.25)
        snapshot.panelWallNormal = PlacementAnchor(-wall.meterNormal)
        XCTAssertEqual(measurer.measure(snapshot).meterAndPanelShareWall, true)
    }

    /// 5.7: the ground under the meter comes from the mesh floor in front of it, not the plane hit 8 cm up.
    func testMeterGroundFromMeshFloor() throws {
        let y = try XCTUnwrap(CorePlacementMeasurer.floorMedianY(wall.mesh, near: wall.meterLock, outward: wall.outward))
        XCTAssertEqual(y, wall.floorY, accuracy: 0.005)
        let feet = Double(wall.meterLock.y - y) / 0.3048
        XCTAssertEqual(feet, 5.1, accuracy: 0.05)
        XCTAssertNil(CorePlacementMeasurer.floorMedianY([ClassifiedMeshSample](), near: wall.meterLock, outward: wall.outward))
    }

    /// The panel's door-tilted patch normal snaps to the siding behind it.
    func testPanelNormalSnapsToTheSiding() throws {
        let snapped = try XCTUnwrap(CorePlacementMeasurer.snappedWallNormal(wall.mesh, at: wall.panelLock, patchNormal: wall.panelNormal))
        XCTAssertGreaterThan(simd_dot(snapped.normal, wall.outward), 0.99)
        XCTAssertEqual(snapped.behind, 0.173, accuracy: 0.03)
    }

    private func pad(at a: Float, gap: Float) -> PlacementSceneSnapshot {
        var snapshot = wall.snapshot
        let position = wall.siding + wall.along * a + wall.outward * (BatteryGeometry.depthMeters / 2 + gap)
        snapshot.batteryPosition = PlacementAnchor(SIMD3(position.x, wall.floorY, position.z))
        snapshot.batteryYawRadians = atan2(wall.outward.x, wall.outward.z)
        return snapshot
    }

    /// 5.4: the wall 0.24 m behind the cabinet's back reads about 0.8 ft; with no wall behind it there is no reading.
    func testWallDistanceNeedsAWallBehind() throws {
        let feet = try XCTUnwrap(measurer.measure(pad(at: 2.0, gap: 0.24)).distanceToWallFeet)
        XCTAssertEqual(feet, 0.24 / 0.3048, accuracy: 0.1)
        var open = pad(at: 2.0, gap: 0.24)
        open.classifiedMesh = open.classifiedMesh.filter { $0.faceClass == .floor }
        XCTAssertNil(measurer.measure(open).distanceToWallFeet)
    }

    /// 5.6: three faces smeared on a pad edge are unknown, never blocked; a real 0.5 m box is blocked.
    func testFootprintNeedsARealObject() {
        let clear = pad(at: 2.0, gap: 0.08)
        XCTAssertEqual(measurer.measure(clear).footprintIsClear, true)
        let center = clear.batteryPosition!.simd
        var smear = clear
        for index in 0..<3 {
            smear.classifiedMesh.append(ClassifiedMeshSample(
                faceClass: .other, point: center + wall.along * (Float(index) * 0.05) + SIMD3(0, 0.12, 0), normal: wall.outward
            ))
        }
        XCTAssertNil(measurer.measure(smear).footprintIsClear)
        var box = clear
        for index in 0..<20 {
            let lift = 0.1 + Float(index % 5) * 0.1
            let side = Float(index / 5) * 0.05
            box.classifiedMesh.append(ClassifiedMeshSample(
                faceClass: .other, point: center + wall.along * side + SIMD3(0, lift, 0), normal: wall.outward
            ))
        }
        XCTAssertEqual(measurer.measure(box).footprintIsClear, false)
    }

    /// 5.8: the pad goes on the panel side. The corner side has no wall under the cabinet.
    func testBatterySpotLandsOnThePanelSide() throws {
        let input = BatterySpotPlanner.Input(
            snapshot: wall.snapshot,
            meterPoint: wall.meterLock,
            outward: wall.outward,
            wallBehindMeters: 0.115,
            groundY: wall.floorY,
            final: true
        )
        let plan = BatterySpotPlanner.plan(input)
        let winner = try XCTUnwrap(plan.winner, "\(plan.candidates.map { "\($0.offsetMeters): \($0.verdict)" })")
        XCTAssertEqual(plan.status, .placed)
        XCTAssertEqual(plan.summary.towardPanel, true)
        XCTAssertGreaterThan(winner.offsetMeters * (plan.panelAlongMeters ?? 0), 0)
        let cornerSide = plan.candidates.filter { $0.offsetMeters * (plan.panelAlongMeters ?? 0) < 0 }
        XCTAssertFalse(cornerSide.isEmpty)
        // The scanned stretch past the corner is "wall ends"; farther out, where the fixture has no turf, "not scanned".
        let out: [BatterySpotPlanner.Verdict] = [.rejected(BatterySpotPlanner.wallEnds), .rejected(BatterySpotPlanner.notScanned)]
        XCTAssertTrue(cornerSide.allSatisfy { out.contains($0.verdict) }, "\(cornerSide.map(\.verdict))")
        let nearest = try XCTUnwrap(cornerSide.min { abs($0.offsetMeters) < abs($1.offsetMeters) })
        XCTAssertEqual(nearest.verdict, .rejected(BatterySpotPlanner.wallEnds))
    }
}
