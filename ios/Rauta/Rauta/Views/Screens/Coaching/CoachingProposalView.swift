import SwiftUI

/// A change RAUTA prepared, shown before anything is saved: what it does, what
/// to know, and each affected workout with what changes in it and why.
struct CoachingProposalView: View {
    let proposal: CoachingProposal
    /// Kept already: the "nothing is saved" reassurance no longer holds.
    var applied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(proposal.title)
                    .font(Theme.sans(20, weight: .heavy))
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(proposal.summary)
                    .font(Theme.sans(14, weight: .medium))
                    .foregroundStyle(Theme.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
                if !applied {
                    Label("Nothing is saved until you keep it.", systemImage: "hand.raised")
                        .font(Theme.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .padding(.horizontal, 4)

            ForEach(proposal.changes) { change in
                SessionChangeCard(change: change)
            }

            if !proposal.notes.isEmpty {
                PageSection(title: "Good to know") {
                    ForEach(Array(proposal.notes.enumerated()), id: \.offset) { index, note in
                        PageRow(icon: "info.circle", title: note, showsDivider: index < proposal.notes.count - 1)
                    }
                }
            }
        }
    }
}

/// One workout as a proposal leaves it.
struct SessionChangeCard: View {
    let change: PlanSessionChange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Text(change.date == CalendarDate.today ? "TODAY" : CalendarDate.weekdayShort(change.date).uppercased())
                        .font(Theme.sans(10, weight: .black))
                        .kerning(0.8)
                        .foregroundStyle(Theme.primary)
                    Text(CalendarDate.dayOfMonth(change.date))
                        .font(Theme.sans(24, weight: .black))
                        .foregroundStyle(Theme.foreground)
                    Text(CalendarDate.monthShort(change.date).uppercased())
                        .font(Theme.sans(9, weight: .bold))
                        .foregroundStyle(Theme.mutedForeground)
                }
                .frame(width: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(CalendarDate.format(change.date, "EEEEdMMMM"))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(change.title)
                            .font(Theme.sans(17, weight: .bold))
                            .foregroundStyle(Theme.foreground)
                        Spacer(minLength: 6)
                        Text(minutesText)
                            .font(Theme.sans(13, weight: .semibold))
                            .foregroundStyle(Theme.mutedForeground)
                            .monospacedDigit()
                    }
                    if let previous = change.previousDate {
                        Text(change.previousIsSource
                             ? "Follows on from \(CalendarDate.short(previous))"
                             : "Was \(CalendarDate.short(previous))")
                            .font(Theme.sans(12, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                    }
                    if !change.exerciseIds.isEmpty {
                        ExerciseStrip(exerciseIds: change.exerciseIds)
                            .padding(.top, 4)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(change.lines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: line.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint(line.kind))
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        Text(line.text)
                            .font(Theme.sans(13, weight: .medium))
                            .foregroundStyle(line.kind == .kept ? Theme.mutedForeground : Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { GradientCard(radius: Theme.Radius.xl2, accent: Theme.primary, strength: 0.6) }
    }

    private var minutesText: String {
        guard change.minutes > 0 else { return "" }
        if let previous = change.previousMinutes, previous != change.minutes, previous > 0 {
            return "\(previous) → \(change.minutes) min"
        }
        return "~\(change.minutes) min"
    }

    private func tint(_ kind: PlanChangeLine.Kind) -> Color {
        switch kind {
        case .kept: return Theme.mutedForeground
        case .progressed, .added: return Theme.success
        case .removed: return Theme.destructive
        case .swapped, .sets, .moved: return Theme.primary
        case .note: return Theme.gold
        }
    }
}

/// The buttons under a proposal: keep it or leave it, then undo once kept.
struct CoachingProposalControls: View {
    var proposal: CoachingProposal?
    var applied: CoachingUndo?
    var working: Bool
    var onKeep: () -> Void
    var onDiscard: () -> Void
    var onUndo: () -> Void
    var onDone: () -> Void

    var body: some View {
        if applied != nil {
            HStack(spacing: 10) {
                AppButton("Undo", variant: .secondary, size: .cta, expands: true, action: onUndo)
                AppButton("Done", size: .cta, expands: true, action: onDone)
            }
        } else if proposal != nil {
            HStack(spacing: 10) {
                AppButton("Not now", variant: .secondary, size: .cta, expands: true, action: onDiscard)
                AppButton(working ? "Saving…" : "Keep this", size: .cta, isDisabled: working, expands: true, action: onKeep)
            }
        }
    }
}
