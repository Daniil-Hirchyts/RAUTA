import SwiftUI

struct ActiveSetLog: View {
    private let store = AppStore.shared
    let exerciseId: String
    var restSeconds: Double = 90
    var hasNextExercise = false
    var onFinishExercise: (() -> Void)? = nil

    @State private var selectedSetId: String?
    @State private var reps = 10.0
    @State private var kilograms: Double? = 0
    @State private var rir: Double?
    @State private var mode: ResistanceMode = .externalLoad
    @State private var side: SetSide = .both
    @State private var stationContext: StationContext?
    @State private var issue: String?
    @State private var modeMenuOpen = false
    @State private var sideMenuOpen = false

    private var exercise: ExerciseSummary? { ExerciseCatalogue.byId[exerciseId] }
    private var draft: PersistedActiveExerciseDraft? {
        TrainingSessionBridge.draftExercise(store.trainingRecords.data.activeWorkout, exerciseId)
    }
    private var selectedSet: PersistedActiveSetDraft? {
        if let selectedSetId, let match = draft?.sets.first(where: { $0.id == selectedSetId }) {
            return match
        }
        return draft?.sets.first { $0.observation?.completed != true }
    }
    private var context: StationContext? {
        if let stationContext { return stationContext }
        guard let exercise else { return nil }
        return loadContext(for: exercise, mode: mode)
    }

    private var target: PersistedSetTarget? {
        draft?.sets.first { $0.setType == .working && $0.target != nil }?.target
            ?? draft?.sets.first { $0.target != nil }?.target
    }

    /// The target the header shows: the set the counter is loaded from, so the
    /// two always agree. An extra set with no target of its own reads against
    /// the working sets.
    private var headerTarget: (label: String?, target: PersistedSetTarget)? {
        if let set = selectedSet, let own = set.target, let draft {
            return (setTitle(set, in: draft), own)
        }
        return target.map { (nil, $0) }
    }

    private var allSetsCompleted: Bool {
        guard let sets = draft?.sets, !sets.isEmpty else { return false }
        return sets.allSatisfy { $0.observation?.completed == true }
    }

    private var recommendation: ProgressionRecommendation? {
        guard let draft else { return nil }
        return TrainingWorkflow.nextPerformance(
            draft,
            data: store.trainingRecords.data,
            increments: store.filters.equipmentLoadIncrements,
            loggedMode: mode,
            loggedContext: Resistance.isMeasuredInKg(mode) ? context : nil
        )
    }

    private var progressionNote: ProgressionNote? {
        guard let exercise,
              Resistance.isMeasuredInKg(Resistance.modes(for: exercise).first ?? .unknown),
              let recommendation
        else { return nil }
        return ProgressionNotes.note(recommendation, previousKg: previousComparableKg(recommendation))
    }

