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
        return Resistance.resolveLoadContext(
            for: exercise,
            mode: mode,
            settings: store.trainingRecords.data.settings,
            equipmentIncrementKg: store.filters.equipmentLoadIncrements[exercise.equipment]
        )
    }

    private var target: PersistedSetTarget? {
        draft?.sets.first { $0.setType == .working && $0.target != nil }?.target
            ?? draft?.sets.first { $0.target != nil }?.target
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

    private var activeSession: ActiveWorkoutSession? { store.activeWorkout.session }
    private var restUntil: Date? {
        activeSession?.restUntil.map { Date(timeIntervalSince1970: $0 / 1_000) }
    }
    private var setPhaseStartedAt: Date? {
        guard let session = activeSession else { return nil }
        let epochMs = session.setPhaseStartedAt ?? session.startedAt
        return Date(timeIntervalSince1970: epochMs / 1_000)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let target {
                Text(targetSummary(target))
                    .font(Theme.sans(11, weight: .bold))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
            if let progressionNote {
                Text(progressionText(progressionNote))
                    .font(Theme.sans(11))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            phaseTimer
        }
    }

    private var phaseTimer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = restUntil.map { $0.timeIntervalSince(context.date) } ?? -1
            let isResting = remaining > 0
            let elapsedAnchor = setPhaseStartedAt ?? context.date
            let seconds = isResting
                ? Int(remaining.rounded(.up))
                : max(0, Int(context.date.timeIntervalSince(elapsedAnchor).rounded(.down)))

            HStack(spacing: 5) {
                Text(isResting ? "REST" : "SET")
                    .font(Theme.sans(9, weight: .black))
                    .kerning(1.1)
                    .foregroundStyle(isResting ? Theme.primary : Theme.mutedForeground)
                Text(restClock(seconds))
                    .font(Theme.sans(11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.foreground)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.muted.opacity(0.6), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isResting ? "Rest timer" : "Current set timer")
            .accessibilityValue(restClock(seconds))
        }
    }

    private func setRows(_ draft: PersistedActiveExerciseDraft) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("").frame(width: 22, alignment: .leading)
                Text("Load").frame(maxWidth: .infinity, alignment: .leading)
                Text("Reps").frame(width: 44, alignment: .trailing)
                Text("RIR").frame(width: 44, alignment: .trailing)
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
                            HStack {
                                Text("\(index + 1)").frame(width: 22, alignment: .leading)
                                Text(set.observation?.resistance.map(Resistance.format) ?? "—")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(set.observation?.reps.map(Num.trimmed) ?? "—")
                                    .frame(width: 44, alignment: .trailing)
                                Text(set.observation?.rir.map(Num.trimmed) ?? "—")
                                    .frame(width: 44, alignment: .trailing)
                            }
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(set.observation?.completed == true ? Theme.foreground : Theme.mutedForeground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(
                                (selectedSet?.id == set.id ? Theme.primary : Theme.muted).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
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
                    canDecrement: reps > 1
                ) { direction in
                    reps = min(100, max(1, reps + Double(direction)))
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
                        Haptics.trigger(.success)
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
        if let selectedSet, let index = draft.sets.firstIndex(where: { $0.id == selectedSet.id }) {
            return "Save set \(index + 1)"
        }
        return "Log set \(draft.sets.count + 1)"
    }

    private var resolvedSubmitLabel: String {
        guard Resistance.isMeasuredInKg(mode), kilograms == nil else { return submitLabel }
        return "Dial in the \(mode == .assistance ? "assistance" : "load")"
    }

    private func targetSummary(_ target: PersistedSetTarget) -> String {
        let reps = target.reps.min == target.reps.max
            ? Num.trimmed(target.reps.max)
            : "\(Num.trimmed(target.reps.min))–\(Num.trimmed(target.reps.max))"
        let load = Resistance.isMeasuredInKg(target.resistance.type)
            ? " · \(Resistance.format(target.resistance))"
            : ""
        return "\(reps) reps · RIR \(Num.trimmed(target.rir))\(load)"
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
        rir = set?.target?.rir ?? defaults.rir
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
            store.activeWorkout.startRest(seconds: restSeconds, exerciseName: exercise?.name)
            issue = nil
            Haptics.trigger(.success)
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

    private func defaultEditorValue(for exercise: ExerciseSummary) -> EditorValue {
        let defaultMode = Resistance.modes(for: exercise).first ?? .externalLoad
        let defaultContext = Resistance.resolveLoadContext(
            for: exercise,
            mode: defaultMode,
            settings: store.trainingRecords.data.settings,
            equipmentIncrementKg: store.filters.equipmentLoadIncrements[exercise.equipment]
        )
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
            rir: previous?.rir ?? planned?.rir,
            side: .both
        )
    }

    private func changeMode(_ nextMode: ResistanceMode) {
        guard nextMode != mode, let exercise else { return }
        let nextContext = Resistance.resolveLoadContext(
            for: exercise,
            mode: nextMode,
            settings: store.trainingRecords.data.settings,
            equipmentIncrementKg: store.filters.equipmentLoadIncrements[exercise.equipment]
        )
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

    private func progressionText(_ note: ProgressionNote) -> String {
        guard let kg = note.kg else { return note.text }
        let each = note.basis == .perImplement ? " each" : ""
        return "\(Resistance.formatKg(kg)) kg\(each) · \(note.text)"
    }

    private func restClock(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
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
