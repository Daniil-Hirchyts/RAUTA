import Foundation
import Testing
@testable import Rauta

@Suite("Persistence validation and storage", .serialized)
struct PersistenceTests {
    @Test func emptyStateIsValid() {
        #expect(PersistenceValidation.validate(PersistedTrainingState.empty()).isEmpty)
    }

    @Test func emptyStateSurvivesASerializationRoundTrip() throws {
        let tree = PersistedTrainingState.empty().jsonTree
        let parsed = try #require(JSONCoding.parse(tree.canonical))
        let recovered = PersistenceValidation.recover(parsed)
        #expect(recovered.issues.isEmpty)
        #expect(recovered.state == PersistedTrainingState.empty())
    }

    @Test func garbageRecoversToAValidState() {
        let recovered = PersistenceValidation.recover(.string("not a training state"))
        #expect(!recovered.issues.isEmpty)
        #expect(PersistenceValidation.validate(recovered.state).isEmpty)
    }

    @Test(arguments: [
        "2026-01-02T03:04:05.678Z",
        "2026-12-31T23:59:59.000Z",
    ])
    func canonicalInstantsRoundTrip(_ iso: String) throws {
        let millis = try #require(ISOTime.parse(iso))
        #expect(ISOTime.string(fromMillis: millis) == iso)
        #expect(ISOTime.valid(iso))
    }

    @Test func instantsWithoutFractionsAndCalendarDaysParse() {
        #expect(ISOTime.parse("2026-01-02T03:04:05Z") == ISOTime.parse("2026-01-02T03:04:05.000Z"))
        #expect(ISOTime.parse("2026-01-02") == ISOTime.parse("2026-01-02T00:00:00.000Z"))
        #expect(ISOTime.parse("yesterday") == nil)
        #expect(ISOTime.valid("2026-01-02") == false)
    }

    /// Training history moved from user defaults into a file: the first read
    /// on the new build moves it, and the old key is removed only once the
    /// file holds it.
    @Test func trainingHistoryMigratesOutOfUserDefaults() throws {
        let suite = "rauta-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: suite, directoryHint: .isDirectory)
        let previousDefaults = Storage.defaults
        Storage.defaults = defaults
        Storage.directoryOverride = directory
        defer {
            Storage.defaults = previousDefaults
            Storage.directoryOverride = nil
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        let state = JSONValue.object(["data": PersistedTrainingState.empty().jsonTree])
        Storage.writeEnvelope("legacy-training", state: state, version: 3)
        #expect(defaults.string(forKey: "legacy-training") != nil)

        let migrated = try #require(Storage.readEnvelopeFile("training", migratingKey: "legacy-training"))
        #expect(migrated.version == 3)
        #expect(migrated.state == state)
        #expect(defaults.string(forKey: "legacy-training") == nil)
        #expect(FileManager.default.fileExists(atPath: Storage.fileURL("training").path()))

        // Later reads come from the file alone.
        let again = try #require(Storage.readEnvelopeFile("training", migratingKey: "legacy-training"))
        #expect(again.state == state)

        try Storage.writeEnvelopeFile("training", state: .object([:]), version: 4)
        #expect(Storage.readEnvelopeFile("training", migratingKey: "legacy-training")?.version == 4)
    }

    @Test func missingHistoryReadsAsNothing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "rauta-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        Storage.directoryOverride = directory
        defer { Storage.directoryOverride = nil }
        #expect(Storage.readEnvelopeFile("training", migratingKey: "rauta-tests-no-such-key") == nil)
    }
}

/// Closing a draft into history.
///
/// These are the writes a finish depends on. A refusal here used to be
/// swallowed, so the app could report a saved workout that history never
/// received — which is why the cases below are about what a refusal costs.
@Suite("Draft completion")
struct DraftCompletionTests {
    private func draft(
        startedAt: String,
        setTimestamp: String
    ) -> PersistedActiveWorkoutDraft {
        PersistedActiveWorkoutDraft(
            id: "draft-1",
            sourceWorkoutId: "workout-1",
            plannedProgramId: nil,
            plannedSessionId: nil,
            startedAt: startedAt,
            exercises: [
                PersistedActiveExerciseDraft(
                    id: "draft-exercise-1",
                    exerciseId: "0001",
                    plannedExerciseId: nil,
                    exerciseNameSnapshot: "Sit-up",
                    sets: [
                        PersistedActiveSetDraft(
                            id: "draft-set-1",
                            plannedSetId: nil,
                            setType: .working,
                            side: .both,
                            target: nil,
                            observation: PersistedSetObservation(
                                reps: 10,
                                resistance: ResistanceValue(type: .bodyweight),
                                rir: nil,
                                rpe: nil,
                                completed: true,
                                timestamp: setTimestamp
                            )
                        )
                    ]
                )
            ]
        )
    }

    private func complete(
        _ draft: PersistedActiveWorkoutDraft,
        at completedAt: String
    ) throws -> PersistedCompletedSession {
        var index = 0
        return try WorkoutDrafts.complete(
            draft,
            sessionId: "training-session-1",
            completedAt: completedAt,
            status: .completed,
            makeId: { kind in
                defer { index += 1 }
                return "\(kind.rawValue)-\(index)"
            }
        )
    }