    var body: some View {
        SurfaceCard(padding: 10, cornerRadius: Theme.Radius.xl3) {
            VStack(spacing: 8) {
                header
                if let draft, !draft.sets.isEmpty { setRows(draft) }
                editor
                if let issue { InlineNotice(message: issue, isError: true) }
            }
        }
        .onAppear {
            loadCurrent()
        }
        .onChange(of: selectedSetId) { _, _ in loadCurrent() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let headerTarget {
                HStack(spacing: 6) {
                    Text([headerTarget.label, targetSummary(headerTarget.target)]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                        .font(Theme.sans(12, weight: .bold))
                        .foregroundStyle(Theme.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: selectedSet?.id)
                    if isCalibrating(headerTarget.target) {
                        TermInfoButton(term: .calibration, tint: Theme.primary)
                    }
                }
            }
            // The engine's reason in full: recorded, suggested and unknown
            // kept apart, never cut off.
            if let progressionNote {
                Text(progressionText(progressionNote))
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func setRows(_ draft: PersistedActiveExerciseDraft) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("").frame(width: 22, alignment: .leading)
                Text("Load").frame(maxWidth: .infinity, alignment: .leading)
                Text("Reps").frame(width: 44, alignment: .trailing)
                Text("Left").frame(width: 44, alignment: .trailing)
                    .accessibilityLabel("Reps left")
            }
            .font(Theme.sans(9, weight: .bold))
            .kerning(1.08)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(Theme.mutedForeground)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.border.opacity(0.6)).frame(height: 1)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(Array(draft.sets.enumerated()), id: \.element.id) { index, set in
                        Button {
                            selectedSetId = set.id
                        } label: {
                            let done = set.observation?.completed == true
                            HStack {
                                Text(setNumber(set, in: draft))
                                    .foregroundStyle(set.setType == .warmup ? Theme.primary : (done ? Theme.foreground : Theme.mutedForeground))
                                    .frame(width: 22, alignment: .leading)
                                Text(done ? set.observation?.resistance.map(Resistance.format) ?? "—" : plannedLoad(set))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(done ? set.observation?.reps.map(Num.trimmed) ?? "—" : plannedReps(set))
                                    .frame(width: 44, alignment: .trailing)
                                Text(done ? set.observation?.rir.map(Num.trimmed) ?? "—" : set.target.map { Num.trimmed($0.rir) } ?? "—")
                                    .frame(width: 44, alignment: .trailing)
                            }
                            .font(Theme.sans(15, weight: .semibold))
                            // Not yet logged: the row shows what the set asks
                            // for, quieter than what was done.
                            .foregroundStyle(done ? Theme.foreground : Theme.mutedForeground.opacity(0.75))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(
                                (selectedSet?.id == set.id ? Theme.primary : Theme.muted).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(set.setType == .warmup ? "Warm-up set" : "Set \(setNumber(set, in: draft))")
                        .accessibilityValue(rowDescription(set))
                        .accessibilityAddTraits(selectedSet?.id == set.id ? .isSelected : [])
                    }
                }
            }
            .frame(height: min(CGFloat(draft.sets.count) * 48, 168))
        }
    }

    private var editor: some View {
        VStack(spacing: 8) {
            if exercise != nil {
                if Resistance.isMeasuredInKg(mode) {
                    AppStepper(
                        label: mode == .assistance ? "Assistance" : "Load",
                        display: kilograms.map(Resistance.formatKg) ?? "—",
                        unit: context?.basis == .perImplement && mode == .externalLoad ? "kg each" : "kg",
                        canDecrement: kilograms.map { $0 > 0 } ?? false
                    ) { direction in
                        stepLoad(direction)
                    }
                }

                AppStepper(
                    label: "Reps",
                    display: Num.trimmed(reps),
                    unit: "reps",
                    canDecrement: reps > 1
                ) { direction in
                    reps = min(100, max(1, reps + Double(direction)))
                }

                if selectedSet?.setType != .warmup {
                    RepsLeftPicker(value: $rir, target: selectedSet?.target?.rir ?? target?.rir)
                }
            }

            HStack(spacing: 8) {
                if selectedSet != nil, selectedSet?.plannedSetId == nil {
                    AppButton(
                        variant: .destructive,
                        size: .icon,
                        accessibilityLabel: "Delete this set",
                        action: discard
                    ) {
                        Image(systemName: "trash")
                    }
                }
                if allSetsCompleted, selectedSetId == nil {
                    AppButton(
                        variant: .secondary,
                        size: .icon,
                        accessibilityLabel: "Add another set",
                        action: addExtraSet
                    ) {
                        Image(systemName: "plus")
                    }
                }
                if let exercise {
                    let modes = Resistance.modes(for: exercise)
                    if modes.count > 1 {
                        modeMenu(modes)
                    }
                    let sides = Resistance.sideOptions(for: exercise)
                    if sides.count > 1 {
                        sideMenu(sides)
                    }
                }
                if allSetsCompleted, selectedSetId == nil, let onFinishExercise {
                    AppButton(
                        hasNextExercise ? "Next exercise" : "Finish exercise",
                        variant: .ghost,
                        expands: true
                    ) {
                        // The caller confirms the finish: one success, not two.
                        onFinishExercise()
                    }
                } else {
                    AppButton(
                        resolvedSubmitLabel,
                        variant: .ghost,
                        isDisabled: Resistance.isMeasuredInKg(mode) && kilograms == nil,
                        expands: true,
                        action: save
                    )
                }
            }
        }
    }

