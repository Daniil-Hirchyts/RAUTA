import SwiftUI
import UniformTypeIdentifiers

/// Backups and restoring, in plain terms: what is kept, where, when it last
/// worked, and how to get any of it back.
struct BackupScreen: View {
    private let store = AppStore.shared
    private let vault = BackupVault.shared

    @State private var importing = false
    /// A backup someone picked, checked and waiting for them to confirm.
    @State private var pending: PendingRestore?
    @State private var issue: String?
    @State private var confirmingUndo = false

    private struct PendingRestore: Identifiable {
        let id = UUID()
        var json: String
        var sourceName: String?
        var preview: BackupPreview
    }

    var body: some View {
        RautaScreen(title: "Backup & restore", onBack: store.navigation.pop) {
            ScrollView {
                VStack(spacing: 24) {
                    if let interrupted = vault.interruptedRestore {
                        interruptedSection(interrupted)
                    }
                    if !store.trainingRecords.persistenceIssues.isEmpty {
                        damagedRecordsSection
                    }
                    completeBackupsSection
                    iCloudSection
                    restoreSection
                    if let issue { InlineNotice(message: issue, isError: true) }
                }
                .padding(.horizontal, Theme.Metrics.contentInset)
                .padding(.bottom, 32)
            }
            .pageScroll()
        }
        .onAppear { vault.refresh() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            pick(result)
        }
        .alert(
            pending.map { title(for: $0.preview) } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { restore in
            Button("Restore", role: .destructive) { apply(restore) }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { restore in
            Text(message(for: restore.preview))
        }
        .alert("Undo the last restore?", isPresented: $confirmingUndo) {
            Button("Undo restore", role: .destructive, action: undoRestore)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This puts back your data exactly as it was just before the restore\(vault.undoableRestore.flatMap { RelativeMoment.text($0.createdAt) }.map { ", \($0)" } ?? "").")
        }
    }

    // MARK: Sections

    private var completeBackupsSection: some View {
        PageSection(title: "Complete backups") {
            PageRow(
                icon: vault.lastFailure == nil ? "checkmark.shield" : "exclamationmark.triangle",
                tint: vault.lastFailure == nil ? Theme.success : Theme.destructive,
                title: lastBackupTitle,
                detail: vault.lastFailure ?? lastBackupDetail
            ) {
                if vault.working {
                    ProgressView().accessibilityLabel("Backing up")
                }
            }
            PageNote(text: "Everything: workouts, every logged set, plans, load settings, profile and preferences. "
                + "Saved on this iPhone a few moments after you change something — the newest \(BackupVault.keep) are kept — "
                + "and included in your iPhone's own iCloud or computer backup. You can also find them in the Files app: "
                + "On My iPhone › Rauta › Backups."
                + (vault.iCloudDriveAvailable ? " The newest one is copied to iCloud Drive too." : ""))
            HStack(spacing: 10) {
                AppButton(vault.lastFailure == nil ? "Back up now" : "Try again", variant: .secondary, expands: true) {
                    backUpNow()
                }
                ShareLink(item: BackupExport(), preview: SharePreview("RAUTA backup")) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(Theme.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassControl(.clear, .capsule(height: 40)))
                .frame(minHeight: 44)
                .accessibilityHint("Saves one complete backup file wherever you choose")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    private var iCloudSection: some View {
        PageSection(title: "iCloud quick sync") {
            PageRow(icon: "icloud", tint: iCloudTint, title: iCloudTitle, detail: iCloudDetail) {
                if store.iCloud.status == .synced || store.iCloud.status == .error {
                    Button {
                        Haptics.trigger(.light)
                        store.iCloud.syncNow()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                    }
                    .buttonStyle(.glassControl(.clear, .circle(diameter: 40)))
                    .accessibilityLabel("Sync with iCloud now")
                }
            }
            PageNote(text: "Your profile, preferences, favourites, equipment and workout list sync through iCloud, "
                + "so another iPhone or iPad signed in to the same account picks them up. Copies from two devices are "
                + "merged — a workout added or deleted on either one is kept that way. Set-by-set history and plans "
                + "are too large for this sync and live in the complete backups.")
        }
    }

    @ViewBuilder private var restoreSection: some View {
        PageSection(title: "Restore") {
            if vault.undoableRestore != nil {
                PageActionRow(
                    icon: "arrow.uturn.backward",
                    title: "Undo the last restore",
                    detail: "Puts back your data from just before it."
                ) { confirmingUndo = true }
            }
            let restorable = vault.generations.filter { $0.reason != .beforeRestore }
            if restorable.isEmpty {
                PageNote(text: "No backups on this iPhone yet. The first one is made a few moments after you add or change something.")
            } else {
                ForEach(Array(restorable.prefix(8))) { generation in
                    PageActionRow(
                        icon: generation.location == .iCloudDrive ? "icloud.and.arrow.down" : "clock.arrow.circlepath",
                        title: (RelativeMoment.text(generation.createdAt) ?? generation.createdAt).capitalizedFirst,
                        detail: detail(for: generation)
                    ) { choose(generation) }
                }
            }
            PageActionRow(
                icon: "doc.badge.arrow.up",
                title: "Restore from a file…",
                detail: "A backup you exported or saved in Files.",
                showsDivider: false
            ) { importing = true }
        }
    }

    private func interruptedSection(_ interrupted: InterruptedRestore) -> some View {
        PageSection(title: "Restore interrupted", accent: Theme.destructive) {
            PageNote(
                text: "RAUTA closed in the middle of a restore\(RelativeMoment.text(interrupted.startedAt).map { " \($0)" } ?? ""). "
                    + "Some of your data may be from the backup and some from before. Finish the restore, or put back your data as it was.",
                tint: Theme.foreground
            )
            HStack(spacing: 10) {
                AppButton("Finish restore", variant: .primary, expands: true) { resolve(finish: true) }
                AppButton("Put back my data", variant: .secondary, expands: true) { resolve(finish: false) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    private var damagedRecordsSection: some View {
        PageSection(title: "Training records", accent: Theme.destructive) {
            PageNote(
                text: "Some training records couldn't be read when RAUTA opened, and were left out so the rest could load. "
                    + "Restoring a backup from before then brings them back; RAUTA keeps a copy of what's here now first.",
                tint: Theme.foreground
            )
        }
    }

    // MARK: Words

    private var lastBackupTitle: String {
        if vault.lastFailure != nil { return "The last backup didn't save" }
        guard let when = RelativeMoment.text(vault.lastSuccessAt) else { return "No backup yet" }
        return "Last backup \(when)"
    }

    private var lastBackupDetail: String? {
        if vault.dirtySince != nil { return "Recent changes are saved in a moment." }
        guard let latest = vault.generations.first(where: { $0.location == .device && $0.reason != .beforeRestore }),
              let counts = latest.counts else { return nil }
        return summary(counts)
    }

    private var iCloudTitle: String {
        switch store.iCloud.status {
        case .checking: return "Checking iCloud…"
        case .syncing: return "Syncing…"
        case .unavailable: return "iCloud is off"
        case .error: return "iCloud sync didn't go through"
        case .synced:
            if store.iCloud.heldForWorkout != nil { return "Waiting for your workout to end" }
            return RelativeMoment.text(store.iCloud.lastSyncedAt).map { "Synced \($0)" } ?? "Synced"
        }
    }

    private var iCloudDetail: String? {
        switch store.iCloud.status {
        case .unavailable: return "Sign in to iCloud in the Settings app to sync. Complete backups on this iPhone still work."
        case .error: return store.iCloud.error
        case .synced where store.iCloud.heldForWorkout != nil:
            return "Changes from your other device are applied once this workout is finished, so nothing changes mid-set."
        default: return nil
        }
    }

    private var iCloudTint: Color {
        switch store.iCloud.status {
        case .error: return Theme.destructive
        case .unavailable: return Theme.mutedForeground
        default: return Theme.primary
        }
    }

    private func summary(_ counts: BackupCounts) -> String {
        var parts = [Wording.countLabel(counts.workouts, "workout")]
        if counts.sessions > 0 { parts.append(Wording.countLabel(counts.sessions, "logged session")) }
        if counts.programs > 0 { parts.append(Wording.countLabel(counts.programs, "plan")) }
        return parts.joined(separator: " · ")
    }

    private func detail(for generation: BackupGeneration) -> String {
        var parts: [String] = []
        if generation.location == .iCloudDrive { parts.append("iCloud Drive") }
        if generation.reason == .manual { parts.append("Backed up by you") }
        if generation.reason == .conflict { parts.append("A second device's copy") }
        if let counts = generation.counts { parts.append(summary(counts)) }
        return parts.joined(separator: " · ")
    }

    private func title(for preview: BackupPreview) -> String {
        guard let when = RelativeMoment.text(preview.createdAt) else { return "Restore this backup?" }
        return "Restore the backup from \(when)?"
    }

    private func message(for preview: BackupPreview) -> String {
        var lines = ["It holds \(summary(preview.counts))."]
        lines.append("Restoring replaces the data on this iPhone. RAUTA keeps a copy of your current data first, so you can undo it.")
        lines += preview.warnings
        return lines.joined(separator: "\n\n")
    }

    // MARK: Actions

    private func backUpNow() {
        if vault.backUp(reason: .manual) != nil {
            Haptics.trigger(.success)
            RautaSpeech.shared.say("Backed up. Everything's safe.", reaction: .celebrate)
            issue = nil
        } else {
            Haptics.trigger(.warning)
        }
    }

    private func choose(_ generation: BackupGeneration) {
        do {
            let json = try String(contentsOf: generation.url, encoding: .utf8)
            let preview = try vault.preview(json)
            pending = PendingRestore(
                json: json,
                sourceName: generation.location == .device ? generation.url.lastPathComponent : nil,
                preview: preview
            )
            issue = nil
        } catch { capture(error) }
    }

    private func pick(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let json = try String(contentsOf: url, encoding: .utf8)
            pending = PendingRestore(json: json, sourceName: nil, preview: try vault.preview(json))
            issue = nil
        } catch {
            capture(error)
        }
    }

    private func apply(_ restore: PendingRestore) {
        pending = nil
        do {
            let source = try restore.sourceName ?? vault.importIntoVault(restore.json)
            try vault.restore(restore.json, sourceName: source)
            Haptics.trigger(.success)
            RautaSpeech.shared.say("Restored. Your training is back — and I kept a copy of what was here.", reaction: .celebrate)
            issue = nil
        } catch { capture(error) }
    }

    private func undoRestore() {
        do {
            try vault.undoLastRestore()
            Haptics.trigger(.success)
            RautaSpeech.shared.say("Put back exactly as it was before the restore.")
            issue = nil
        } catch { capture(error) }
    }

    private func resolve(finish: Bool) {
        do {
            try vault.resolveInterruptedRestore(finish: finish)
            Haptics.trigger(.success)
            issue = nil
        } catch { capture(error) }
    }

    private func capture(_ error: Error) {
        issue = (error as? TrainingPersistenceError)?.message
            ?? "That file couldn't be read. Pick the .json file RAUTA exported."
        Haptics.trigger(.warning)
    }
}

/// A backup that exists only once something asks for its file.
struct BackupExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { _ in
            SentTransferredFile(try await AppBackup.exportFileURL())
        }
    }
}

extension String {
    /// "today at 14:32" → "Today at 14:32".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
