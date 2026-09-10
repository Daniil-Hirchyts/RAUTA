import Combine
import Foundation
import UIKit

/// Keeps the compact JSON backup in iCloud's key-value store. KVS is the right
/// fit for this app's structured preferences and workout history: it survives
/// uninstall, follows the user's iCloud account, and remains available offline
/// from the system cache.
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
            throw TrainingPersistenceError("The RAUTA backup is too large for iCloud sync.")
        }
        store.set(record.data, forKey: dataKey)
        store.set(record.updatedAt, forKey: updatedAtKey)
        store.synchronize()
    }

    static let externalChange = NSUbiquitousKeyValueStore.didChangeExternallyNotification
}

@MainActor
final class ICloudSync: ObservableObject {
    static let shared = ICloudSync()

    enum Status: String {
        case checking, syncing, synced, unavailable, error
    }

    @Published private(set) var status: Status = .checking
    @Published private(set) var lastSyncedAt: String?
    @Published private(set) var error: String?

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

    private func restoreCloudData(_ record: ICloudBackupRecord) throws {
        applyingCloudBackup = true
        defer { applyingCloudBackup = false }
        try AppBackup.importBackup(record.data)
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
        status = .syncing
        error = nil

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

        NotificationCenter.default
            .publisher(for: ICloudBackupStore.externalChange)
            .sink { [weak self] _ in
                guard let record = ICloudBackupStore.read() else { return }
                Task { @MainActor in self?.acceptExternalChange(record) }
            }
            .store(in: &cancellables)

        let remote = ICloudBackupStore.read()
        let meta = readMeta()
        let localChangedAt = meta.localChangedAt
        let meaningful = AppBackup.hasMeaningfulData()

        if let remote,
           !meaningful || (localChangedAt != nil && remote.updatedAt > localChangedAt!) {
            do { try restoreCloudData(remote) } catch { report(error) }
        } else if meaningful,
                  remote == nil || localChangedAt == nil || localChangedAt! > remote!.updatedAt {
            uploadLocalData()
        } else {
            status = .synced
            lastSyncedAt = remote?.updatedAt ?? meta.cloudUpdatedAt
            error = nil
        }

        subscribeToLocalData()

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
