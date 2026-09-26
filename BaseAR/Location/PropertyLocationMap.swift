import MapKit
import SwiftUI

/// Map of the phone's property fix. The circle is reported horizontal accuracy, not the battery position.
struct PropertyLocationMap: View {
    var fix: GeoFix

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
    }

    private var region: MKCoordinateRegion {
        let span = max(fix.horizontalAccuracyMeters * 4, 120)
        return MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: span,
            longitudinalMeters: span
        )
    }

    var body: some View {
        Map(initialPosition: .region(region)) {
            MapCircle(center: coordinate, radius: max(fix.horizontalAccuracyMeters, 8))
                .foregroundStyle(Color.accentColor.opacity(0.18))
            Marker("Property", systemImage: "house.fill", coordinate: coordinate)
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("Map of the phone's property location")
        .id(fix.timestamp)
    }
}
