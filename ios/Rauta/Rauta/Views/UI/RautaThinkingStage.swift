import SwiftUI

/// One of the inputs RAUTA is weighing, as it orbits: a symbol for what kind of
/// input it is, and the input itself. Some are the symbol alone.
struct ThinkingChip: Hashable {
    var symbol: String
    var label: String = ""
}

/// RAUTA at work, as a scene rather than a spinner: the character in the middle
/// working away, the real inputs it is weighing orbiting it, rings pulsing out
/// from it, warm light drifting behind, and underneath, a line saying which of
/// those inputs it is turning over.
///
/// Nothing here claims progress. The chips and the thoughts are the request
/// itself — the days, the goal, the equipment — so the scene can run for as
/// long as the work does and never say something that has not happened.
struct RautaThinkingStage: View {
    /// What RAUTA is turning over, one at a time.
    var thoughts: [String]
    /// The inputs, as symbols and short labels.
    var chips: [ThinkingChip]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private static let characterSize: CGFloat = 150
    private static let thoughtSeconds: TimeInterval = 2.4

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            GeometryReader { proxy in
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.42)
                ZStack {
                    aurora(t, in: proxy.size)

                    Canvas { context, _ in
                        drawRings(context, at: center, time: t)
                    }

                    ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                        let pose = orbit(index: index, time: t, center: center, width: proxy.size.width)
                        if !pose.front { chipView(chip, pose: pose) }
                    }

