import AVFoundation
import SwiftUI
import UIKit
import VisionKit

enum LabelScanTarget: String, Identifiable {
    case meterNumber
    case breakerAmperage

    var id: String { rawValue }

    var instruction: String {
        switch self {
        case .meterNumber:
            "Center the meter number in the frame. Pinch to zoom if it is small."
        case .breakerAmperage:
            "Center the main breaker rating in the frame. Pinch to zoom if it is small."
        }
    }

    fileprivate func read(from transcripts: [String]) -> LabelScanRead? {
        switch self {
        case .meterNumber:
            guard let number = ElectricalLabelParser.meterNumber(from: transcripts) else { return nil }
            return LabelScanRead(meterNumber: number, amperage: nil)
        case .breakerAmperage:
            guard let amps = ElectricalLabelParser.mainBreakerAmperage(in: transcripts) else { return nil }
            return LabelScanRead(meterNumber: nil, amperage: amps)
        }
    }
}

struct LabelScanRead: Equatable {
    var meterNumber: String?
    var amperage: Int?

    var display: String {
        if let meterNumber { return meterNumber }
        if let amperage { return "\(amperage) A" }
        return ""
    }
}

/// Live camera scan with a card-shaped window and highlighted text, like adding a payment card.
@MainActor
struct LiveLabelScanner: UIViewControllerRepresentable {
    var target: LabelScanTarget
    var onAccept: (LabelScanRead, UIImage?) -> Void
    var onCancel: () -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported
    }

    /// Nil when the camera is ready to scan. Otherwise a short reason to show in the form.
    static func prepare() async -> String? {
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            allowed = true
        case .notDetermined:
            allowed = await AVCaptureDevice.requestAccess(for: .video)
        default:
            allowed = false
        }
        guard allowed else {
            return "Camera access is off, so live scan is unavailable. You can type the value."
        }
        guard DataScannerViewController.isAvailable else {
            return "Live scan isn't available on this iPhone right now. You can type the value."
        }
        return nil
    }

    func makeUIViewController(context: Context) -> LabelScanController {
        let controller = LabelScanController(target: target)
        controller.onAccept = onAccept
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ controller: LabelScanController, context: Context) {
        controller.onAccept = onAccept
        controller.onCancel = onCancel
    }
}

@MainActor
final class LabelScanController: UIViewController, DataScannerViewControllerDelegate {
    var onAccept: (LabelScanRead, UIImage?) -> Void
    var onCancel: () -> Void

