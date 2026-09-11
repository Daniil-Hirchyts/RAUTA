import SwiftUI

/// The warm, low-contrast colour field shared by the app's content cards.
struct AuraTint {
    var core: Color
    var edge: Color
    var glow: Color

    static func single(_ color: Color) -> AuraTint {
        AuraTint(
            core: Theme.mix(Theme.card, color, 0.08),
            edge: color,
            glow: color
        )
    }
}

extension Theme {
    static let aura = AuraTint(core: card, edge: gold, glow: primary)
}

enum AuraPanelLevel {
    case quiet
    case lit
    case vivid

    var edgeOpacity: Double {
        switch self {
        case .quiet: return 0.16
        case .lit: return 0.22
        case .vivid: return 0.34
        }
    }

    var glowOpacity: Double {
        switch self {
        case .quiet: return 0.05
        case .lit: return 0.10
        case .vivid: return 0.18
        }
    }
}

struct AuraPanelBackground<S: InsettableShape>: View {
    var shape: S
    var level: AuraPanelLevel
    var tint: AuraTint = Theme.aura

    var body: some View {
        ZStack {
            shape.fill(tint.core.opacity(0.82))
            RadialGradient(
                colors: [tint.glow.opacity(level.glowOpacity), .clear],
                center: UnitPoint(x: 0.86, y: 1.04),
                startRadius: 0,
                endRadius: 280
            )
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(tint.edge.opacity(level.edgeOpacity), lineWidth: 1))
    }
}

extension View {
    func auraPanel(
        _ level: AuraPanelLevel,
        cornerRadius: CGFloat,
        tint: AuraTint = Theme.aura
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(AuraPanelBackground(shape: shape, level: level, tint: tint))
    }
}
