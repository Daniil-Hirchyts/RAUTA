import Combine
import Foundation
import Observation
import UIKit

/// Keeps the compact JSON copy in iCloud's key-value store: preferences,
/// profile, favorites, equipment and the workout list. KVS survives uninstall,
/// follows the user's iCloud account and is available offline from the system
/// cache, but its whole allowance is 1 MB — so the structured training records,
/// which grow with every set, are not in it. Complete backups are files kept
/// by ``BackupVault``.
struct ICloudBackupRecord {
    var data: String
    var updatedAt: String
}

enum ICloudBackupStore {
    private static let store = NSUbiquitousKeyValueStore.default
    private static let dataKey = "gym-lib-backup-data"
    private static let updatedAtKey = "gym-lib-backup-updated-at"
    private static let maximumBackupBytes = 900_000

    static var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    static func read() -> ICloudBackupRecord? {
        store.synchronize()
        guard let data = store.string(forKey: dataKey),
              let updatedAt = store.string(forKey: updatedAtKey)
        else { return nil }
        return ICloudBackupRecord(data: data, updatedAt: updatedAt)
    }

    static func write(_ record: ICloudBackupRecord) throws {
        guard record.data.lengthOfBytes(using: .utf8) <= maximumBackupBytes else {
            throw TrainingPersistenceError(
                "Your workout list has outgrown iCloud's quick sync. Complete backups on this iPhone still include everything."
            )
        }
        store.set(record.data, forKey: dataKey)
        store.set(record.updatedAt, forKey: updatedAtKey)
        store.synchronize()
    }

    static let externalChange = NSUbiquitousKeyValueStore.didChangeExternallyNotification
}

@MainActor
@Observable
final class ICloudSync {
    static let shared = ICloudSync()

    enum Status: String {
        case checking, syncing, synced, unavailable, error
    }

    private(set) var status: Status = .checking
    private(set) var lastSyncedAt: String?
    private(set) var error: String?
    /// A copy from another device that arrived during a workout. It is applied
    /// once the workout ends, so nothing changes under a set being logged.
    private(set) var heldForWorkout: ICloudBackupRecord?

    private static let metaKey = "gym-lib-icloud-sync"
    private static let uploadDelay: TimeInterval = 0.9

    private var started = false
    private var available = false
    private var applyingCloudBackup = false
    private var lastIssuedTimestamp: Double = 0
    private var uploadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    private struct SyncMeta {
        var localChangedAt: String?
        var cloudUpdatedAt: String?
    }

    private func readMeta() -> SyncMeta {
        guard let text = Storage.readString(Self.metaKey),
              let object = JSONCoding.parse(text)?.objectValue
        else { return SyncMeta(localChangedAt: nil, cloudUpdatedAt: nil) }
        return SyncMeta(
            localChangedAt: object["localChangedAt"]?.stringValue,
            cloudUpdatedAt: object["cloudUpdatedAt"]?.stringValue
        )
    }

    private func writeMeta(_ meta: SyncMeta) {
        Storage.writeString(Self.metaKey, JSONValue.object([
            "localChangedAt": meta.localChangedAt.map(JSONValue.string) ?? .null,
            "cloudUpdatedAt": meta.cloudUpdatedAt.map(JSONValue.string) ?? .null,
        ]).canonical)
    }

    private func nextTimestamp() -> String {
        lastIssuedTimestamp = Swift.max(ActiveWorkout.nowMillis(), lastIssuedTimestamp + 1)
        return ISOTime.string(fromMillis: lastIssuedTimestamp)
    }

    private func report(_ error: Error) {
        status = .error
        self.error = (error as? TrainingPersistenceError)?.message
            ?? "Could not save this backup to iCloud."
    }

