import SwiftUI

/// The app's one way to ask something on top of a page: a centred panel over a
/// dimmed page, which stays exactly where it was underneath. Anything that would
/// otherwise be a full-screen detour for a single question — a date, a
/// confirmation — belongs here.
///
/// The panel scales up from 0.96 as it fades in and leaves faster than it
/// arrives. The asymmetry is the point: an answer should feel quicker than the
/// question.
struct AppModal<Content: View>: View {
    var isPresented: Bool
    var label: String
    var onClose: () -> Void
    var panelPadding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            if isPresented {
                // The scrim dims the page — the panel is the only thing to
                // answer while it is up — and catches the taps that would
                // otherwise land underneath it.
                Theme.scrim
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { onClose() }

                content()
                    .padding(panelPadding)
                    .frame(maxWidth: 344)
                    .background(FrostedBackground(cornerRadius: Theme.Radius.xl3))
                    .padding(20)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity.combined(with: .scale(scale: 0.96))
                        )
                    )
                    .accessibilityLabel(label)
                    .accessibilityAddTraits(.isModal)
            }
        }
        .animation(Theme.Motion.smoothOut(isPresented ? 0.25 : 0.15), value: isPresented)
    }
}

enum ConfirmationKind: String, Identifiable {
    case clearData = "clear-data"
    case deleteWorkout = "delete-workout"
    case discardSession = "discard-session"
    case finishWorkout = "finish-workout"
    case finishWorkoutPartial = "finish-workout-partial"

    var id: String { rawValue }

    struct Copy {
        var action: String
        var description: String
        var title: String
        var destructive: Bool
    }

    /// The confirming button repeats the title's verb rather than saying
    /// "Continue": what is about to happen should be readable from the button
    /// the thumb is already over.
    var copy: Copy {
        switch self {
        case .clearData:
            return Copy(
                action: "Clear data", description: "", title: "Clear all data?", destructive: true
            )
        case .deleteWorkout:
            return Copy(
                action: "Delete workout",
                description: "The exercises stay in the library. "
                    + "Only this day's plan and its recorded time go.",
                title: "Delete workout?",
                destructive: true
            )
        case .discardSession:
            return Copy(
                action: "Discard session",
                description: "The timer and everything checked off are lost. "
                    + "The workout stays saved, and so do the sets you logged.",
                title: "Discard this session?",
                destructive: true
            )
        case .finishWorkout:
            return Copy(
                action: "Finish workout",
                description: "Your session progress and elapsed time will be saved to your history.",
                title: "Finish workout?",
                destructive: false
            )
        case .finishWorkoutPartial:
            // Finishing early is allowed; what it must not do is go into history
            // looking like the whole plan was done.
            return Copy(
                action: "Finish workout",
                description: "Some prescribed sets have not been logged, "
                    + "so this is saved to your history as a partial session.",
                title: "Finish workout?",
                destructive: false
            )
        }
    }
}

/// Every confirmation in the app is this modal: a question about a single tap is
/// not worth a screen of its own, and the answer reads better with the page it
/// applies to still on screen behind it.
struct ConfirmModal: View {
    var kind: ConfirmationKind?
    var error: String?
    var onCancel: () -> Void
    var onConfirm: () -> Void

    @ObservedObject private var store = AppStore.shared
    /// Clearing everything asks twice: the second pass is the one that says the
    /// data is not coming back.
    @State private var clearConfirmed = false

    private var finalClear: Bool { kind == .clearData && clearConfirmed }

    private var title: String {
        finalClear ? "This clears iCloud too" : (kind?.copy.title ?? "")
    }

    /// "This cannot be undone" only raises the voice. What someone needs in
    /// order to answer is what they are about to lose, counted — and then, on
    /// the second pass, the one fact the first screen cannot give them.
    private var description: String {
        guard let kind else { return "" }
        guard kind == .clearData else { return kind.copy.description }
        if finalClear {
            return "No other device keeps a copy, and reinstalling will not bring one back. "
                + "Export a backup first if you might want any of this later."
        }
        let workouts = Wording.countLabel(store.workouts.workouts.count, "workout")
        let favorites = Wording.countLabel(store.favorites.favoriteIds.count, "favorite")
        let presets = Wording.countLabel(store.filters.equipmentPresets.count, "equipment preset")
        return "\(workouts), \(favorites) and \(presets) are deleted, "
            + "and your settings go back to their defaults."
    }

    private var actionLabel: String {
        if error != nil { return "Try again" }
        if finalClear { return "Delete everything" }
        return kind?.copy.action ?? ""
    }

    var body: some View {
        AppModal(isPresented: kind != nil, label: title, onClose: onCancel) {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text(title)
                        .font(Theme.sans(18, weight: .black))
                        .kerning(-0.36)
                        .foregroundStyle(Theme.foreground)
                        .multilineTextAlignment(.center)
                    if !description.isEmpty {
                        Text(description)
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.mutedForeground)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)

                if let error {
                    Text(error)
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.destructive)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }

                HStack(spacing: 8) {
                    AppButton("Cancel", variant: .ghost, expands: true, action: onCancel)
                    AppButton(
                        actionLabel,
                        variant: (kind?.copy.destructive ?? false) ? .destructive : .primary,
                        expands: true
                    ) {
                        if kind == .clearData && !clearConfirmed {
                            Haptics.trigger(.medium)
                            clearConfirmed = true
                            return
                        }
                        Haptics.trigger(
                            kind == .finishWorkout || kind == .finishWorkoutPartial
                                ? .success
                                : .warning
                        )
                        onConfirm()
                    }
                }
                .padding(.top, 16)
            }
        }
        .onChange(of: kind) { _, next in
            if next != nil { clearConfirmed = false }
        }
    }
}
