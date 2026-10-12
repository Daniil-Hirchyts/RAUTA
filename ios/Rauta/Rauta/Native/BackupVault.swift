import Combine
import Foundation
import Observation
import UIKit

/// One complete backup file the vault keeps.
nonisolated struct BackupGeneration: Identifiable, Hashable, Sendable {
    enum Reason: String, Sendable {
        case automatic
        case manual
        /// The data as it was just before a restore replaced it: what "undo
        /// restore" puts back.
        case beforeRestore = "before-restore"
        /// A copy that arrived in iCloud Drive alongside another device's.
        case conflict
    }

    enum Location: String, Sendable { case device, iCloudDrive }

    var url: URL
    var createdAt: String
    var reason: Reason
    var location: Location
    var counts: BackupCounts?

    var id: String { location.rawValue + "/" + url.lastPathComponent }
}

/// A restore that started and never finished: the app went away between
/// replacing the first store and the last.
nonisolated struct InterruptedRestore: Codable, Hashable, Sendable {
    var startedAt: String
    /// The file being restored.
    var sourceFile: String
    /// The copy of the data taken just before, inside the vault.
    var safetyFile: String
}

/// Complete backups of everything — workouts, every logged set, plans, load
/// settings, profile and preferences — kept as verified files.
///
/// Training history grows with every set, so it is kept in files rather than
/// in iCloud's key-value store, whose whole allowance is 1 MB. The files live
/// in the app's Documents folder: they travel with the iPhone's own iCloud or
/// computer backup, survive an app crash, and can be copied out from the Files
/// app (On My iPhone › Rauta › Backups) without opening RAUTA at all. When the
/// app has an iCloud Drive container, the newest copy is mirrored there too,
/// for restoring on another device.
///
/// Every file is written atomically and read back before an older one is
/// pruned, so a crash or a full disk mid-write leaves the previous backups
/// untouched. Nothing here ever restores on its own: a restore is always a
/// choice someone makes, preceded by a copy of the data it replaces.
@MainActor
@Observable
final class BackupVault {
    static let shared = BackupVault()

    /// How many automatic and manual backups are kept on the device.
    nonisolated static let keep = 12
    /// After a change, how long the vault waits for more before backing up.
    static let quietSeconds: Double = 20
    /// While a workout runs, sets change by the minute; the draft is already
    /// journaled, so a backup every few minutes is plenty.
    static let duringWorkoutSeconds: Double = 300

    private(set) var generations: [BackupGeneration] = []
    private(set) var lastSuccessAt: String?
    private(set) var lastFailure: String?
    private(set) var lastFailureAt: String?
    private(set) var working = false
    private(set) var interruptedRestore: InterruptedRestore?
    /// Whether an iCloud Drive container is available to mirror into.
    private(set) var iCloudDriveAvailable = false
    /// When the data last changed in a way no backup holds yet.
    private(set) var dirtySince: Date?

    /// Tests point the vault at a folder of their own.
    static var folderOverride: URL?
    static var cloudFolderOverride: URL?

    private var started = false
    private var pending: Task<Void, Never>?
    private var lastBackupAt: Date?
    /// An automatic backup being written away from the main actor.
    private var inFlight = false
    /// Moves on with every change, so a backup that finishes knows whether
    /// it holds the latest one.
    private var changes = 0
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: Places

    static var folder: URL {
        folderOverride ?? URL.documentsDirectory.appending(path: "Backups", directoryHint: .isDirectory)
    }

    /// The iCloud Drive container's Backups folder, when the app has one.
    static var cloudFolder: URL? {
        if let cloudFolderOverride { return cloudFolderOverride }
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        return container.appending(path: "Documents/Backups", directoryHint: .isDirectory)
    }

    private static var markerURL: URL { folder.appending(path: ".restore-in-progress.json") }

    // MARK: Starting

