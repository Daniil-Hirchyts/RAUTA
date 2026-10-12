import Foundation
import Testing
@testable import Rauta

/// The coaching features — the next workout, the week ahead, adjusting this
/// one and looking back on it — and the honesty rules under them: unknown
/// effort stays unknown, missing history is said, nothing is kept unasked.
@Suite("Coaching", .serialized)
@MainActor
struct CoachingTests {
    // MARK: Fixtures

    static func workout(
        _ id: String, date: String, createdAt: String = "2026-10-01T08:00:00.000Z",
        completed: Bool = false, planned: PlannedWorkoutReference? = nil, exercises: [String] = ["0662"]
    ) -> Workout {
        Workout(
            id: id, name: id.capitalized, date: date, exerciseIds: exercises,
            completion: completed ? WorkoutCompletion(
                startedAt: "\(date)T09:00:00.000Z", completedAt: "\(date)T10:00:00.000Z",
                durationMs: 3_600_000, completedExerciseIds: exercises, activeCalories: 0,
                healthSyncStatus: .notRequested
            ) : nil,
            createdAt: createdAt, updatedAt: createdAt, planned: planned
        )
    }

    // MARK: Start dates

    @Test func startTodayPutsTheFirstSessionTodayAndKeepsTheWeeklyCount() {
        // Saturday 10 October 2026, training Monday, Wednesday and Friday.
        let dates = PlanStart.today.dates(trainingDays: [1, 3, 5], today: "2026-10-10")
        #expect(dates == ["2026-10-10", "2026-10-12", "2026-10-14"])
        #expect(PlanStart.isoWeekday("2026-10-10") == 6)
        #expect(PlanStart.isoWeekday("2026-10-11") == 7)
        #expect(PlanStart.isoWeekday("2026-10-12") == 1)
    }