    @Test func anOrdinarySessionKeepsItsDuration() throws {
        let session = try complete(
            draft(startedAt: "2026-09-21T17:00:00.000Z", setTimestamp: "2026-09-21T17:10:00.000Z"),
            at: "2026-09-21T18:00:00.000Z"
        )
        #expect(session.durationSeconds == 3_600)
    }

    /// A session left open overnight has a span, not a training duration — and
    /// the schema will not store one longer than a day. The work is recorded
    /// with the duration unknown rather than refused outright, which is what
    /// used to happen: the write failed, the failure was swallowed, and the
    /// sets never reached history.
    @Test func aSessionLeftOpenForDaysIsStillRecorded() throws {
        let draft = draft(
            startedAt: "2026-09-17T00:55:13.294Z",
            setTimestamp: "2026-09-21T18:49:00.000Z"
        )
        let session = try complete(draft, at: "2026-09-21T19:08:00.000Z")

        #expect(session.durationSeconds == nil)
        #expect(session.exercises.flatMap(\.sets).count == 1)
        // Raw timestamps are never rewritten to make the span fit.
        #expect(session.startedAt == "2026-09-17T00:55:13.294Z")
        #expect(session.completedAt == "2026-09-21T19:08:00.000Z")

        var state = PersistedTrainingState.empty()
        state.sessions = [session]
        #expect(PersistenceValidation.validate(state).isEmpty)
    }

    @Test func aDraftWithNoRecordedSetsRefusesToBecomeASession() {
        var empty = draft(
            startedAt: "2026-09-21T17:00:00.000Z",
            setTimestamp: "2026-09-21T17:10:00.000Z"
        )
        empty.exercises[0].sets[0].observation = nil
        #expect(throws: TrainingPersistenceError.self) {
            _ = try complete(empty, at: "2026-09-21T18:00:00.000Z")
        }
    }
}

/// A session from a replaced plan, trained anyway as a workout of its own.
@Suite("Detached from plan")
struct DetachedFromPlanTests {
    private func plannedDraft() -> PersistedActiveWorkoutDraft {
        func set(_ id: String, _ type: SetType, reps: Double) -> PersistedActiveSetDraft {
            PersistedActiveSetDraft(
                id: id,
                plannedSetId: "planned-\(id)",
                setType: type,
                side: .both,
                target: PersistedSetTarget(
                    reps: RepRange(min: reps, max: reps + 8),
                    rir: 3,
                    resistance: ResistanceValue(type: .bodyweight)
                ),
                observation: nil
            )
        }
        return PersistedActiveWorkoutDraft(
            id: "draft-1",
            sourceWorkoutId: "workout-1",
            plannedProgramId: "program-old",
            plannedSessionId: "session-old",
            startedAt: "2026-09-25T10:00:00.000Z",
            exercises: [
                PersistedActiveExerciseDraft(
                    id: "entry-push",
                    exerciseId: "push",
                    plannedExerciseId: "push",
                    exerciseNameSnapshot: "Push-up",
                    sets: [set("w", .warmup, reps: 5), set("a", .working, reps: 12), set("b", .working, reps: 12)]
                ),
                PersistedActiveExerciseDraft(
                    id: "entry-row",
                    exerciseId: "row",
                    plannedExerciseId: "row",
                    exerciseNameSnapshot: "Row",
                    sets: [set("c", .working, reps: 8)]
                ),
            ]
        )
    }

    @Test func thePrescriptionStaysAndThePlanGoes() {
        let detached = WorkoutDrafts.detachedFromPlan(
            plannedDraft(),
            exerciseIds: ["push", "row"],
            makeId: { "new-\($0.rawValue)" },
            exerciseNameSnapshot: nil
        )
        #expect(detached.plannedProgramId == nil)
        #expect(detached.plannedSessionId == nil)
        #expect(detached.exercises.allSatisfy { $0.plannedExerciseId == nil })
        let sets = detached.exercises.flatMap(\.sets)
        #expect(sets.allSatisfy { $0.plannedSetId == nil })
        // Warm-up, working sets and targets are all still there.
        #expect(detached.exercises[0].sets.map(\.setType) == [.warmup, .working, .working])
        #expect(sets.allSatisfy { $0.target != nil })
    }

    /// The workout's own list decides what is trained, in its order.
    @Test func theWorkoutsExercisesDecideTheOrder() {
        let detached = WorkoutDrafts.detachedFromPlan(
            plannedDraft(),
            exerciseIds: ["row", "squat"],
            makeId: { "new-\($0.rawValue)" },
            exerciseNameSnapshot: { $0 == "squat" ? "Squat" : nil }
        )
        #expect(detached.exercises.map(\.exerciseId) == ["row", "squat"])
        #expect(detached.exercises[0].sets.count == 1)
        #expect(detached.exercises[1].sets.isEmpty)
        #expect(detached.exercises[1].exerciseNameSnapshot == "Squat")
    }
}
