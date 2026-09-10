import SwiftUI

/// The anatomy outlines, as they ship in `body-paths.generated.json`.
struct BodyPart {
    var slug: String
    var paths: [Path]
    var muscle: MuscleId?
}

struct BodyView_Model {
    var viewBox: CGRect
    var parts: [BodyPart]
}

enum BodyPaths {
    private static let views: (front: BodyView_Model, back: BodyView_Model) = {
        let root = BundledData.json("body-paths.generated")
        return (parse(root?["front"]), parse(root?["back"]))
    }()

    static var front: BodyView_Model { views.front }
    static var back: BodyView_Model { views.back }

    static func view(_ side: BodySide) -> BodyView_Model {
        side == .front ? front : back
    }

    private static func parse(_ value: JSONValue?) -> BodyView_Model {
        let numbers = (value?["viewBox"]?.stringValue ?? "0 0 100 100")
            .split(separator: " ")
            .compactMap { Double($0) }
        let box = numbers.count == 4
            ? CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
            : CGRect(x: 0, y: 0, width: 100, height: 100)

        let parts = (value?["parts"]?.arrayValue ?? []).compactMap { item -> BodyPart? in
            guard let object = item.objectValue, let slug = object["slug"]?.stringValue
            else { return nil }
            let paths = (object["paths"]?.arrayValue ?? [])
                .compactMap(\.stringValue)
                .compactMap(SVGPath.parse)
            guard !paths.isEmpty else { return nil }
            return BodyPart(slug: slug, paths: paths, muscle: MuscleId(rawValue: slug))
        }
        return BodyView_Model(viewBox: box, parts: parts)
    }
}

/// Which way the figure is facing.
enum BodySide: String, Hashable { case front, back }

private let swipeThreshold: CGFloat = 45

/// The figure, painted muscle by muscle.
///
/// A selection can carry a degree — how much of a training week a muscle is
/// meant to take. It mixes toward the resting fill rather than fading out, so a
/// lighter region still reads as painted rather than as a hole in the figure.
struct BodyFigure: View {
    var view: BodyView_Model
    var selectedMuscles: [MuscleId]
    var muscleWeights: [MuscleId: Double] = [:]
    var onToggle: ((MuscleId) -> Void)?
    var compact: Bool = false

    private static let restingFill = Color(hex: 0x3D322B)
    private static let silhouetteFill = Color(hex: 0x2D241F)
    private static let outline = Color(hex: 0x100D0B)

    var body: some View {
        GeometryReader { proxy in
            let scale = Swift.min(
                proxy.size.width / view.viewBox.width,
                proxy.size.height / view.viewBox.height
            )
            let offsetX = (proxy.size.width - view.viewBox.width * scale) / 2
                - view.viewBox.minX * scale
            let offsetY = (proxy.size.height - view.viewBox.height * scale) / 2
                - view.viewBox.minY * scale

            ZStack(alignment: .topLeading) {
                ForEach(view.parts, id: \.slug) { part in
                    partShape(part, scale: scale, offset: CGPoint(x: offsetX, y: offsetY))
                }
            }
            .contentShape(Rectangle())
            .modifier(TapLocator { location in
                guard let onToggle else { return }
                let point = CGPoint(
                    x: (location.x - offsetX) / scale,
                    y: (location.y - offsetY) / scale
                )
                guard let muscle = hitTest(point, scale: scale) else { return }
                Haptics.trigger(.selection)
                onToggle(muscle)
            })
        }
    }

    private func partShape(_ part: BodyPart, scale: CGFloat, offset: CGPoint) -> some View {
        let transform = CGAffineTransform(translationX: offset.x, y: offset.y)
            .scaledBy(x: scale, y: scale)
        return ZStack {
            ForEach(part.paths.indices, id: \.self) { index in
                let path = part.paths[index].applying(transform)
                if let muscle = part.muscle {
                    let selected = selectedMuscles.contains(muscle)
                    let weight = selected ? (muscleWeights[muscle] ?? 1) : 0
                    let fill = selected
                        ? Theme.mix(Self.restingFill, Theme.primary, weight)
                        : Self.restingFill

                    path
                        .fill(fill)
                        .overlay {
                            if !selected {
                                path.stroke(Self.outline, lineWidth: 3 * scale)
                            }
                        }
                        .shadow(
                            color: selected
                                ? Theme.primary.opacity(0.55 * weight)
                                : .black.opacity(0.45),
                            radius: selected ? 4 : 2,
                            y: selected ? 0 : 2
                        )
                        .animation(Theme.Motion.smoothOut(0.16), value: selected)
                } else {
                    path
                        .fill(Self.silhouetteFill)
                        .overlay(path.stroke(Self.outline, lineWidth: 3 * scale))
                }
            }
        }
    }