    /// Reads what is on disk, notices a restore that never finished, and
    /// starts following the stores.
    func start() {
        guard !started else { return }
        started = true
        refresh()
        subscribe()
        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                // The last moment a backup is sure to run before suspension.
                guard let self, self.dirtySince != nil else { return }
                self.backUp(reason: .automatic)
            }
            .store(in: &cancellables)
        // A first backup on a device that has data and none yet.
        if generations.isEmpty, AppBackup.hasMeaningfulData() { schedule(after: 2) }
    }

    /// Re-reads the folders: the backups kept, the last success, a restore
    /// left unfinished.
    func refresh() {
        Self.removeLeftoverTemporaryFiles()
        iCloudDriveAvailable = Self.cloudFolder != nil
        var found = Self.list(Self.folder, location: .device)
        if let cloud = Self.cloudFolder {
            Self.preserveConflicts(in: cloud)
            found += Self.list(cloud, location: .iCloudDrive)
        }
        generations = found.sorted { $0.createdAt > $1.createdAt }
        lastSuccessAt = generations.first { $0.location == .device && $0.reason != .beforeRestore }?.createdAt
        interruptedRestore = (try? Data(contentsOf: Self.markerURL))
            .flatMap { try? JSONDecoder().decode(InterruptedRestore.self, from: $0) }
    }

    private func subscribe() {
        let publishers: [AnyPublisher<Void, Never>] = [
            TrainingRecordsStore.shared.changed.eraseToAnyPublisher(),
            WorkoutsStore.shared.changed.eraseToAnyPublisher(),
            FavoritesStore.shared.changed.eraseToAnyPublisher(),
            FiltersStore.shared.changed.eraseToAnyPublisher(),
            SettingsStore.shared.changed.eraseToAnyPublisher(),
            TrainingProfileStore.shared.changed.eraseToAnyPublisher(),
        ]
        for publisher in publishers {
            publisher
                .sink { [weak self] in self?.noteChange() }
                .store(in: &cancellables)
        }
    }

    private func noteChange() {
        changes += 1
        if dirtySince == nil { dirtySince = Date() }
        let running = ActiveWorkoutStore.shared.session != nil
        if running, let last = lastBackupAt, Date().timeIntervalSince(last) < Self.duringWorkoutSeconds {
            let wait = Self.duringWorkoutSeconds - Date().timeIntervalSince(last)
            schedule(after: wait)
        } else {
            schedule(after: Self.quietSeconds)
        }
    }

    private func schedule(after seconds: Double) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.backUpInBackground()
        }
    }

    /// An automatic backup: the stores are read here, and the serialising,
    /// hashing, writing and reading back happen away from the main actor, so
    /// a growing history never holds up the screen.
    func backUpInBackground() {
        guard !inFlight else {
            schedule(after: 5)
            return
        }
        inFlight = true
        working = true
        let createdAt = ISOTime.now()
        let data = AppBackup.backupData(includeLocalTraining: true)
        let appVersion = AppBackup.appVersion
        let folder = Self.folder
        let cloud = Self.cloudFolder
        let snapshot = changes
        Task {
            let result = await Self.writeAway(
                data: data, createdAt: createdAt, appVersion: appVersion, folder: folder, cloud: cloud
            )
            inFlight = false
            working = false
            switch result {
            case .success:
                lastBackupAt = Date()
                if changes == snapshot { dirtySince = nil }
                lastFailure = nil
                lastFailureAt = nil
                Self.prune(folder)
                refresh()
            case .failure(let error):
                lastFailure = (error as? TrainingPersistenceError)?.message
                    ?? "The backup couldn't be saved. Free up some space on this iPhone and try again."
                lastFailureAt = createdAt
                Storage.report("Backing up", error)
            }
        }
    }

    @concurrent
    private nonisolated static func writeAway(
        data: [String: JSONValue],
        createdAt: String,
        appVersion: String,
        folder: URL,
        cloud: URL?
    ) async -> Result<BackupGeneration, Error> {
        let json = BackupArchive.envelope(data: data, createdAt: createdAt, appVersion: appVersion, complete: true).canonical
        do {
            let generation = try write(json, createdAt: createdAt, reason: .automatic, to: folder)
            if let cloud {
                Storage.attempt("Mirroring the backup to iCloud Drive") {
                    try mirror(json, createdAt: createdAt, to: cloud)
                }
            }
            return .success(generation)
        } catch {
            return .failure(error)
        }
    }

    // MARK: Backing up

    /// Writes a complete backup now. Returns it when it was written and read
    /// back intact; otherwise records why not and keeps every older backup.
    @discardableResult
    func backUp(reason: BackupGeneration.Reason = .manual) -> BackupGeneration? {
        pending?.cancel()
        pending = nil
        working = true
        defer { working = false }
        let createdAt = ISOTime.now()
        let json = AppBackup.createBackup(createdAt: createdAt, includeLocalTraining: true)
        do {
            let generation = try Self.write(json, createdAt: createdAt, reason: reason, to: Self.folder)
            lastBackupAt = Date()
            dirtySince = nil
            changes += 1
            lastFailure = nil
            lastFailureAt = nil
            Self.prune(Self.folder)
            if let cloud = Self.cloudFolder, reason != .beforeRestore {
                Storage.attempt("Mirroring the backup to iCloud Drive") {
                    try Self.mirror(json, createdAt: createdAt, to: cloud)
                }
            }
            refresh()
            return generation
        } catch {
            lastFailure = (error as? TrainingPersistenceError)?.message
                ?? "The backup couldn't be saved. Free up some space on this iPhone and try again."
            lastFailureAt = createdAt
            Storage.report("Backing up", error)
            return nil
        }
    }

    // MARK: Restoring

    /// Checks a backup without changing anything.
    func preview(_ json: String) throws -> BackupPreview {
        do { return try BackupArchive.inspect(json) } catch { throw TrainingPersistenceError(error.message) }
    }

    /// Restores a backup in place of the data on this iPhone. A copy of the
    /// data it replaces is kept first; ``undoLastRestore()`` puts it back.
    func restore(_ json: String, sourceName: String) throws {
        guard ActiveWorkoutStore.shared.session == nil else {
            throw TrainingPersistenceError("Finish or discard the workout in progress before restoring a backup.")
        }
        _ = try preview(json)
        guard let safety = backUp(reason: .beforeRestore) else {
            throw TrainingPersistenceError(
                "RAUTA couldn't save a copy of your current data first, so nothing was restored. "
                    + (lastFailure ?? "")
            )
        }
        let marker = InterruptedRestore(
            startedAt: ISOTime.now(),
            sourceFile: sourceName,
            safetyFile: safety.url.lastPathComponent
        )
        try Self.writeMarker(marker)
        try AppBackup.importBackup(json)
        Self.removeMarker()
        refresh()
        // The restored data is what a backup should hold from now on.
        backUp(reason: .automatic)
    }

    /// The copy taken before the most recent restore, if one is kept.
    var undoableRestore: BackupGeneration? {
        generations.first { $0.reason == .beforeRestore && $0.location == .device }
    }

    func undoLastRestore() throws {
        guard let safety = undoableRestore else {
            throw TrainingPersistenceError("There's no restore to undo.")
        }
        let json = try String(contentsOf: safety.url, encoding: .utf8)
        guard ActiveWorkoutStore.shared.session == nil else {
            throw TrainingPersistenceError("Finish or discard the workout in progress first.")
        }
        try AppBackup.importBackup(json)
        // Spent: undoing twice would put the restored data back.
        try? FileManager.default.removeItem(at: safety.url)
        Self.removeMarker()
        refresh()
        backUp(reason: .automatic)
    }

    /// Settles a restore the app was closed in the middle of: either finish
    /// it from the same file, or put back the copy taken before it began.
    func resolveInterruptedRestore(finish: Bool) throws {
        guard let interrupted = interruptedRestore else { return }
        let source = finish ? interrupted.sourceFile : interrupted.safetyFile
        let url = Self.folder.appending(path: source)
        guard let json = try? String(contentsOf: url, encoding: .utf8) else {
            Self.removeMarker()
            refresh()
            throw TrainingPersistenceError(
                finish
                    ? "The backup that was being restored is no longer available. Your data is as the restore left it."
                    : "The copy from before the restore is missing. Your data is as the restore left it."
            )
        }
        try AppBackup.importBackup(json)
        Self.removeMarker()
        refresh()
        backUp(reason: .automatic)
    }

    /// Copies a file the person picked into the vault before restoring from
    /// it, so an interrupted restore can be finished from the same file.
    func importIntoVault(_ json: String) throws -> String {
        let name = "rauta-import-\(Self.stamp(ISOTime.now())).json"
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: Self.folder.appending(path: name), options: .atomic)
        return name
    }

    /// Deletes every backup the vault keeps, here and in iCloud Drive — what
    /// "Clear all data" promises.
    func deleteAllBackups() {
        pending?.cancel()
        pending = nil
        try? FileManager.default.removeItem(at: Self.folder)
        if let cloud = Self.cloudFolder {
            let latest = cloud.appending(path: "rauta-backup-latest-automatic.json")
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: latest, options: .forDeleting, error: &coordinationError) { url in
                try? FileManager.default.removeItem(at: url)
            }
        }
        lastFailure = nil
        lastFailureAt = nil
        dirtySince = nil
        refresh()
    }

    // MARK: Files

    static func stamp(_ iso: String) -> String {
        iso.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: ".", with: "-")
    }

    /// What the vault knows about each backup it wrote — when, why and what
    /// it holds — so listing them never re-reads every file. A backup is
    /// checked in full when it is written and again before it is restored.
    nonisolated struct IndexEntry: Codable, Sendable {
        var createdAt: String
        var reason: String
        var counts: BackupCounts?
    }

    nonisolated static func indexURL(_ folder: URL) -> URL { folder.appending(path: ".index.json") }

    nonisolated static func readIndex(_ folder: URL) -> [String: IndexEntry] {
        guard let data = try? Data(contentsOf: indexURL(folder)),
              let index = try? JSONDecoder().decode([String: IndexEntry].self, from: data)
        else { return [:] }
        return index
    }

    nonisolated static func writeIndex(_ index: [String: IndexEntry], _ folder: URL) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexURL(folder), options: .atomic)
    }

    nonisolated static func fileName(createdAt: String, reason: BackupGeneration.Reason) -> String {
        let stamp = createdAt.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: ".", with: "-")
        return "rauta-backup-\(stamp)-\(reason.rawValue).json"
    }

    /// Writes atomically, then reads the file back and checks it whole.
    nonisolated static func write(
        _ json: String,
        createdAt: String,
        reason: BackupGeneration.Reason,
        to folder: URL
    ) throws -> BackupGeneration {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName(createdAt: createdAt, reason: reason))
        try Data(json.utf8).write(to: url, options: .atomic)
        let preview: BackupPreview
        do {
            preview = try BackupArchive.inspect(String(contentsOf: url, encoding: .utf8))
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw TrainingPersistenceError("The backup didn't read back correctly, so it was discarded. Older backups are untouched.")
        }
        var index = readIndex(folder)
        index[url.lastPathComponent] = IndexEntry(createdAt: createdAt, reason: reason.rawValue, counts: preview.counts)
        writeIndex(index, folder)
        return BackupGeneration(url: url, createdAt: createdAt, reason: reason, location: .device, counts: preview.counts)
    }

    /// The backups in a folder, newest first. Files that are not backups, or
    /// fail their checks, are left alone and not listed.
    /// The backups in a folder, newest first, from the vault's index. A file
    /// the index doesn't know yet — written by an older build, or before a
    /// crash — is checked in full once and added; one that fails its checks is
    /// left alone and not listed.
    nonisolated static func list(_ folder: URL, location: BackupGeneration.Location) -> [BackupGeneration] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var index = readIndex(folder)
        var changed = false
        var names = Set<String>()
        let generations = files.compactMap { url -> BackupGeneration? in
            let name = url.lastPathComponent
            guard name.hasPrefix("rauta-backup-"), url.pathExtension == "json" else { return nil }
            names.insert(name)
            let reason: BackupGeneration.Reason = {
                for candidate in [BackupGeneration.Reason.beforeRestore, .conflict, .manual, .automatic]
                where name.hasSuffix("-\(candidate.rawValue).json") { return candidate }
                return .automatic
            }()
            if let entry = index[name] {
                return BackupGeneration(url: url, createdAt: entry.createdAt, reason: reason, location: location, counts: entry.counts)
            }
            guard let json = try? String(contentsOf: url, encoding: .utf8),
                  let preview = try? BackupArchive.inspect(json)
            else { return nil }
            let createdAt = preview.createdAt ?? ""
            index[name] = IndexEntry(createdAt: createdAt, reason: reason.rawValue, counts: preview.counts)
            changed = true
            return BackupGeneration(url: url, createdAt: createdAt, reason: reason, location: location, counts: preview.counts)
        }
        for name in index.keys where !names.contains(name) {
            index[name] = nil
            changed = true
        }
        if changed { writeIndex(index, folder) }
        return generations.sorted { $0.createdAt > $1.createdAt }
    }

    /// Keeps the newest ``keep`` backups and the newest copy from before a
    /// restore; never the last good backup.
    nonisolated static func prune(_ folder: URL) {
        let all = list(folder, location: .device)
        let regular = all.filter { $0.reason == .automatic || $0.reason == .manual }
        for old in regular.dropFirst(keep) {
            Storage.attempt("Pruning an old backup") { try FileManager.default.removeItem(at: old.url) }
        }
        let safety = all.filter { $0.reason == .beforeRestore }
        for old in safety.dropFirst(1) {
            Storage.attempt("Pruning an old pre-restore copy") { try FileManager.default.removeItem(at: old.url) }
        }
        // Files picked to restore from are copied in so an interrupted restore
        // can finish; only the latest two are worth keeping.
        let referenced = (try? Data(contentsOf: folder.appending(path: ".restore-in-progress.json")))
            .flatMap { try? JSONDecoder().decode(InterruptedRestore.self, from: $0) }?.sourceFile
        let imports = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("rauta-import-") && $0.lastPathComponent != referenced }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in imports.dropFirst(2) { try? FileManager.default.removeItem(at: old) }
    }

    /// Writes the newest backup into iCloud Drive through a file coordinator,
    /// so the iCloud daemon never reads a half-written file.
    nonisolated static func mirror(_ json: String, createdAt: String, to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "rauta-backup-latest-automatic.json")
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try Data(json.utf8).write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    /// When two devices wrote the iCloud Drive copy at once, iCloud keeps one
    /// and holds the other as a conflict version. Each conflict version is
    /// saved as a backup of its own before the conflict is marked resolved, so
    /// neither device's copy is lost — both appear in the restore list.
    static func preserveConflicts(in folder: URL) {
        let url = folder.appending(path: "rauta-backup-latest-automatic.json")
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !versions.isEmpty else { return }
        for (index, version) in versions.enumerated() {
            let modified = version.modificationDate.map { ISOTime.string(fromMillis: $0.timeIntervalSince1970 * 1000) }
                ?? ISOTime.now()
            let name = "rauta-backup-\(stamp(modified))-\(index)-conflict.json"
            Storage.attempt("Keeping an iCloud Drive conflict copy") {
                try FileManager.default.copyItem(at: version.url, to: folder.appending(path: name))
            }
            version.isResolved = true
        }
        Storage.attempt("Resolving iCloud Drive conflicts") {
            try NSFileVersion.removeOtherVersionsOfItem(at: url)
        }
    }

    /// An atomic write that was cut short leaves a temporary file behind; the
    /// backup it was replacing is still whole.
    static func removeLeftoverTemporaryFiles() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(".dat") || file.pathExtension == "tmp" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func writeMarker(_ marker: InterruptedRestore) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(marker).write(to: markerURL, options: .atomic)
    }

    private static func removeMarker() {
        try? FileManager.default.removeItem(at: markerURL)
    }
}
