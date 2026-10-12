import SwiftUI

/// The training words RAUTA uses, each explained in a sentence where it is
/// used. One list, so a term means the same on every screen.
enum TrainingTerm: String, Identifiable {
    case repsLeft
    case calibration
    case effectiveSets
    case estimatedOneRepMax
    case sessionLength

    var id: String { rawValue }

    var title: String {
        switch self {
        case .repsLeft: return "Reps left"
        case .calibration: return "Calibration"
        case .effectiveSets: return "Effective sets"
        case .estimatedOneRepMax: return "Estimated 1RM"
        case .sessionLength: return "Session length"
        }
    }

    var explanation: String {
        switch self {
        case .repsLeft:
            return "How many more repetitions could you have done with good form? 0 means none were left. "
                + "Plans call it RIR, reps in reserve. If you're not sure, leave it empty: RAUTA keeps it unknown "
                + "rather than guessing, and holds the load until it knows."
        case .calibration:
            return "RAUTA doesn't know your load for this yet. Pick a weight you think you can lift for the target reps "
                + "with the reps left shown, and log what really happened. The next session's load comes from that."
        case .effectiveSets:
            return "Sets that count for a muscle. When the muscle does the main work, a working set counts as 1; "
                + "when it helps, as ½. Warm-ups don't count."
        case .estimatedOneRepMax:
            return "The most you could probably lift once, worked out from a hard set of 10 reps or fewer with 2 or "
                + "fewer reps left. It's an estimate, not something you lifted."
        case .sessionLength:
            return "The time you'd like a session to take, warm-up and rest included. RAUTA treats it as a target and "
                + "never plans more than 10 minutes past it. A session can come out shorter when the week's work "
                + "is already covered — RAUTA doesn't pad it with extra sets."
        }
    }
}

/// A small ⓘ beside a term, opening its explanation in place.
struct TermInfoButton: View {
    let term: TrainingTerm
    var tint: Color = Theme.mutedForeground
    @State private var open = false

    var body: some View {
        Button {
            Haptics.trigger(.selection)
            open = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What does \(term.title.lowercased()) mean?")
        .popover(isPresented: $open, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(term.title)
                    .font(Theme.sans(15, weight: .bold))
                    .foregroundStyle(Theme.foreground)
                Text(term.explanation)
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 300, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// How many reps were left in the tank after a set, chosen in one tap — and
/// left empty, honestly unknown, until someone chooses. Tapping the chosen
/// count again clears it.
struct RepsLeftPicker: View {
    @Binding var value: Double?
    /// What the plan asked for, shown as a hint and never filled in for you.
    var target: Double?

    private static let options: [Double] = [0, 1, 2, 3, 4, 5]

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("REPS LEFT")
                        .font(Theme.sans(10, weight: .black))
                        .kerning(1.4)
                        .foregroundStyle(Theme.mutedForeground)
                    Text(caption)
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(value == nil ? Theme.mutedForeground : Theme.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                TermInfoButton(term: .repsLeft)
            }
            .frame(minWidth: 92, alignment: .leading)
            .accessibilityElement(children: .contain)

            HStack(spacing: 4) {
                ForEach(Self.options, id: \.self) { option in
                    let selected = value.map { option == 5 ? $0 >= 5 : $0 == option } ?? false
                    Button {
                        Haptics.trigger(.selection)
                        value = selected ? nil : option
                    } label: {
                        Text(option == 5 ? "5+" : Num.trimmed(option))
                            .font(Theme.sans(15, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(selected ? Theme.primaryForeground : Theme.foreground)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selected ? Theme.primary : Theme.muted.opacity(0.35))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        option == target && !selected ? Theme.primary.opacity(0.55) : Theme.border,
                                        lineWidth: 1
                                    )
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option == 5 ? "5 or more reps left" : "\(Num.trimmed(option)) reps left")
                    .accessibilityHint(option == target ? "The plan's target" : "")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .frame(minHeight: 44)
    }

    private var caption: String {
        guard let value else {
            return target.map { "aim for \(Num.trimmed($0))" } ?? "not recorded"
        }
        return value >= 5 ? "5 or more" : "\(Num.trimmed(value)) more"
    }
}
