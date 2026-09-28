import SwiftUI
import UIKit

enum MainTab: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case workout = "Workout"
    case library = "Library"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .summary: return "chart.bar"
        case .workout: return "figure.strengthtraining.traditional"
        case .library: return "books.vertical"
        }
    }
}

/// RAUTA's auxiliary slot is a control, never a destination. Keeping it out of
/// `MainTab` prevents it from becoming restorable navigation state.
enum NativeTabSelection: Hashable {
    case page(MainTab)
    case rauta
}

enum NativeTabIcons {
    static let summary = make(MainTab.summary.systemImage)
    static let workout = make(MainTab.workout.systemImage)
    static let library = make(MainTab.library.systemImage)
    static let transparentPlaceholder = UIGraphicsImageRenderer(
        size: CGSize(width: 28, height: 28)
    ).image { _ in }

    static func image(for tab: MainTab) -> UIImage {
        switch tab {
        case .summary: return summary
        case .workout: return workout
        case .library: return library
        }
    }

    private static func make(_ systemName: String) -> UIImage {
        let canvasSize = CGSize(width: 28, height: 28)
        let visibleSize = CGSize(width: 20, height: 20)
        let configuration = UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: configuration) else {
            return UIImage()
        }

        let scale = min(visibleSize.width / symbol.size.width, visibleSize.height / symbol.size.height)
        let drawingSize = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let drawingRect = CGRect(
            x: (canvasSize.width - drawingSize.width) / 2,
            y: (canvasSize.height - drawingSize.height) / 2,
            width: drawingSize.width,
            height: drawingSize.height
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: canvasSize, format: format).image { _ in
            symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: drawingRect)
        }
        return rendered.withRenderingMode(.alwaysTemplate)
    }
}