    private func hitTest(_ point: CGPoint, scale: CGFloat) -> MuscleId? {
        // Front to back, so a region drawn last wins the tap the way the SVG
        // stacking order did. Browser SVG hit testing includes the painted
        // outline as well as the fill, so include the source 3-unit stroke too.
        // Do that exact pass first so adjacent muscles keep the browser's
        // behavior. If the finger lands just outside a narrow painted region,
        // make a second pass with roughly 10 pt of screen-space tolerance.
        for part in view.parts.reversed() {
            guard let muscle = part.muscle else { continue }
            if part.paths.contains(where: {
                $0.contains(point)
                    || $0.strokedPath(StrokeStyle(lineWidth: 3)).contains(point)
            }) {
                return muscle
            }
        }

        let touchWidth = Swift.max(3, 20 / Swift.max(scale, 0.001))
        for part in view.parts.reversed() {
            guard let muscle = part.muscle else { continue }
            if part.paths.contains(where: {
                $0.strokedPath(
                    StrokeStyle(lineWidth: touchWidth, lineCap: .round, lineJoin: .round)
                ).contains(point)
            }) {
                return muscle
            }
        }
        return nil
    }
}

/// Reports the exact point a tap landed on, which SwiftUI's `onTapGesture`
/// alone does not give in a shape-hit-testing form.
private struct TapLocator: ViewModifier {
    var onTap: (CGPoint) -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            SpatialTapGesture()
                .onEnded { value in onTap(value.location) }
        )
    }
}

/// The full picker: one figure, a flip, a swipe, and the side it is showing.
struct BodyMap: View {
    var selectedMuscles: [MuscleId]
    /// How strongly each selected region paints, 0–1. Left out, every selection
    /// paints at full strength — which is what picking muscles for one workout
    /// means.
    var muscleWeights: [MuscleId: Double] = [:]
    var onToggle: (MuscleId) -> Void
    var onSideChange: ((BodySide) -> Void)?
    var showCornerCount: Bool = false
    var showFlipButton: Bool = true
    var side: BodySide?

    @State private var internalSide: BodySide = .front

    private var currentSide: BodySide { side ?? internalSide }
    private var label: String { currentSide == .front ? "Front" : "Back" }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                BodyFigure(
                    view: BodyPaths.view(currentSide),
                    selectedMuscles: selectedMuscles,
                    muscleWeights: muscleWeights,
                    onToggle: onToggle
                )
                .padding(14)
                .id(currentSide)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))

                if showCornerCount && !selectedMuscles.isEmpty {
                    HStack(spacing: 4) {
                        AnimatedNumber(value: selectedMuscles.count)
                        Text("selected")
                    }
                    .font(Theme.sans(12, weight: .bold))
                    .kerning(1.9)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                if showFlipButton {
                    Button(action: flip) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 44, height: 44)
                            .background(FrostedBackground(cornerRadius: 22, compact: true))
                    }
                    .buttonStyle(.plain)
                    .padding(14)
                    .accessibilityLabel("Show \(currentSide == .front ? "back" : "front")")
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: swipeThreshold)
                    .onEnded { value in
                        if abs(value.translation.width) > swipeThreshold { flip() }
                    }
            )

            TextSwap(
                text: label.uppercased(),
                font: Theme.sans(12, weight: .bold),
                color: Theme.mutedForeground
            )
            .kerning(1.9)
            .padding(.bottom, 4)
        }
        .animation(Theme.Motion.smoothOut(0.22), value: currentSide)
    }

    private func flip() {
        Haptics.trigger(.selection)
        let next: BodySide = currentSide == .front ? .back : .front
        if side == nil { internalSide = next }
        onSideChange?(next)
    }
}

/// The two small figures a workout row draws beside its title.
struct BodyPreview: View {
    var selectedMuscles: [MuscleId]
    var width: CGFloat = 96
    var height: CGFloat = 64

    var body: some View {
        HStack(spacing: 2) {
            BodyFigure(
                view: BodyPaths.front, selectedMuscles: selectedMuscles, compact: true
            )
            BodyFigure(
                view: BodyPaths.back, selectedMuscles: selectedMuscles, compact: true
            )
        }
        .frame(width: width, height: height)
        .accessibilityLabel(
            selectedMuscles.isEmpty
                ? "No target muscles"
                : "Target muscles: " + selectedMuscles.map(\.label).joined(separator: ", ")
        )
    }
}
