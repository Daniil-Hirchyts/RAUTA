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

        Storage.writeEnvelopeFile("training", state: .object([:]), version: 4)
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
