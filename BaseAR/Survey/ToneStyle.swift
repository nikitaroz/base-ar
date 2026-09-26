import SwiftUI
import UIKit

enum ToneStyle {
    static func color(_ tone: PlacementTone) -> Color {
        Color(uiColor: uiColor(tone))
    }

    static func uiColor(_ tone: PlacementTone) -> UIColor {
        switch tone {
        case .clear:
            UIColor.systemGreen
        case .attested:
            UIColor.systemTeal
        case .incomplete:
            UIColor(red: 0.93, green: 0.58, blue: 0.05, alpha: 1)
        case .conflict:
            UIColor.systemRed
        }
    }

    static func title(_ tone: PlacementTone) -> String {
        switch tone {
        case .clear:
            "All required checks passed"
        case .attested:
            "Passed with attestations"
        case .incomplete:
            "Needs measurements"
        case .conflict:
            "Measured conflict"
        }
    }

    static func statusTitle(_ status: CheckStatus) -> String {
        switch status {
        case .pass:
            "Pass"
        case .conflict:
            "Conflict"
        case .unknown:
            "Unknown"
        }
    }
}