    @discardableResult
    private func uploadLocalData() -> Bool {
        guard available else { return false }
        uploadTask?.cancel()
        uploadTask = nil

        status = .syncing
        error = nil
        mergeNewerCloudWorkouts()
        let updatedAt = nextTimestamp()
        do {
            try ICloudBackupStore.write(ICloudBackupRecord(
                data: AppBackup.createBackup(createdAt: updatedAt),
                updatedAt: updatedAt
            ))
            writeMeta(SyncMeta(localChangedAt: updatedAt, cloudUpdatedAt: updatedAt))
            status = .synced
            lastSyncedAt = updatedAt
            error = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Another device uploaded since this one last synced: its workouts are
    /// merged in before this upload replaces its copy, so an upload can never
    /// drop a workout that exists only over there.
    private func mergeNewerCloudWorkouts() {
        guard let remote = ICloudBackupStore.read(),
              remote.updatedAt != readMeta().cloudUpdatedAt,
              let data = JSONCoding.parse(remote.data)?["data"]
        else { return }
        let theirs = WorkoutsStore.sanitize(data["workouts"])
        let mine = WorkoutsStore.PersistedWorkouts(
            workouts: WorkoutsStore.shared.workouts,
            deletions: WorkoutsStore.shared.deletions
        )
        let merged = WorkoutsStore.merge(
            local: mine, remote: theirs, runningId: ActiveWorkoutStore.shared.session?.workoutId
        )
        guard merged.workouts != mine.workouts || merged.deletions != mine.deletions else { return }
        applyingCloudBackup = true
        defer { applyingCloudBackup = false }
        WorkoutsStore.shared.replaceAll(merged)
    }

    private func restoreCloudData(_ record: ICloudBackupRecord) throws {
        if ActiveWorkoutStore.shared.session != nil {
            heldForWorkout = record
            return
        }
        heldForWorkout = nil
        applyingCloudBackup = true
        defer { applyingCloudBackup = false }
        // Merged, not swallowed: a workout this device added or finished since
        // the other device's copy was made stays, and one deleted on either
        // side stays deleted.
        try AppBackup.importBackup(record.data, keepingRunningWorkout: true, mergingWorkouts: true)
        writeMeta(SyncMeta(localChangedAt: record.updatedAt, cloudUpdatedAt: record.updatedAt))
        status = .synced
        lastSyncedAt = record.updatedAt
        error = nil
    }

    private func acceptExternalChange(_ record: ICloudBackupRecord) {
        let meta = readMeta()
        if let localChangedAt = meta.localChangedAt, record.updatedAt <= localChangedAt { return }
        do { try restoreCloudData(record) } catch { report(error) }
    }

    private func scheduleUpload() {
        guard available, !applyingCloudBackup else { return }
        let changedAt = nextTimestamp()
        var meta = readMeta()
        meta.localChangedAt = changedAt
        writeMeta(meta)
        // Every local edit lands here, and both values are published through the
        // app store: assigning what is already there would redraw every screen
        // for nothing — continuously, while a slider or colour picker is dragged.
        if status != .syncing { status = .syncing }
        if error != nil { error = nil }

        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.uploadDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.uploadTask = nil
                self?.uploadLocalData()
            }
        }
    }

    private func subscribeToLocalData() {
        let publishers: [AnyPublisher<Void, Never>] = [
            FavoritesStore.shared.changed.eraseToAnyPublisher(),
            FiltersStore.shared.changed.eraseToAnyPublisher(),
            SettingsStore.shared.changed.eraseToAnyPublisher(),
            TrainingProfileStore.shared.changed.eraseToAnyPublisher(),
            WorkoutsStore.shared.changed.eraseToAnyPublisher(),
        ]
        for publisher in publishers {
            publisher
                .sink { [weak self] in self?.scheduleUpload() }
                .store(in: &cancellables)
        }
    }

    /// Restores before first paint, then mirrors later data changes.
    func start() {
        guard !started else { return }
        started = true

        available = ICloudBackupStore.isAvailable
        guard available else {
            status = .unavailable
            error = nil
            return
        }

        // The store posts its change on a queue of its own; reading it is
        // main-actor work, so the notification is moved there first.
        NotificationCenter.default
            .publisher(for: ICloudBackupStore.externalChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let record = ICloudBackupStore.read() else { return }
                self?.acceptExternalChange(record)
            }
            .store(in: &cancellables)

        let remote = ICloudBackupStore.read()
        let meta = readMeta()
        let localChangedAt = meta.localChangedAt
        let meaningful = AppBackup.hasMeaningfulData()
        // Timestamps compare as ISO strings. Without both, the cloud copy never
        // counts as newer and the local data always does.
        let cloudIsNewer = remote.flatMap { remote in localChangedAt.map { remote.updatedAt > $0 } } ?? false
        let localIsNewer = remote.flatMap { remote in localChangedAt.map { $0 > remote.updatedAt } } ?? true

        if let remote, !meaningful || cloudIsNewer {
            do { try restoreCloudData(remote) } catch { report(error) }
        } else if meaningful, localIsNewer {
            uploadLocalData()
        } else {
            status = .synced
            lastSyncedAt = remote?.updatedAt ?? meta.cloudUpdatedAt
            error = nil
        }

        subscribeToLocalData()

        // A copy held back during a workout lands once the workout is over.
        ActiveWorkoutStore.shared.changed
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self, let held = self.heldForWorkout,
                      ActiveWorkoutStore.shared.session == nil else { return }
                do { try self.restoreCloudData(held) } catch { self.report(error) }
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                // Do not depend on a debounce surviving suspension. Backgrounding
                // is the last guaranteed opportunity to persist a just-made change.
                guard let self else { return }
                let meta = self.readMeta()
                if meta.localChangedAt != meta.cloudUpdatedAt { self.uploadLocalData() }
            }
            .store(in: &cancellables)
    }

    /// Used by Settings for an explicit retry and immediately after clearing.
    @discardableResult
    func syncNow() -> Bool {
        start()
        return uploadLocalData()
    }
}
