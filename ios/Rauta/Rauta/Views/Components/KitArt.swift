import SwiftUI

/// A piece of kit as the app draws it: its render when one is bundled at
/// `Media/equipment/<name>.webp`, otherwise a symbol that stands in for it.
/// Fixtures (pull-up bar, bench, rack…) share the equipment folder.
struct KitArt: View {
    let item: String

    private static let symbols: [String: String] = [
        "pull-up bar": "figure.play",
        "dip station": "figure.strengthtraining.functional",
        "dip bars": "figure.strengthtraining.functional",
        "bench": "bed.double",
        "rack": "square.split.bottomrightquarter",
        "low bar": "arrow.down.to.line",
        "suspension trainer": "point.topleft.down.to.point.bottomright.curvepath",
        "glute-ham bench": "bed.double",
        "slide board": "rectangle.portrait",
        "balance board": "circle.bottomhalf.filled",
        "band anchor": "link",
    ]

    var body: some View {
        if let image = StillImage.load(MediaLibrary.equipmentURL(item)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .saturation(1.25)
                .hueRotation(.degrees(Theme.palette.hueShift))
        } else {
            Image(systemName: Self.symbols[item] ?? "dumbbell")
                .resizable()
                .scaledToFit()
                .fontWeight(.medium)
                .foregroundStyle(Theme.primary)
                .padding(4)
        }
    }
}