    private let target: LabelScanTarget
    private let scanner: DataScannerViewController
    private let dimView = CardDimView()
    private let instructionLabel = UILabel()
    private let candidateLabel = UILabel()
    private let hintLabel = UILabel()
    private let useButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var cardRect = CGRect.zero
    private var lockedRead: LabelScanRead?
    private var candidateKey: String?
    private var candidateSince: Date?
    private var didFinish = false
    private var didStart = false
    private var didHaptic = false
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    init(target: LabelScanTarget) {
        self.target = target
        self.onAccept = { _, _ in }
        self.onCancel = {}
        scanner = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["en-US"])],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        super.init(nibName: nil, bundle: nil)
        scanner.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        haptic.prepare()

        instructionLabel.text = target.instruction
        instructionLabel.textColor = .white
        instructionLabel.font = .preferredFont(forTextStyle: .subheadline)
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0

        candidateLabel.text = "Looking…"
        candidateLabel.textColor = .white
        candidateLabel.font = .monospacedDigitSystemFont(ofSize: 34, weight: .semibold)
        candidateLabel.textAlignment = .center
        candidateLabel.adjustsFontSizeToFitWidth = true
        candidateLabel.minimumScaleFactor = 0.6

        hintLabel.text = "Hold the number inside the frame."
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        hintLabel.font = .preferredFont(forTextStyle: .footnote)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0

        var useConfig = UIButton.Configuration.filled()
        useConfig.title = "Use this number"
        useConfig.baseBackgroundColor = .white
        useConfig.baseForegroundColor = .black
        useConfig.cornerStyle = .large
        useConfig.buttonSize = .large
        useButton.configuration = useConfig
        useButton.isEnabled = false
        useButton.alpha = 0.45
        useButton.addTarget(self, action: #selector(useTapped), for: .touchUpInside)

        var cancelConfig = UIButton.Configuration.plain()
        cancelConfig.title = "Cancel"
        cancelConfig.baseForegroundColor = .white
        cancelButton.configuration = cancelConfig
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanner.view)
        NSLayoutConstraint.activate([
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        scanner.didMove(toParent: self)

        // Controls sit above the camera. Inside the scanner they lose taps to its gestures.
        for item in [dimView, instructionLabel, candidateLabel, hintLabel, useButton, cancelButton] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }

        NSLayoutConstraint.activate([
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),

            instructionLabel.topAnchor.constraint(equalTo: cancelButton.bottomAnchor, constant: 8),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            useButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            useButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            useButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            hintLabel.bottomAnchor.constraint(equalTo: useButton.topAnchor, constant: -12),

            candidateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            candidateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            candidateLabel.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -4),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = scanner.view.bounds
        let width = min(bounds.width - 40, 420)
        let height = max(96, width * 0.46)
        guard width > 1, height > 1 else { return }
        cardRect = CGRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2 - 36,
            width: width,
            height: height
        )
        scanner.regionOfInterest = cardRect
        dimView.hole = view.convert(cardRect, from: scanner.view)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true
        do {
            try scanner.startScanning()
        } catch {
            hintLabel.text = "Live scan couldn't start. Close this and type the number."
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if scanner.isScanning {
            scanner.stopScanning()
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        consider(allItems)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        consider(allItems)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        consider(allItems)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        guard case .text(let text) = item else { return }
        if let read = target.read(from: [text.transcript]) {
            finish(read)
        } else {
            hintLabel.text = target == .meterNumber
                ? "That highlight isn't a meter number. Aim at the longer number on the nameplate."
                : "That highlight isn't a main breaker rating. Look for 100, 125, 150, 175, 200, or 225."
        }
    }

    func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
        hintLabel.text = "Live scan stopped. Close this and type the number."
    }

    private func consider(_ items: [RecognizedItem]) {
        guard !didFinish else { return }
        let texts = items.compactMap { item -> RecognizedItem.Text? in
            guard case .text(let text) = item else { return nil }
            return text
        }
        let inside = texts.filter { cardRect.contains(center(of: $0.bounds)) }
        let ordered = inside.sorted { $0.bounds.topLeft.x < $1.bounds.topLeft.x }
        guard let read = target.read(from: ordered.map(\.transcript)) else {
            // Losing the label invalidates the old candidate instead of leaving Use enabled.
            lockedRead = nil
            candidateKey = nil
            candidateSince = nil
            didHaptic = false
            useButton.isEnabled = false
            useButton.alpha = 0.45
            candidateLabel.text = "Looking…"
            hintLabel.text = "Keep the printed label inside the frame. Stand still and reduce glare."
            return
        }
        if read == lockedRead { return }
        if read.display != candidateKey {
            candidateKey = read.display
            candidateSince = Date()
            didHaptic = false
            lockedRead = nil
            useButton.isEnabled = false
            useButton.alpha = 0.45
            candidateLabel.text = read.display
            hintLabel.text = "Hold steady…"
            return
        }
        let elapsed = Date().timeIntervalSince(candidateSince ?? Date())
        guard elapsed >= 0.45 else { return }
        lockedRead = read
        candidateLabel.text = read.display
        hintLabel.text = "Tap a highlighted number to pick a different one."
        useButton.isEnabled = true
        useButton.alpha = 1
        if !didHaptic {
            didHaptic = true
            haptic.impactOccurred()
        }
    }

    private func center(of bounds: RecognizedItem.Bounds) -> CGPoint {
        CGPoint(
            x: (bounds.topLeft.x + bounds.topRight.x + bounds.bottomLeft.x + bounds.bottomRight.x) / 4,
            y: (bounds.topLeft.y + bounds.topRight.y + bounds.bottomLeft.y + bounds.bottomRight.y) / 4
        )
    }

    @objc private func useTapped() {
        guard let lockedRead else { return }
        finish(lockedRead)
    }

    @objc private func cancelTapped() {
        guard !didFinish else { return }
        didFinish = true
        onCancel()
    }

    private func finish(_ read: LabelScanRead) {
        guard !didFinish else { return }
        didFinish = true
        useButton.isEnabled = false
        candidateLabel.text = "Saving photo…"
        Task {
            let image = try? await scanner.capturePhoto()
            onAccept(read, image)
        }
    }
}

private final class CardDimView: UIView {
    var hole = CGRect.zero {
        didSet { setNeedsLayout() }
    }

    private let fill = CAShapeLayer()
    private let stroke = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        fill.fillRule = .evenOdd
        fill.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor
        stroke.fillColor = UIColor.clear.cgColor
        stroke.strokeColor = UIColor.white.cgColor
        stroke.lineWidth = 3
        stroke.shadowColor = UIColor.black.cgColor
        stroke.shadowOpacity = 0.45
        stroke.shadowRadius = 2
        layer.addSublayer(fill)
        layer.addSublayer(stroke)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath(rect: bounds)
        let holePath = UIBezierPath(roundedRect: hole, cornerRadius: 18)
        path.append(holePath)
        fill.frame = bounds
        fill.path = path.cgPath
        stroke.frame = bounds
        stroke.path = holePath.cgPath
    }
}