    private func sideMenu(_ options: [SetSide]) -> some View {
        AppControlButton(
            systemImage: sideIcon(side),
            label: "Side: \(Wording.titleCase(side.rawValue))"
        ) {
            Haptics.trigger(.selection)
            sideMenuOpen = true
        }
        .popover(isPresented: $sideMenuOpen, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            AppMenuSurface(dismiss: { sideMenuOpen = false }) {
                ForEach(options, id: \.self) { option in
                    Button {
                        sideMenuOpen = false
                        side = option
                    } label: {
                        HStack(spacing: 10) {
                            Label(Wording.titleCase(option.rawValue), systemImage: sideIcon(option))
                            Spacer(minLength: 12)
                            if side == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.primary)
                            }
                        }
                    }
                }
            }
            .presentationCompactAdaptation(.popover)
            .presentationBackground(.clear)
        }
    }

    private func sideIcon(_ side: SetSide) -> String {
        switch side {
        case .both: return "person.2"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
    }

    private func modeMenu(_ modes: [ResistanceMode]) -> some View {
        AppControlButton(
            systemImage: modeIcon(mode),
            label: "How: \(Resistance.modeLabel(mode))"
        ) {
            Haptics.trigger(.selection)
            modeMenuOpen = true
        }
        .popover(isPresented: $modeMenuOpen, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            AppMenuSurface(dismiss: { modeMenuOpen = false }) {
                ForEach(modes, id: \.self) { candidate in
                    Button {
                        modeMenuOpen = false
                        changeMode(candidate)
                    } label: {
                        HStack(spacing: 10) {
                            Label(
                                Resistance.modeLabel(candidate),
                                systemImage: modeIcon(candidate)
                            )
                            Spacer(minLength: 12)
                            if mode == candidate {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.primary)
                            }
                        }
                    }
                }
            }
            .presentationCompactAdaptation(.popover)
            .presentationBackground(.clear)
        }
    }

    private func modeIcon(_ mode: ResistanceMode) -> String {
        switch mode {
        case .externalLoad: return "scalemass"
        case .assistance: return "arrow.down.to.line"
        case .bodyweight: return "figure.stand"
        case .bandResistance: return "oval"
        case .unknown: return "questionmark"
        }
    }

    private var submitLabel: String {
        guard let draft else { return "Log set" }
        if let selectedSet {
            return selectedSet.setType == .warmup
                ? "Log warm-up"
                : "Log set \(setNumber(selectedSet, in: draft))"
        }
        return "Log set \(draft.sets.filter { $0.setType != .warmup }.count + 1)"
    }

    /// "W" for a warm-up, otherwise the set's place among the sets that count:
    /// warm-ups ramp up to the work, they are not part of it.
    private func setNumber(_ set: PersistedActiveSetDraft, in draft: PersistedActiveExerciseDraft) -> String {
        guard set.setType != .warmup else { return "W" }
        let counted = draft.sets.filter { $0.setType != .warmup }
        return "\((counted.firstIndex { $0.id == set.id } ?? counted.count) + 1)"
    }

    private func setTitle(_ set: PersistedActiveSetDraft, in draft: PersistedActiveExerciseDraft) -> String {
        set.setType == .warmup ? "Warm-up" : "Set \(setNumber(set, in: draft))"
    }

    private func plannedLoad(_ set: PersistedActiveSetDraft) -> String {
        guard let target = set.target, Resistance.isMeasuredInKg(target.resistance.type),
              target.resistance.kg != nil
        else { return "—" }
        return Resistance.format(target.resistance)
    }

    /// A set with no load the engine could name: the person finds it.
    private func isCalibrating(_ target: PersistedSetTarget) -> Bool {
        Resistance.isMeasuredInKg(target.resistance.type) && target.resistance.kg == nil
    }

    /// What a set row says to VoiceOver: what was done, or what is asked.
    private func rowDescription(_ set: PersistedActiveSetDraft) -> String {
        if let observation = set.observation, observation.completed {
            var parts: [String] = []
            if let resistance = observation.resistance { parts.append(Resistance.format(resistance)) }
            if let reps = observation.reps { parts.append("\(Num.trimmed(reps)) reps") }
            parts.append(observation.rir.map { "\(Num.trimmed($0)) reps left" } ?? "reps left not recorded")
            return "Done. " + parts.joined(separator: ", ")
        }
        var parts = ["Planned"]
        let load = plannedLoad(set)
        if load != "—" { parts.append(load) }
        parts.append("\(plannedReps(set)) reps")
        if let rir = set.target?.rir { parts.append("stop with \(Num.trimmed(rir)) left") }
        return parts.joined(separator: ", ")
    }

    private func plannedReps(_ set: PersistedActiveSetDraft) -> String {
        set.target?.reps.label ?? "—"
    }

    private var resolvedSubmitLabel: String {
        guard Resistance.isMeasuredInKg(mode), kilograms == nil else { return submitLabel }
        return "Dial in the \(mode == .assistance ? "assistance" : "load")"
    }

    private func targetSummary(_ target: PersistedSetTarget) -> String {
        let reps = target.reps.label
        let load = Resistance.isMeasuredInKg(target.resistance.type) && target.resistance.kg != nil
            ? " · \(Resistance.format(target.resistance))"
            : ""
        return "\(reps) reps · stop with \(Num.trimmed(target.rir)) left\(load)"
    }

    private func loadCurrent() {
        guard let exercise else { return }
        let set = selectedSet
        if let observation = set?.observation, observation.completed {
            let resistance = observation.resistance ?? .unknown
            mode = resistance.type
            stationContext = Resistance.recordedLoadContext(
                for: exercise,
                resistance: resistance,
                settings: store.trainingRecords.data.settings,
                equipmentIncrementKg: store.filters.equipmentLoadIncrements[exercise.equipment]
            )
            kilograms = Resistance.isMeasuredInKg(mode) ? (resistance.kg ?? 0) : nil
            reps = observation.reps ?? 10
            rir = observation.rir
            side = set?.side ?? .both
            return
        }

        let defaults = defaultEditorValue(for: exercise)
        mode = defaults.mode
        stationContext = defaults.context
        let targetLoad = set?.target.flatMap {
            Resistance.carryOverLoad($0.resistance, defaults.mode, defaults.context)
        }
        kilograms = Resistance.isMeasuredInKg(defaults.mode)
            ? (targetLoad ?? defaults.kg ?? 0)
            : nil
        reps = set?.target?.reps.max ?? defaults.reps
        // Effort is what the person says it was, never the target filled in
        // for them: an unanswered set stays unknown, and progression treats
        // it as unknown.
        rir = nil
        side = set?.side ?? defaults.side
    }

    private func stepLoad(_ direction: Int) {
        guard let context else { return }
        if let kilograms {
            self.kilograms = Resistance.stepLoad(kilograms, direction, context.grid)
        } else if direction > 0 {
            kilograms = Resistance.firstLoad(context.grid)
        }
    }

    private func save() {
        guard let draft, let context else { return }
        if Resistance.isMeasuredInKg(mode), kilograms == nil { return }
        let observation = PersistedSetObservation(
            reps: reps,
            resistance: Resistance.makeResistance(mode, kilograms ?? 0, context),
            rir: rir,
            completed: true,
            timestamp: ISOTime.now()
        )
        do {
            if let set = selectedSet {
                if set.side != side {
                    try store.trainingRecords.updateSetDetails(
                        exerciseEntryId: draft.id,
                        setDraftId: set.id,
                        setType: set.setType,
                        side: side
                    )
                }
                try store.trainingRecords.recordSet(
                    exerciseEntryId: draft.id,
                    setDraftId: set.id,
                    observation: observation
                )
            } else {
                _ = try store.trainingRecords.addUnplannedSet(
                    exerciseEntryId: draft.id,
                    setType: .working,
                    side: side,
                    observation: observation
                )
            }
            closeEditor()
            // The set's own sound covers the rest starting.
            WorkoutAudio.play(.setLogged)
            store.activeWorkout.startRest(seconds: restSeconds, exerciseName: exercise?.name, announce: false)
            issue = nil
        } catch { capture(error) }
    }

    private func addExtraSet() {
        guard let draft else { return }
        do {
            let setId = try store.trainingRecords.addUnplannedSet(
                exerciseEntryId: draft.id,
                setType: .working,
                side: side
            )
            selectedSetId = setId
            issue = nil
            Haptics.trigger(.selection)
        } catch { capture(error) }
    }

    private func discard() {
        guard let draft, let set = selectedSet else { return }
        do {
            try store.trainingRecords.discardLoggedSet(
                exerciseEntryId: draft.id,
                setDraftId: set.id
            )
            closeEditor()
            issue = nil
        } catch { capture(error) }
    }

    private struct EditorValue {
        var mode: ResistanceMode
        var context: StationContext
        var kg: Double?
        var reps: Double
        var rir: Double?
        var side: SetSide
    }

    private func loadContext(for exercise: ExerciseSummary, mode: ResistanceMode) -> StationContext {
        Resistance.resolveLoadContext(
            for: exercise,
            mode: mode,
            settings: store.trainingRecords.data.settings,
            equipmentIncrementKg: store.filters.equipmentLoadIncrements[exercise.equipment]
        )
    }

    private func defaultEditorValue(for exercise: ExerciseSummary) -> EditorValue {
        let defaultMode = Resistance.modes(for: exercise).first ?? .externalLoad
        let defaultContext = loadContext(for: exercise, mode: defaultMode)
        let planned = draft?.sets.first { $0.target != nil }?.target
        let previous = draft?.sets.reversed().first { $0.observation?.completed == true }?.observation
        let engine = draft.flatMap {
            TrainingWorkflow.nextPerformance(
                $0,
                data: store.trainingRecords.data,
                increments: store.filters.equipmentLoadIncrements,
                loggedMode: defaultMode,
                loggedContext: Resistance.isMeasuredInKg(defaultMode) ? defaultContext : nil
            )
        }
        let engineLoad: Double? = {
            guard let engine,
                  engine.resistance.type == defaultMode,
                  Resistance.sameLoadContext(
                    engine.resistance.stationId, engine.resistance.basis,
                    defaultContext.stationId, defaultContext.basis
                  )
            else { return nil }
            return engine.resistance.kg
        }()

        return EditorValue(
            mode: defaultMode,
            context: defaultContext,
            kg: previous.flatMap { Resistance.carryOverLoad($0.resistance, defaultMode, defaultContext) }
                ?? engineLoad
                ?? (Resistance.isMeasuredInKg(defaultMode) ? 0 : nil),
            reps: previous?.reps ?? engine?.targetReps.max ?? planned?.reps.max ?? 10,
            rir: nil,
            side: .both
        )
    }

    private func changeMode(_ nextMode: ResistanceMode) {
        guard nextMode != mode, let exercise else { return }
        let nextContext = loadContext(for: exercise, mode: nextMode)
        mode = nextMode
        stationContext = nextContext
        kilograms = carriedLoad(mode: nextMode, context: nextContext)
            ?? (Resistance.isMeasuredInKg(nextMode) ? 0 : nil)
    }

    private func carriedLoad(mode: ResistanceMode, context: StationContext) -> Double? {
        if let draft {
            for set in draft.sets.reversed() where set.observation?.completed == true {
                if let load = Resistance.carryOverLoad(set.observation?.resistance, mode, context) {
                    return load
                }
            }
            if let next = TrainingWorkflow.nextPerformance(
                draft,
                data: store.trainingRecords.data,
                increments: store.filters.equipmentLoadIncrements,
                loggedMode: mode,
                loggedContext: Resistance.isMeasuredInKg(mode) ? context : nil
            ), next.action != .calibrate {
                return Resistance.carryOverLoad(next.resistance, mode, context)
            }
        }
        return nil
    }

    private func previousComparableKg(_ recommendation: ProgressionRecommendation) -> Double? {
        guard let previous = lastPerformedSet(),
              let previousKg = previous.resistance.kg,
              previous.resistance.stationId == recommendation.resistance.stationId,
              previous.resistance.basis == recommendation.resistance.basis
        else { return nil }
        return previousKg
    }

    private func lastPerformedSet() -> CompletedSet? {
        for session in store.trainingRecords.data.sessions.reversed() {
            for exercise in session.exercises.reversed() where exercise.exerciseId == exerciseId {
                if let set = exercise.sets.last { return set }
            }
        }
        return nil
    }

    /// A suggestion is labelled as one: the load is what RAUTA suggests for
    /// today, worked out from what was recorded last time.
    private func progressionText(_ note: ProgressionNote) -> String {
        guard let kg = note.kg else { return note.text }
        let each = note.basis == .perImplement ? " each" : ""
        return "Suggested today: \(Resistance.formatKg(kg)) kg\(each). \(note.text)"
    }

    private func closeEditor() {
        selectedSetId = nil
        stationContext = nil
        loadCurrent()
    }

    private func capture(_ error: Error) {
        issue = (error as? TrainingPersistenceError)?.message ?? error.localizedDescription
        Haptics.trigger(.warning)
    }
}