    @Test func startNextWeekFollowsTheLocalesFirstDayOfTheWeek() {
        // Monday-first (most of Europe) and Sunday-first (US) agree on weekdays…
        #expect(PlanStart.nextWeek.dates(trainingDays: [1, 3, 5], today: "2026-10-10", firstWeekday: 2)
            == ["2026-10-12", "2026-10-14", "2026-10-16"])
        #expect(PlanStart.nextWeek.dates(trainingDays: [1, 3, 5], today: "2026-10-10", firstWeekday: 1)
            == ["2026-10-12", "2026-10-14", "2026-10-16"])
        // …but a Sunday session belongs to a different "next week" in each.
        #expect(PlanStart.nextWeek.dates(trainingDays: [7], today: "2026-10-10", firstWeekday: 2) == ["2026-10-18"])
        #expect(PlanStart.nextWeek.dates(trainingDays: [7], today: "2026-10-10", firstWeekday: 1) == ["2026-10-11"])
        // On the week's first day, "next week" is a week away, never today.
        #expect(PlanStart.startOfNextWeek(after: "2026-10-12", firstWeekday: 2) == "2026-10-19")
        // Across a month and a year end.
        #expect(PlanStart.nextWeek.dates(trainingDays: [1], today: "2026-12-30", firstWeekday: 2) == ["2027-01-04"])
    }

    // MARK: The next workout

    @Test func theTodayCardPicksResumeStartRestPlanFinishedOrStarter() {
        let records = PersistedTrainingState.empty()
        let wednesday = "2026-10-14"

        var next = NextWorkout.resolve(workouts: [], records: records, activeWorkoutId: nil, today: wednesday)
        #expect(next.state == .noPlan)

        let today = Self.workout("push", date: wednesday)
        next = NextWorkout.resolve(workouts: [today], records: records, activeWorkoutId: nil, today: wednesday)
        #expect(next.state == .today(today))

        next = NextWorkout.resolve(workouts: [today], records: records, activeWorkoutId: "push", today: wednesday)
        #expect(next.state == .running(today))

        let done = Self.workout("done", date: wednesday, completed: true)
        let friday = Self.workout("legs", date: "2026-10-16")
        next = NextWorkout.resolve(workouts: [done, friday], records: records, activeWorkoutId: nil, today: wednesday)
        #expect(next.state == .doneToday(next: friday))

        next = NextWorkout.resolve(workouts: [friday], records: records, activeWorkoutId: nil, today: wednesday)
        #expect(next.state == .restDay(next: friday))

        // A planned Monday that didn't happen is offered a way back in.
        let monday = Self.workout("monday", date: "2026-10-12")
        next = NextWorkout.resolve(workouts: [monday, friday], records: records, activeWorkoutId: nil, today: wednesday)
        #expect(next.missed.map(\.id) == ["monday"])

        var withPlan = records
        withPlan.activeProgramId = "program-x"
        next = NextWorkout.resolve(workouts: [], records: withPlan, activeWorkoutId: nil, today: wednesday)
        #expect(next.state == .planFinished)
    }

    @Test func plannedRestDaysAreRestNotMisses() {
        let workouts = [
            Self.workout("mon", date: "2026-10-12", completed: true),
            Self.workout("wed", date: "2026-10-14"),
            Self.workout("fri", date: "2026-10-16"),
            // Started and trained the same day it was made: an extra session.
            Self.workout("extra", date: "2026-10-13", createdAt: "2026-10-13T07:00:00.000Z", completed: true),
        ]
        let week = WeekProgress.build(
            monday: "2026-10-12", today: "2026-10-15", workouts: workouts,
            records: .empty(), activeWorkoutId: nil
        )
        #expect(week.planned == 3)
        #expect(week.completedPlanned == 1)
        #expect(week.extra == 1)
        #expect(week.missed.map(\.id) == ["wed"])
        #expect(week.remaining.map(\.id) == ["fri"])
        #expect(week.days.map(\.status) == [.done, .done, .missed, .rest, .planned, .rest, .rest])
        #expect(week.summary == "1 of 3 planned + 1 extra")
    }

    // MARK: Weekly review

    static func session(_ id: String, at: String, exerciseId: String, reps: Double, kg: Double?, rir: Double?) -> CompletedSession {
        CompletedSession(
            id: id, plannedSessionId: nil, startedAt: at, completedAt: at, durationSeconds: 3_000, status: .completed,
            exercises: [CompletedExercise(exerciseId: exerciseId, sets: (1...3).map { number in
                CompletedSet(
                    id: "\(id)-\(number)", plannedSetId: nil, reps: reps,
                    resistance: kg.map { .load($0, basis: .total, stationId: "rack") } ?? .bodyweight,
                    rir: rir, rpe: nil, completed: true, setType: .working, side: .both, timestamp: at
                )
            })]
        )
    }

    static func review(history: TrainingHistory, workouts: [Workout], today: String = "2026-10-15") -> WeeklyReview {
        let week = WeekProgress.build(monday: "2026-10-12", today: today, workouts: workouts, records: .empty(), activeWorkoutId: nil)
        let next = NextWorkout.resolve(workouts: workouts, records: .empty(), activeWorkoutId: nil, today: today)
        return WeeklyReview.build(week: week, history: history, next: next, hasPlan: false, today: today)
    }

    @Test func anEmptyReviewSaysThereIsNothingYetAndOffersAPlan() {
        let review = Self.review(history: .empty, workouts: [])
        #expect(review.isEmpty)
        #expect(review.changes.isEmpty)
        #expect(review.dataNotes.first?.contains("No workouts logged yet") == true)
        #expect(review.next.kind == .buildPlan)
    }

    @Test func aSparseReviewSaysComparisonsNeedASecondSession() {
        let history = TrainingHistory(
            sessions: [Self.session("a", at: "2026-10-13T10:00:00.000Z", exerciseId: "0662", reps: 10, kg: nil, rir: nil)],
            coverage: .unknown, coverageStart: nil
        )
        let review = Self.review(history: history, workouts: [Self.workout("a", date: "2026-10-13", completed: true)])
        #expect(!review.isEmpty)
        #expect(review.changes.isEmpty)
        #expect(review.dataNotes.contains { $0.contains("new to your log") })
        #expect(review.dataNotes.contains { $0.contains("Reps left was recorded on 0 of 3") })
    }

    @Test func aFullReviewComparesLikeForLikeAndLabelsEstimates() throws {
        let squat = TrainingEngineTests.loadedExercise.id
        let history = TrainingHistory(
            sessions: [
                Self.session("before", at: "2026-10-06T10:00:00.000Z", exerciseId: squat, reps: 8, kg: 60, rir: 2),
                Self.session("this", at: "2026-10-13T10:00:00.000Z", exerciseId: squat, reps: 8, kg: 62.5, rir: 2),
                Self.session("pushups-1", at: "2026-10-07T10:00:00.000Z", exerciseId: "0662", reps: 10, kg: nil, rir: nil),
                Self.session("pushups-2", at: "2026-10-14T10:00:00.000Z", exerciseId: "0662", reps: 12, kg: nil, rir: nil),
            ],
            coverage: .complete, coverageStart: "2026-09-01T00:00:00.000Z"
        )
        let workouts = [
            Self.workout("this", date: "2026-10-13", completed: true),
            Self.workout("pushups-2", date: "2026-10-14", completed: true),
        ]
        let review = Self.review(history: history, workouts: workouts)
        let loaded = try #require(review.changes.first { $0.exerciseId == squat })
        #expect(loaded.direction == .up)
        #expect(loaded.text.contains("60 → 62.5 kg"))
        #expect(loaded.estimate?.contains("an estimate") == true, "Estimated 1RM is labelled as an estimate")
        let bodyweight = try #require(review.changes.first { $0.exerciseId == "0662" })
        #expect(bodyweight.text == "Best set 10 → 12 reps.")
        #expect(bodyweight.estimate == nil, "No estimate without a load and recorded effort")
        #expect(review.consistency.first == "You completed 2 of 2 planned sessions so far.")
    }

    @Test func differentEquipmentIsNeverComparedAsProgress() {
        let then = TrainingEngineTests.set(reps: 8, kg: 60, rir: 2)
        var now = TrainingEngineTests.set(reps: 8, kg: 80, rir: 2)
        now.resistance = .load(80, basis: .total, stationId: "machine")
        #expect(WeeklyReview.compare("0001", now, then) == nil)
    }

    // MARK: Missing evidence

    @Test func unrecordedEffortHoldsTheLoadInsteadOfGuessing() {
        let id = TrainingEngineTests.loadedExercise.id
        func logged(_ name: String, day: Int, rir: Double?) -> CompletedSession {
            var session = TrainingEngineTests.loggedSession(name, day: day, exerciseId: id, reps: 12, kg: 60, rir: 2)
            for index in session.exercises[0].sets.indices { session.exercises[0].sets[index].rir = rir }
            return session
        }
        let unknown = TrainingHistory(sessions: [logged("a", day: -2, rir: nil)], coverage: .complete, coverageStart: nil)
        let held = TrainingEngineTests.progression(history: unknown)
        #expect(held.action == .hold)
        #expect(held.reasons == [.missingEffort])
        #expect(held.resistance.kg == 60, "The last recorded load is kept, not raised on a guess")
        #expect(ProgressionNotes.note(held)?.text.contains("Reps left wasn't recorded") == true)

        let known = TrainingHistory(sessions: [logged("a", day: -2, rir: 2)], coverage: .complete, coverageStart: nil)
        #expect(TrainingEngineTests.progression(history: known).action == .increaseLoad)

        let none = TrainingEngineTests.progression(history: .empty)
        #expect(none.action == .calibrate)
        #expect(none.resistance.kg == nil, "No history: a calibration, never an invented number")
    }

    @Test func nextWeekEvidenceSaysHowMuchWasLogged() {
        let weekStart = "2026-10-05T00:00:00.000Z"
        let lastWeek = [PlannedSession(id: "s1", scheduledAt: weekStart, focus: [], exercises: [],
                                       duration: SessionTiming.estimateSession([], TrainingWorkflow.trainingIndex(), DEFAULT_POLICY))]
        let nothing = CoachingPlanner.evidenceNotes(lastWeek, weekStart: weekStart, history: .empty)
        #expect(nothing.first?.contains("None of last week's planned sessions were logged") == true)

        let history = TrainingHistory(
            sessions: [Self.session("a", at: "2026-10-06T10:00:00.000Z", exerciseId: "0662", reps: 10, kg: nil, rir: nil)],
            coverage: .unknown, coverageStart: nil
        )
        let some = CoachingPlanner.evidenceNotes(lastWeek, weekStart: weekStart, history: history)
        #expect(some.first?.contains("Built on the 1 session you logged") == true)
        #expect(some.contains { $0.contains("Reps left was recorded on 0 of 3") })
    }

    // MARK: Adapting a week (engine)

    static func adaptation(
        minutes: Double = 60,
        equipment: [String]? = nil,
        nowOffsetDays: Double = 3
    ) throws -> (program: TrainingProgram, adapted: ProgramGenerationResult, request: ProgramGenerationRequest) {
        var request = TrainingEngineTests.request(goal: .generalFitness, equipment: equipment, days: [0, 2, 4], minutes: 70)
        let program = try #require(Generate.generateTrainingProgram(request).program)
        // Wednesday morning: Monday's and Wednesday's sessions have passed
        // untrained, Friday's is still ahead.
        request.now = ISOTime.addDays(TrainingEngineTests.weekStart, nowOffsetDays)
        request.schedule.days = [4]
        request.policy = program.policy
        request.preferences.maxSessionDurationMinutes = minutes
        let adapted = Adapt.adaptTrainingProgram(AdaptationRequest(previousProgram: program, request: request, mode: .remainingWeek))
        return (program, adapted, request)
    }

    @Test func missedWorkMovesIntoTheRestOfTheWeekWhereItFits() throws {
        let (program, result, request) = try Self.adaptation()
        let adapted = try #require(result.program, "\(result.issues)")
        let source = try #require(program.weeks.first)
        let friday = try #require(source.sessions.last)
        let after = try #require(adapted.weeks.first?.sessions.first)
        let missedIds = Set(source.sessions.dropLast().flatMap { $0.exercises.map(\.exerciseId) })
        let moved = after.exercises.filter { exercise in
            missedIds.contains(exercise.exerciseId) && !friday.exercises.contains { $0.exerciseId == exercise.exerciseId }
        }
        // Either some of the missed work fits into Friday, or the plan says
        // what was dropped — never silence.
        #expect(!moved.isEmpty || result.issues.contains { $0.code == .missedVolumeDropped })
        #expect(after.duration.totalSeconds <= request.preferences.maxSessionDurationMinutes * 60)
        #expect(after.exercises.count <= adapted.policy.maxExercisesPerSession)
    }

    @Test func shorterSessionsStayInsideTheNewLimit() throws {
        let (_, result, _) = try Self.adaptation(minutes: 30)
        let adapted = try #require(result.program, "\(result.issues)")
        for session in adapted.weeks.flatMap(\.sessions) {
            #expect(session.duration.totalSeconds <= 30 * 60)
            #expect(!session.exercises.isEmpty)
        }
    }

    @Test func unavailableEquipmentIsSwappedOutOfTheRestOfTheWeek() throws {
        let all = TrainingEngineTests.allEquipment
        let without = all.filter { $0 != "dumbbell" && $0 != "barbell" }
        let (_, result, request) = try Self.adaptation(equipment: without)
        let adapted = try #require(result.program, "\(result.issues)")
        let index = TrainingWorkflow.trainingIndex()
        for exercise in adapted.weeks.flatMap(\.sessions).flatMap(\.exercises) {
            let needs = index.byId[exercise.exerciseId]?.metadata.requiredEquipment ?? []
            #expect(needs.allSatisfy { $0 == "body weight" || request.preferences.availableEquipment.contains($0) },
                    "\(exercise.exerciseId) needs \(needs)")
        }
    }

    // MARK: Keeping and undoing (stores)

    @Test func nextWeekIsReviewedThenKeptThenUndoneWithoutTouchingHistory() async throws {
        try await IsolatedStores.run {
            try await IsolatedStores.finishWorkout()
            let history = TrainingRecordsStore.shared.data.sessions
            #expect(history.count == 1)

            // A first plan, then the week after it.
            let first = PlanStart.nextWeek.dates(trainingDays: [1, 3, 5], firstWeekday: 2)
            guard case .created? = await TrainingPlan.createTrainingPlanForDates(dates: first) else {
                Issue.record("No first plan"); return
            }
            let workoutsBefore = WorkoutsStore.shared.workouts
            let recordsBefore = TrainingRecordsStore.shared.data
            let firstPlanId = try #require(recordsBefore.activeProgramId)
            let dates = CoachingPlanner.nextWeekDates(.nextWeek, trainingDays: [1, 3, 5])
            #expect(dates.first.map(WeekProgress.mondayOf) == first.first.map { CalendarDate.shift(WeekProgress.mondayOf($0), by: 7) })

            let proposal = try await CoachingPlanner.previewNextWeek(dates: dates)
            #expect(WorkoutsStore.shared.workouts == workoutsBefore, "A preview saves nothing")
            #expect(!proposal.changes.isEmpty)
            #expect(proposal.notes.contains { $0.contains("None of last week's planned sessions were logged") })

            let undo = try CoachingPlanner.apply(proposal)
            let data = TrainingRecordsStore.shared.data
            #expect(data.sessions == history, "Completed sessions are untouched")
            let active = try #require(TrainingPlan.activeProgramRecord())
            #expect(active.snapshot.weeks.count == 2, "The first week is carried over, the new one added")
            let planned = WorkoutsStore.shared.workouts.filter { $0.planned?.programId == active.id }
            #expect(Set(planned.map(\.date)) == Set(first + dates))
            #expect(PersistenceValidation.validate(data).isEmpty)
            for old in workoutsBefore where old.planned != nil && old.planned?.programId != firstPlanId {
                #expect(WorkoutsStore.shared.workout(old.id) == old)
            }
            // Every carried workout keeps its id; the trained one-off, from
            // a program of its own, is left exactly as it was.
            for old in workoutsBefore where old.planned?.programId == firstPlanId {
                #expect(WorkoutsStore.shared.workout(old.id)?.planned?.programId == active.id)
            }

            try CoachingPlanner.undo(undo)
            #expect(TrainingRecordsStore.shared.data == recordsBefore)
            #expect(WorkoutsStore.shared.workouts == workoutsBefore)
        }
    }

    @Test func aStaleProposalIsRefusedRatherThanApplied() async throws {
        try await IsolatedStores.run {
            let first = PlanStart.nextWeek.dates(trainingDays: [1, 3, 5], firstWeekday: 2)
            guard case .created? = await TrainingPlan.createTrainingPlanForDates(dates: first) else {
                Issue.record("No first plan"); return
            }
            let proposal = try await CoachingPlanner.previewNextWeek(dates: CoachingPlanner.nextWeekDates(.nextWeek, trainingDays: [1, 3, 5]))
            // Something changes in between: the proposal no longer describes now.
            _ = WorkoutsStore.shared.createWorkout(name: "Extra", date: CalendarDate.today, exerciseIds: ["0662"])
            #expect(throws: (any Error).self) { try CoachingPlanner.apply(proposal) }
        }
    }

    @Test func movingAMissedWorkoutChangesOnlyThatWorkout() async throws {
        try await IsolatedStores.run {
            let other = WorkoutsStore.shared.createWorkout(name: "Other", date: CalendarDate.shift(CalendarDate.today, by: 3), exerciseIds: ["0662"])
            let id = WorkoutsStore.shared.createWorkout(name: "Missed", date: CalendarDate.shift(CalendarDate.today, by: -1), exerciseIds: ["0662"])
            let missed = try #require(WorkoutsStore.shared.workout(id))
            let target = try #require(CoachingPlanner.moveTargets(for: missed).first)
            #expect(target == CalendarDate.today)
            let proposal = CoachingPlanner.previewMove(missed, to: target)
            let otherBefore = WorkoutsStore.shared.workout(other)
            let undo = try CoachingPlanner.apply(proposal)
            #expect(WorkoutsStore.shared.workout(id)?.date == target)
            #expect(WorkoutsStore.shared.workout(other) == otherBefore)
            try CoachingPlanner.undo(undo)
            #expect(WorkoutsStore.shared.workout(id)?.date == missed.date)
        }
    }

    // MARK: The assistant without a model

    private func waitForTurn(_ agent: RautaAgent, after count: Int) async {
        for _ in 0..<200 {
            if agent.items.count > count + 1, agent.phase != .thinking, agent.phase != .working { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func recognisedRequestsWorkWithNoModelAndOthersSayWhatStillWorks() async throws {
        try await IsolatedStores.run {
            let agent = RautaAgent.shared
            let previous = RautaAgent.modelAvailable
            RautaAgent.modelAvailable = { false }
            defer {
                RautaAgent.modelAvailable = previous
                agent.startOver()
            }
            agent.startOver()
            _ = WorkoutsStore.shared.createWorkout(name: "Push", date: CalendarDate.shift(CalendarDate.today, by: 1), exerciseIds: ["0662"])

            agent.send("What's coming up?")
            await waitForTurn(agent, after: 0)
            #expect(!agent.items.contains { if case .card(.download) = $0.content { return true }; return false },
                    "A recognised request never asks for the download")
            #expect(agent.items.contains { if case .card(.sessions) = $0.content { return true }; return false })

            let before = agent.items.count
            agent.send("Write me a poem about squats")
            #expect(agent.items.count == before + 3)
            if case .rauta(let text) = agent.items[before + 1].content {
                #expect(text == RautaAgent.needsModel)
            } else { Issue.record("Expected RAUTA's explanation") }
            #expect({ if case .card(.download) = agent.items[before + 2].content { return true }; return false }())
        }
    }

    @Test func coachingRequestsAreReadWithoutTheModel() {
        let today = "2026-10-14"
        #expect(AgentIntent.parse("Plan my next week", today: today, running: false) == .nextWeek)
        #expect(AgentIntent.parse("How did my week go?", today: today, running: false) == .weeklyReview)
        #expect(AgentIntent.parse("I missed Monday's workout", today: today, running: false) == .missedSession)
        #expect(AgentIntent.parse("I only have 30 minutes this week", today: today, running: false) == .shortOnTime(minutes: 30))
        #expect(AgentIntent.parse("The bench isn't available this week", today: today, running: false) == .equipmentUnavailable)
        // A permanent change is still a change to the equipment list.
        #expect(AgentIntent.parse("I don't have a barbell", today: today, running: false) == .equipment)
        // Moving to next week is a move, not a new week.
        if case .reschedule? = AgentIntent.parse("Move Friday's workout to next week Monday", today: today, running: false) {} else {
            Issue.record("Expected a reschedule")
        }
        #expect(AgentToolHost.repsLeft(in: "Log 8 reps at 60 kg with 2 left") == 2)
        #expect(AgentToolHost.repsLeft(in: "log 10 reps rir 1") == 1)
        #expect(AgentToolHost.repsLeft(in: "log 10 reps at 40 kg") == nil)
    }
}