                    RautaCharacter(mood: .working)
                        .frame(width: Self.characterSize, height: Self.characterSize)
                        .offset(y: reduceMotion ? 0 : CGFloat(sin(t * 2.2)) * 5)
                        .position(center)
                        .accessibilityHidden(true)

                    ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                        let pose = orbit(index: index, time: t, center: center, width: proxy.size.width)
                        if pose.front { chipView(chip, pose: pose) }
                    }

                    // The thought reads under the scene, not in a bubble:
                    // RAUTA is busy, and the line says with what.
                    thought(at: t)
                        .frame(maxWidth: min(320, proxy.size.width - 48))
                        .position(x: center.x, y: min(proxy.size.height - 44, center.y + 176))
                }
            }
        }
        .onAppear { start = Date() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(thoughts.first ?? "Working")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Pieces

    /// Two warm blobs of light drifting slowly behind the scene.
    private func aurora(_ t: TimeInterval, in size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(Theme.primary.opacity(0.32))
                .frame(width: size.width * 0.9)
                .blur(radius: 70)
                .offset(x: CGFloat(sin(t * 0.5)) * 50, y: CGFloat(cos(t * 0.4)) * 30 + size.height * 0.06)
            Circle()
                .fill(Theme.oxblood.opacity(0.36))
                .frame(width: size.width * 0.8)
                .blur(radius: 80)
                .offset(x: CGFloat(cos(t * 0.35)) * -60, y: CGFloat(sin(t * 0.45)) * 40 + size.height * 0.16)
            Circle()
                .fill(Theme.gold.opacity(0.12))
                .frame(width: size.width * 0.5)
                .blur(radius: 60)
                .offset(x: CGFloat(sin(t * 0.7 + 1)) * 80, y: size.height * 0.02)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    /// Rings breathing out of RAUTA, one after another.
    private func drawRings(_ context: GraphicsContext, at center: CGPoint, time t: TimeInterval) {
        guard !reduceMotion else { return }
        let period = 2.4
        for ring in 0..<3 {
            let phase = ((t + Double(ring) * period / 3).truncatingRemainder(dividingBy: period)) / period
            let radius = 70 + 150 * phase
            var stroke = context
            stroke.opacity = (1 - phase) * 0.55
            stroke.stroke(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius * 0.62, width: radius * 2, height: radius * 1.24)),
                with: .color(ring == 1 ? Theme.gold : Theme.primary),
                lineWidth: 2
            )
        }
    }

    private struct OrbitPose {
        var point: CGPoint
        var scale: CGFloat
        var opacity: Double
        var front: Bool
    }

    /// Where input `index` is on its loop: an ellipse seen from a little above,
    /// so the near side passes in front of RAUTA, larger and brighter.
    private func orbit(index: Int, time t: TimeInterval, center: CGPoint, width: CGFloat) -> OrbitPose {
        let count = max(1, chips.count)
        let speed = reduceMotion ? 0 : 0.42
        let angle = Double(index) / Double(count) * 2 * .pi + t * speed
        let depth = sin(angle)
        let radiusX = Double(min(width * 0.4, 170))
        return OrbitPose(
            point: CGPoint(x: center.x + CGFloat(cos(angle) * radiusX), y: center.y + CGFloat(depth * 58) + 14),
            scale: CGFloat(0.82 + 0.22 * (depth + 1) / 2),
            opacity: 0.45 + 0.55 * (depth + 1) / 2,
            front: depth > 0
        )
    }

    private func chipView(_ chip: ThinkingChip, pose: OrbitPose) -> some View {
        HStack(spacing: 6) {
            Image(systemName: chip.symbol)
                .font(.system(size: chip.label.isEmpty ? 16 : 13, weight: .semibold))
                .foregroundStyle(Theme.primary)
            if !chip.label.isEmpty {
                Text(chip.label)
                    .font(Theme.sans(13, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, chip.label.isEmpty ? 11 : 12)
        .padding(.vertical, chip.label.isEmpty ? 11 : 7)
        .glassSurface(
            .tinted(Theme.primary.opacity(0.18)),
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .scaleEffect(pose.scale)
        .opacity(pose.opacity)
        .position(pose.point)
    }

    /// The line under the scene, changing every few seconds.
    private func thought(at t: TimeInterval) -> some View {
        let index = thoughts.isEmpty ? 0 : Int(t / Self.thoughtSeconds) % thoughts.count
        let text = thoughts.isEmpty ? "Working on it…" : thoughts[index]
        return ShimmerText(text: text, font: Theme.sans(17, weight: .semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .id(index)
            .transition(.asymmetric(
                insertion: .offset(y: 8).combined(with: .opacity),
                removal: .opacity
            ))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: index)
    }
}

/// The lines and labels RAUTA works over while it plans a week, taken from the
/// request itself.
enum ThinkingInputs {
    @MainActor
    static func plan(dates: [String]) -> (thoughts: [String], chips: [ThinkingChip]) {
        let store = AppStore.shared
        let profile = store.trainingProfile.profile
        let goal = ProfileVocabulary.goalLabel(profile.goal)
        let minutes = Int(profile.preferredSessionDurationMinutes)
        let equipment = store.filters.gymEquipment.count
        let priorities = profile.priorityMuscles.prefix(2).map { $0.muscleId.label.lowercased() }

        var thoughts = ["Spreading the work across \(PlanTalk.days(dates))…"]
        thoughts.append("Keeping each session near \(minutes) min…")
        if equipment > 0 { thoughts.append("Choosing from your \(Wording.countLabel(equipment, "piece")) of equipment…") }
        thoughts.append("Setting sets and reps for \(goal.lowercased())…")
        if !priorities.isEmpty { thoughts.append("Giving \(priorities.joined(separator: " and ")) a little extra…") }

        var chips = dates.sorted().prefix(4).map { ThinkingChip(symbol: "calendar", label: CalendarDate.format($0, "EEEd")) }
        chips.append(ThinkingChip(symbol: goalSymbol(profile.goal), label: goal))
        chips.append(ThinkingChip(symbol: "timer", label: "\(minutes) min"))
        if equipment > 0 { chips.append(ThinkingChip(symbol: "dumbbell.fill", label: "\(equipment)")) }
        chips += priorities.map { ThinkingChip(symbol: "scope", label: $0.capitalized) }
        chips.append(ThinkingChip(symbol: "chart.line.uptrend.xyaxis"))
        return (thoughts, Array(chips.prefix(9)))
    }

    @MainActor
    static func workout(muscles: [MuscleId], equipmentCount: Int) -> (thoughts: [String], chips: [ThinkingChip]) {
        let names = muscles.prefix(3).map { $0.label.lowercased() }
        var thoughts = ["Picking exercises for \(names.isEmpty ? "the whole body" : names.joined(separator: ", "))…"]
        if equipmentCount > 0 {
            thoughts.append("Using what you have: \(Wording.countLabel(equipmentCount, "item"))…")
        }
        thoughts.append("Fitting it into today…")
        var chips = muscles.prefix(4).map { ThinkingChip(symbol: "figure.strengthtraining.traditional", label: $0.label) }
        if equipmentCount > 0 { chips.append(ThinkingChip(symbol: "dumbbell.fill", label: "\(equipmentCount)")) }
        chips.append(ThinkingChip(symbol: "sun.max.fill", label: "Today"))
        chips.append(ThinkingChip(symbol: "list.number"))
        return (thoughts, chips)
    }

    private static func goalSymbol(_ goal: TrainingGoal) -> String {
        switch goal {
        case .hypertrophy, .strengthHypertrophy: return "figure.strengthtraining.traditional"
        case .strength, .power: return "bolt.fill"
        case .generalFitness: return "heart.fill"
        case .muscularEndurance: return "arrow.triangle.2.circlepath"
        case .fatLossSupport: return "flame.fill"
        }
    }
}
